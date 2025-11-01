package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"

	pb "github.com/dvaldivia/grpc-swift-2-example/server/gen/protos"
	"google.golang.org/grpc"
)

var (
	port         = flag.Int("port", 50051, "The server port")
	featuresFile = flag.String("features", "features.json", "Path to features JSON file")
)

func main() {
	flag.Parse()

	log.Printf("Starting RouteGuide gRPC server...")

	// Create TCP listener
	lis, err := net.Listen("tcp", fmt.Sprintf(":%d", *port))
	if err != nil {
		log.Fatalf("Failed to listen on port %d: %v", *port, err)
	}

	// Create RouteGuide server instance
	routeGuideServer, err := newServer(*featuresFile)
	if err != nil {
		log.Fatalf("Failed to create server: %v", err)
	}

	// Create gRPC server
	grpcServer := grpc.NewServer()

	// Register RouteGuide service
	pb.RegisterRouteGuideServer(grpcServer, routeGuideServer)

	log.Printf("Server listening on port %d", *port)
	log.Printf("Features loaded from: %s", *featuresFile)

	// Setup graceful shutdown
	go func() {
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
		<-sigChan

		log.Println("Received shutdown signal, stopping server...")
		grpcServer.GracefulStop()
		log.Println("Server stopped gracefully")
	}()

	// Start serving
	log.Println("RouteGuide server is ready to accept requests")
	if err := grpcServer.Serve(lis); err != nil {
		log.Fatalf("Failed to serve: %v", err)
	}
}
