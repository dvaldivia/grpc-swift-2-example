//
//  ContentView.swift
//  client
//
//  Created by Daniel Valdivia on 10/31/25.
//

import SwiftUI

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct ContentView: View {
    @StateObject private var service = RouteGuideService()
    @State private var results: String = "Tap a button to test gRPC calls..."
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with connection status
            VStack(spacing: 8) {
                Text("RouteGuide gRPC Client")
                    .font(.title2)
                    .fontWeight(.bold)

                HStack {
                    Circle()
                        .fill(service.isConnected ? Color.green : Color.red)
                        .frame(width: 12, height: 12)

                    Text(service.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !service.isConnected {
                    Button("Connect to Server") {
                        Task {
                            await service.connect()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Disconnect") {
                        Task {
                            await service.disconnect()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))

            Divider()

            // RPC Test Buttons
            ScrollView {
                VStack(spacing: 16) {
                    Text("gRPC Method Tests")
                        .font(.headline)
                        .padding(.top)

                    // Unary RPC
                    Button {
                        testGetFeature()
                    } label: {
                        Label("Get Feature (Unary)", systemImage: "location.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!service.isConnected || isLoading)

                    // Server Streaming RPC
                    Button {
                        testListFeatures()
                    } label: {
                        Label("List Features (Server Streaming)", systemImage: "list.bullet.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!service.isConnected || isLoading)

                    // Client Streaming RPC
                    Button {
                        testRecordRoute()
                    } label: {
                        Label("Record Route (Client Streaming)", systemImage: "arrow.up.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!service.isConnected || isLoading)

                    // Bidirectional Streaming RPC
                    Button {
                        testRouteChat()
                    } label: {
                        Label("Route Chat (Bidirectional)", systemImage: "bubble.left.and.bubble.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!service.isConnected || isLoading)

                    Divider()
                        .padding(.vertical, 8)

                    Button("Clear Results") {
                        results = ""
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                }
                .padding()
            }
            .frame(maxHeight: 300)

            Divider()

            // Results Display
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Results")
                        .font(.headline)
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)

                ScrollView {
                    Text(results)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color(uiColor: .systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .task {
            // Auto-connect on launch
            if !service.isConnected {
                await service.connect()
            }
        }
    }

    // MARK: - Test Methods

    private func testGetFeature() {
        Task {
            isLoading = true
            defer { isLoading = false }

            appendResult("\n🔵 Testing GetFeature (Unary RPC)...")
            appendResult("Request: Point(407838351, -746143763)")

            do {
                let result = try await service.getFeature(
                    latitude: 407838351,
                    longitude: -746143763
                )
                appendResult("✅ Response: \(result)")
            } catch {
                appendResult("❌ Error: \(error.localizedDescription)")
            }
        }
    }

    private func testListFeatures() {
        Task {
            isLoading = true
            defer { isLoading = false }

            appendResult("\n🟢 Testing ListFeatures (Server Streaming RPC)...")
            appendResult("Request: Rectangle from (400000000, -750000000) to (420000000, -730000000)")

            do {
                let features = try await service.listFeatures(
                    loLatitude: 400000000,
                    loLongitude: -750000000,
                    hiLatitude: 420000000,
                    hiLongitude: -730000000
                )
                appendResult("✅ Received \(features.count) features:")
                for feature in features {
                    appendResult(feature)
                }
            } catch {
                appendResult("❌ Error: \(error.localizedDescription)")
            }
        }
    }

    private func testRecordRoute() {
        Task {
            isLoading = true
            defer { isLoading = false }

            appendResult("\n🟡 Testing RecordRoute (Client Streaming RPC)...")
            appendResult("Sending \(RouteGuideService.samplePoints.count) points...")

            do {
                let summary = try await service.recordRoute(
                    points: RouteGuideService.samplePoints
                )
                appendResult("✅ \(summary)")
            } catch {
                appendResult("❌ Error: \(error.localizedDescription)")
            }
        }
    }

    private func testRouteChat() {
        Task {
            isLoading = true
            defer { isLoading = false }

            appendResult("\n🟣 Testing RouteChat (Bidirectional Streaming RPC)...")
            appendResult("Sending \(RouteGuideService.sampleNotes.count) notes...")

            do {
                let notes = try await service.routeChat(
                    notes: RouteGuideService.sampleNotes
                )
                appendResult("✅ Received \(notes.count) notes:")
                for note in notes {
                    appendResult(note)
                }
            } catch {
                appendResult("❌ Error: \(error.localizedDescription)")
            }
        }
    }

    private func appendResult(_ text: String) {
        results += text + "\n"
    }
}

// Fallback view for older OS versions
struct ContentViewFallback: View {
    var body: some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("This app requires iOS 18.0 or later")
                .padding()
        }
        .padding()
    }
}

#Preview {
    if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
        ContentView()
    } else {
        ContentViewFallback()
    }
}
