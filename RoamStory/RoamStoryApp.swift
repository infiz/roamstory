import SwiftData
import SwiftUI

@main
struct RoamStoryApp: App {
    var body: some Scene {
        WindowGroup {
            ModelContainerLoadingView()
        }
    }
}

private struct ModelContainerLoadingView: View {
    @State private var modelContainer: ModelContainer?
    @State private var loadErrorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let modelContainer {
                TripsListView()
                    .modelContainer(modelContainer)
            } else if let loadErrorMessage {
                ContentUnavailableView {
                    Label("Unable to Open RoamStory", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(loadErrorMessage)
                } actions: {
                    Button("Try Again") {
                        Task { await loadModelContainer() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Opening RoamStory…")
                        .font(.headline)
                    Text("Preparing your trip library")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Opening RoamStory")
            }
        }
        .task {
            guard modelContainer == nil, isLoading else { return }
            await loadModelContainer()
        }
    }

    @MainActor
    private func loadModelContainer() async {
        isLoading = true
        loadErrorMessage = nil
        await Task.yield()

        do {
            modelContainer = try await Task.detached(priority: .userInitiated) {
                let schema = Schema([
                    Trip.self,
                    TripSection.self,
                    ContentBlock.self,
                    MediaReference.self,
                ])
                return try ModelContainer(for: schema)
            }.value
        } catch {
            loadErrorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
