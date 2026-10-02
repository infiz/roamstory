import SwiftData
import SwiftUI
import FBSDKCoreKit
import GoogleSignIn
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
#if DEBUG
        if AppStoreScreenshotFixture.screen != nil { return true }
#endif
        guard Bundle.main.hasConfiguredFacebookLogin else {
            return true
        }
        return ApplicationDelegate.shared.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }
        guard Bundle.main.hasConfiguredFacebookLogin else {
            return false
        }
        return ApplicationDelegate.shared.application(
            app,
            open: url,
            sourceApplication: options[.sourceApplication] as? String,
            annotation: options[.annotation]
        )
    }
}

private extension Bundle {
    var hasConfiguredFacebookLogin: Bool {
        hasConfiguredString(forInfoDictionaryKey: "FacebookAppID")
            && hasConfiguredString(forInfoDictionaryKey: "FacebookClientToken")
    }

    func hasConfiguredString(forInfoDictionaryKey key: String) -> Bool {
        guard let value = object(forInfoDictionaryKey: key) as? String else {
            return false
        }
        return !value.isEmpty && !value.contains("$(") && !value.hasPrefix("replace-")
    }
}

@main
struct RoamStoryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authentication = AuthenticationStore()

    var body: some Scene {
        WindowGroup {
            ModelContainerLoadingView()
                .environmentObject(authentication)
        }
    }
}

private struct ModelContainerLoadingView: View {
    @State private var modelContainer: ModelContainer?
    @State private var loadErrorMessage: String?
    @State private var isLoading = true
#if DEBUG
    @State private var screenshotFixture: AppStoreScreenshotFixture?
#endif

    var body: some View {
        Group {
            if let modelContainer {
#if DEBUG
                if let screenshotFixture, let screen = AppStoreScreenshotFixture.screen {
                    AppStoreScreenshotView(fixture: screenshotFixture, screen: screen)
                        .modelContainer(modelContainer)
                } else {
                    TripsListView()
                        .modelContainer(modelContainer)
                }
#else
                TripsListView()
                    .modelContainer(modelContainer)
#endif
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
#if DEBUG
            if AppStoreScreenshotFixture.screen != nil {
                let fixture = try AppStoreScreenshotFixture.make()
                screenshotFixture = fixture
                modelContainer = fixture.container
                isLoading = false
                return
            }
#endif
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
