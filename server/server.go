package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math"
	"os"
	"sync"
	"time"

	pb "github.com/dvaldivia/grpc-swift-2-example/server/gen/protos"
)

// routeGuideServer implements the RouteGuide service
type routeGuideServer struct {
	pb.UnimplementedRouteGuideServer
	savedFeatures []*pb.Feature // pre-loaded features from JSON
	mu            sync.Mutex    // protects routeNotes
	routeNotes    map[string][]*pb.RouteNote
}

// newServer creates a new RouteGuide server and loads features from JSON file
func newServer(featuresFile string) (*routeGuideServer, error) {
	s := &routeGuideServer{
		routeNotes: make(map[string][]*pb.RouteNote),
	}

	if err := s.loadFeatures(featuresFile); err != nil {
		return nil, fmt.Errorf("failed to load features: %v", err)
	}

	log.Printf("Loaded %d features from %s", len(s.savedFeatures), featuresFile)
	return s, nil
}

// loadFeatures loads features from a JSON file
func (s *routeGuideServer) loadFeatures(filePath string) error {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return err
	}

	if err := json.Unmarshal(data, &s.savedFeatures); err != nil {
		return err
	}

	return nil
}

// GetFeature returns the feature at the given point (unary RPC)
func (s *routeGuideServer) GetFeature(ctx context.Context, point *pb.Point) (*pb.Feature, error) {
	log.Printf("GetFeature called with point: lat=%d, lon=%d", point.Latitude, point.Longitude)

	for _, feature := range s.savedFeatures {
		if feature.Location.Latitude == point.Latitude &&
			feature.Location.Longitude == point.Longitude {
			log.Printf("Found feature: %s", feature.Name)
			return feature, nil
		}
	}

	// No feature found, return unnamed feature
	log.Printf("No feature found at location")
	return &pb.Feature{
		Location: point,
		Name:     "",
	}, nil
}

// ListFeatures lists all features within the given bounding rectangle (server streaming RPC)
func (s *routeGuideServer) ListFeatures(rect *pb.Rectangle, stream pb.RouteGuide_ListFeaturesServer) error {
	log.Printf("ListFeatures called with rectangle: lo(%d,%d) hi(%d,%d)",
		rect.Lo.Latitude, rect.Lo.Longitude,
		rect.Hi.Latitude, rect.Hi.Longitude)

	count := 0
	for _, feature := range s.savedFeatures {
		if inRange(feature.Location, rect) {
			if err := stream.Send(feature); err != nil {
				return err
			}
			count++
			log.Printf("Sent feature: %s", feature.Name)
		}
	}

	log.Printf("ListFeatures completed: sent %d features", count)
	return nil
}

// RecordRoute records a route and returns statistics (client streaming RPC)
func (s *routeGuideServer) RecordRoute(stream pb.RouteGuide_RecordRouteServer) error {
	log.Printf("RecordRoute called")

	var pointCount, featureCount, distance int32
	var lastPoint *pb.Point
	startTime := time.Now()

	for {
		point, err := stream.Recv()
		if err == io.EOF {
			// Client has finished sending points
			endTime := time.Now()
			elapsedTime := int32(endTime.Sub(startTime).Seconds())

			summary := &pb.RouteSummary{
				PointCount:   pointCount,
				FeatureCount: featureCount,
				Distance:     distance,
				ElapsedTime:  elapsedTime,
			}

			log.Printf("RecordRoute completed: points=%d, features=%d, distance=%d meters, time=%d seconds",
				pointCount, featureCount, distance, elapsedTime)

			return stream.SendAndClose(summary)
		}
		if err != nil {
			return err
		}

		pointCount++
		log.Printf("Received point %d: lat=%d, lon=%d", pointCount, point.Latitude, point.Longitude)

		// Check if this point is a known feature
		for _, feature := range s.savedFeatures {
			if feature.Location.Latitude == point.Latitude &&
				feature.Location.Longitude == point.Longitude {
				featureCount++
				log.Printf("Point matches feature: %s", feature.Name)
			}
		}

		// Calculate distance from last point
		if lastPoint != nil {
			distance += calcDistance(lastPoint, point)
		}
		lastPoint = point
	}
}

// RouteChat receives and sends route notes (bidirectional streaming RPC)
func (s *routeGuideServer) RouteChat(stream pb.RouteGuide_RouteChatServer) error {
	log.Printf("RouteChat called")

	for {
		note, err := stream.Recv()
		if err == io.EOF {
			log.Printf("RouteChat completed")
			return nil
		}
		if err != nil {
			return err
		}

		key := serialize(note.Location)
		log.Printf("Received note at %s: %s", key, note.Message)

		s.mu.Lock()

		// Send all previously received notes at this location
		if notes, ok := s.routeNotes[key]; ok {
			for _, prevNote := range notes {
				if err := stream.Send(prevNote); err != nil {
					s.mu.Unlock()
					return err
				}
				log.Printf("Sent previous note: %s", prevNote.Message)
			}
		}

		// Store the new note
		s.routeNotes[key] = append(s.routeNotes[key], note)

		s.mu.Unlock()
	}
}

// Helper functions

// inRange checks if a point is within a rectangle
func inRange(point *pb.Point, rect *pb.Rectangle) bool {
	left := min(rect.Lo.Longitude, rect.Hi.Longitude)
	right := max(rect.Lo.Longitude, rect.Hi.Longitude)
	top := max(rect.Lo.Latitude, rect.Hi.Latitude)
	bottom := min(rect.Lo.Latitude, rect.Hi.Latitude)

	return point.Longitude >= left &&
		point.Longitude <= right &&
		point.Latitude >= bottom &&
		point.Latitude <= top
}

// serialize converts a point to a string key for the map
func serialize(point *pb.Point) string {
	return fmt.Sprintf("%d,%d", point.Latitude, point.Longitude)
}

// calcDistance calculates the distance between two points using the Haversine formula
// Returns distance in meters
func calcDistance(p1, p2 *pb.Point) int32 {
	const earthRadiusMeters = 6371000 // Earth radius in meters

	lat1 := toRadians(float64(p1.Latitude) / 1e7)
	lat2 := toRadians(float64(p2.Latitude) / 1e7)
	lon1 := toRadians(float64(p1.Longitude) / 1e7)
	lon2 := toRadians(float64(p2.Longitude) / 1e7)

	dlat := lat2 - lat1
	dlon := lon2 - lon1

	a := math.Sin(dlat/2)*math.Sin(dlat/2) +
		math.Cos(lat1)*math.Cos(lat2)*
			math.Sin(dlon/2)*math.Sin(dlon/2)

	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))

	distance := earthRadiusMeters * c
	return int32(distance)
}

// toRadians converts degrees to radians
func toRadians(degrees float64) float64 {
	return degrees * math.Pi / 180
}

func min(a, b int32) int32 {
	if a < b {
		return a
	}
	return b
}

func max(a, b int32) int32 {
	if a > b {
		return a
	}
	return b
}
