import Foundation
import GRPCCore
import GRPCProtobuf
import GRPCNIOTransportHTTP2
import Combine
import SwiftProtobuf
import grpc_protobuf

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
class RouteGuideService: ObservableObject {
    private var grpcClient: GRPCClient<HTTP2ClientTransport.Posix>?
    private var client: Routeguide_RouteGuide.Client<HTTP2ClientTransport.Posix>?
    private var connectionTask: Task<Void, Never>?

    @Published var isConnected = false
    @Published var statusMessage = "Not connected"

    // MARK: - Connection Management

    func connect(host: String = "127.0.0.1", port: Int = 50051) async {
        do {
            statusMessage = "Connecting to \(host):\(port)..."

            let grpcClient = GRPCClient(
                transport: try .http2NIOPosix(
                    target: .dns(host: host, port: port),
                    transportSecurity: .plaintext
                )
            )

            self.grpcClient = grpcClient
            self.client = Routeguide_RouteGuide.Client(wrapping: grpcClient)

            // Start the client connection in a background task
            connectionTask = Task {
                do {
                    try await grpcClient.runConnections()
                } catch {
                    await MainActor.run {
                        self.isConnected = false
                        self.statusMessage = "Connection error: \(error.localizedDescription)"
                    }
                }
            }

            self.isConnected = true
            self.statusMessage = "Connected to \(host):\(port)"
        } catch {
            isConnected = false
            statusMessage = "Connection failed: \(error.localizedDescription)"
        }
    }

    func disconnect() async {
        client = nil
        if let grpcClient = grpcClient {
            grpcClient.beginGracefulShutdown()
            self.grpcClient = nil
        }

        // Wait for the connection task to complete
        connectionTask?.cancel()
        connectionTask = nil

        isConnected = false
        statusMessage = "Disconnected"
    }

    // MARK: - RPC Methods

    /// Unary RPC: Get a feature at a specific point
    func getFeature(latitude: Int32, longitude: Int32) async throws -> String {
        guard let client = client else {
            throw RouteGuideError.notConnected
        }
        let point = Routeguide_Point.with {
            $0.latitude = latitude
            $0.longitude = longitude
        }

        let request = ClientRequest(message: point)
        let feature = try await client.getFeature(request: request)

        if feature.name.isEmpty {
            return "No feature found at (\(latitude), \(longitude))"
        } else {
            return "Feature: \(feature.name) at (\(feature.location.latitude), \(feature.location.longitude))"
        }
    }

    /// Server Streaming RPC: List all features in a rectangle
    func listFeatures(
        loLatitude: Int32,
        loLongitude: Int32,
        hiLatitude: Int32,
        hiLongitude: Int32
    ) async throws -> [String] {
        guard let client = client else {
            throw RouteGuideError.notConnected
        }

        let rectangle = Routeguide_Rectangle.with {
            $0.lo = Routeguide_Point.with {
                $0.latitude = loLatitude
                $0.longitude = loLongitude
            }
            $0.hi = Routeguide_Point.with {
                $0.latitude = hiLatitude
                $0.longitude = hiLongitude
            }
        }

        let request = ClientRequest(message: rectangle)
        var features: [String] = []

        try await client.listFeatures(request: request) { response in
            for try await feature in response.messages {
                if !feature.name.isEmpty {
                    features.append("  - \(feature.name) at (\(feature.location.latitude), \(feature.location.longitude))")
                }
            }
        }

        return features
    }

    /// Client Streaming RPC: Send multiple points and get a route summary
    func recordRoute(points: [Routeguide_Point]) async throws -> String {
        guard let client = client else {
            throw RouteGuideError.notConnected
        }

        let request = StreamingClientRequest { writer in
            for point in points {
                try await writer.write(point)
            }
        }

        let summary = try await client.recordRoute(request: request)

        return """
        Route Summary:
          - Points: \(summary.pointCount)
          - Features: \(summary.featureCount)
          - Distance: \(summary.distance) meters
          - Elapsed Time: \(summary.elapsedTime) seconds
        """
    }

    /// Bidirectional Streaming RPC: Chat with route notes
    func routeChat(notes: [Routeguide_RouteNote]) async throws -> [String] {
        guard let client = client else {
            throw RouteGuideError.notConnected
        }

        var receivedNotes: [String] = []

        let request = StreamingClientRequest { writer in
            for note in notes {
                try await writer.write(note)
                // Small delay between sends to simulate real chat
                try await Task.sleep(for: .milliseconds(100))
            }
        }

        try await client.routeChat(request: request) { response in
            for try await note in response.messages {
                receivedNotes.append("  📍 at (\(note.location.latitude), \(note.location.longitude)): \(note.message)")
            }
        }

        return receivedNotes
    }
}

// MARK: - Error Types

enum RouteGuideError: LocalizedError {
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to gRPC server. Please connect first."
        }
    }
}

// MARK: - Sample Data

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension RouteGuideService {
    static let samplePoints: [Routeguide_Point] = [
        Routeguide_Point.with { $0.latitude = 407838351; $0.longitude = -746143763 },
        Routeguide_Point.with { $0.latitude = 408122808; $0.longitude = -743999179 },
        Routeguide_Point.with { $0.latitude = 413628156; $0.longitude = -749015468 },
        Routeguide_Point.with { $0.latitude = 419999544; $0.longitude = -740371136 },
        Routeguide_Point.with { $0.latitude = 414008389; $0.longitude = -743951297 },
    ]

    static let sampleNotes: [Routeguide_RouteNote] = [
        Routeguide_RouteNote.with {
            $0.location = Routeguide_Point.with { $0.latitude = 407838351; $0.longitude = -746143763 }
            $0.message = "First note at Patriots Path"
        },
        Routeguide_RouteNote.with {
            $0.location = Routeguide_Point.with { $0.latitude = 408122808; $0.longitude = -743999179 }
            $0.message = "Second note at Whippany"
        },
        Routeguide_RouteNote.with {
            $0.location = Routeguide_Point.with { $0.latitude = 407838351; $0.longitude = -746143763 }
            $0.message = "Back at Patriots Path!"
        },
    ]
}
