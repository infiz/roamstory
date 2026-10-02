#if DEBUG
import SwiftData
import SwiftUI

/// Uses disposable in-memory data and real app views, only for simulator captures.
@MainActor
struct AppStoreScreenshotFixture {
    let container: ModelContainer
    let trip: Trip
    let routes: [String: Int]

    static var screen: String? {
        ProcessInfo.processInfo.arguments.first {
            $0.hasPrefix("--app-store-screenshot=")
        }?.split(separator: "=", maxSplits: 1).last.map(String.init)
    }

    static func make() throws -> Self {
        let schema = Schema([Trip.self, TripSection.self, ContentBlock.self, MediaReference.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        guard let directory = ProcessInfo.processInfo.environment["ROAMSTORY_SCREENSHOT_PHOTOS_PATH"] else {
            throw NSError(domain: "RoamStoryScreenshot", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Missing screenshot asset directory"])
        }
        let sourceURL = URL(fileURLWithPath: directory).deletingLastPathComponent()
            .appendingPathComponent("journey.json")
        let source = try JSONDecoder().decode(JourneySource.self, from: Data(contentsOf: sourceURL))
        let start = try sourceDate(source.startDate)
        let end = try sourceDate(source.endDate)
        let trip = Trip(title: source.title, subtitle: source.subtitle,
                        createdAt: start, modifiedAt: end, startDate: start, endDate: end)
        context.insert(trip)
        var routes: [String: Int] = [:]
        for (index, chapter) in source.sections.enumerated() {
            let date = try sourceDate(chapter.date)
            var blocks: [ContentBlock] = []
            for (blockIndex, item) in chapter.blocks.enumerated() {
                let references = try (item.photos ?? []).enumerated().map { photoIndex, photo in
                    try media(photo.file, index: photoIndex, caption: photo.caption)
                }
                blocks.append(ContentBlock(type: item.type, sortIndex: blockIndex, createdAt: date,
                                           title: item.title ?? "", text: item.text ?? "",
                                           caption: item.caption ?? "",
                                           mapDescription: item.mapDescription ?? "",
                                           mapPlaceName: item.mapPlaceName ?? "",
                                           mapLatitude: item.mapLatitude, mapLongitude: item.mapLongitude,
                                           mediaReferences: references))
            }
            let section = TripSection(title: chapter.title, kind: chapter.kind,
                                      createdAt: date, modifiedAt: date, sortIndex: index,
                                      occurredAt: date, placeName: chapter.placeName, blocks: blocks)
            context.insert(section)
            section.trip = trip
            for (screen, key) in source.screenshotSections where key == chapter.key {
                routes[screen] = index + 1
            }
        }
        guard ["write", "photo", "gallery", "map"].allSatisfy({ routes[$0] != nil }) else {
            throw NSError(domain: "RoamStoryScreenshot", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Missing screenshot chapter mapping"])
        }
        try context.save()
        return Self(container: container, trip: trip, routes: routes)
    }

    private static func sourceDate(_ value: String) throws -> Date {
        guard let date = ISO8601DateFormatter().date(from: value + "T12:00:00Z") else {
            throw NSError(domain: "RoamStoryScreenshot", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid journey date: \(value)"])
        }
        return date
    }

    private struct JourneySource: Decodable {
        let title: String
        let subtitle: String
        let startDate: String
        let endDate: String
        let screenshotSections: [String: String]
        let sections: [ChapterSource]
    }

    private struct ChapterSource: Decodable {
        let key: String
        let title: String
        let kind: SectionKind
        let date: String
        let placeName: String
        let blocks: [BlockSource]
    }

    private struct BlockSource: Decodable {
        let type: BlockType
        let title: String?
        let text: String?
        let caption: String?
        let mapDescription: String?
        let mapPlaceName: String?
        let mapLatitude: Double?
        let mapLongitude: Double?
        let photos: [PhotoSource]?
    }

    private struct PhotoSource: Decodable {
        let file: String
        let caption: String
    }

    private static func media(_ filename: String, index: Int = 0, caption: String) throws -> MediaReference {
        let identifier = "app-store-demo:\(filename)"
        guard let image = image(for: identifier) else {
            throw NSError(domain: "RoamStoryScreenshot", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Missing screenshot demo image: \(filename)"])
        }
        PhotoAssetView.seedScreenshotImage(image, identifier: identifier)
        return MediaReference(localIdentifier: identifier, kind: .image,
                              originalFilename: filename, caption: caption, sortIndex: index)
    }

    static func image(for identifier: String) -> UIImage? {
        guard screen != nil, identifier.hasPrefix("app-store-demo:"),
              let directory = ProcessInfo.processInfo.environment["ROAMSTORY_SCREENSHOT_PHOTOS_PATH"] else {
            return nil
        }
        let filename = String(identifier.dropFirst("app-store-demo:".count))
        return UIImage(contentsOfFile: URL(fileURLWithPath: directory).appendingPathComponent(filename).path)
    }
}

@MainActor
struct AppStoreScreenshotView: View {
    let fixture: AppStoreScreenshotFixture
    let screen: String
    @State private var path: [Int] = []
    @State private var isExporting = false

    var body: some View {
        Group {
            if screen == "trips" {
                TripsListView()
            } else {
                NavigationStack(path: $path) {
                    Color.clear
                        .navigationTitle("Trips")
                        .navigationDestination(for: Int.self) { route in
                            if route == 0 {
                                TripEditorView(trip: fixture.trip)
                            } else {
                                SectionEditorView(section: fixture.trip.orderedSections[route - 1])
                            }
                        }
                }
                .sheet(isPresented: $isExporting) {
                    DocxExportView(title: fixture.trip.title, sections: fixture.trip.orderedSections,
                                   allowsSelection: true)
                }
                .task {
                    guard path.isEmpty else { return }
                    if let route = fixture.routes[screen] {
                        path = [0, route]
                    } else {
                        path = [0]
                    }
                    if screen == "export" { isExporting = true }
                }
            }
        }
        .task {
            if let marker = ProcessInfo.processInfo.environment["ROAMSTORY_SCREENSHOT_READY_PATH"] {
                try? Data(screen.utf8).write(to: URL(fileURLWithPath: marker), options: .atomic)
            }
        }
    }
}
#endif
