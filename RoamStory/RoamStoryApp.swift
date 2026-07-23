import SwiftData
import SwiftUI

@main
struct RoamStoryApp: App {
    private let modelContainer: ModelContainer = {
        let schema = Schema([
            Trip.self,
            TripSection.self,
            ContentBlock.self,
            MediaReference.self,
        ])

        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Unable to create the RoamStory model container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            TripsListView()
        }
        .modelContainer(modelContainer)
    }
}
