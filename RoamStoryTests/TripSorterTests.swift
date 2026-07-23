import SwiftData
import XCTest
@testable import RoamStory

final class TripSorterTests: XCTestCase {
    func testSortsTitlesUsingLocalizedCaseInsensitiveComparison() {
        let alpha = Trip(title: "alpha")
        let beta = Trip(title: "Beta")
        let trips = TripSorter.sort(
            [beta, alpha],
            by: .title,
            direction: .ascending,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(trips.map(\.title), ["alpha", "Beta"])
    }

    func testSortsModifiedDateDescending() {
        let older = Trip(
            title: "Older",
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = Trip(
            title: "Newer",
            modifiedAt: Date(timeIntervalSince1970: 200)
        )

        let trips = TripSorter.sort(
            [older, newer],
            by: .modified,
            direction: .descending
        )

        XCTAssertEqual(trips.map(\.title), ["Newer", "Older"])
    }

    func testMapsLegacySectionKindsToCurrentCategories() {
        XCTAssertEqual(SectionKind.storedValue("location"), .place)
        XCTAssertEqual(SectionKind.storedValue("meal"), .foodAndDrink)
        XCTAssertEqual(SectionKind.storedValue("animal"), .natureAndWildlife)
        XCTAssertEqual(SectionKind.storedValue("experience"), .activity)
        XCTAssertEqual(SectionKind.storedValue("unknown"), .other)
    }

    func testParagraphStoresIndependentTitleAndAttributedContent() throws {
        let styledText = NSAttributedString(
            string: "Tokyo at night",
            attributes: [
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .link: URL(string: "https://example.com/tokyo")!,
            ]
        )
        let archived = try NSKeyedArchiver.archivedData(
            withRootObject: styledText,
            requiringSecureCoding: true
        )
        let paragraph = ContentBlock(
            type: .paragraph,
            title: "First Impressions",
            text: styledText.string,
            attributedTextData: archived
        )

        XCTAssertEqual(paragraph.title, "First Impressions")
        XCTAssertEqual(paragraph.text, "Tokyo at night")
        XCTAssertNotNil(paragraph.attributedTextData)
        let decoded = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: NSAttributedString.self,
            from: archived
        )
        XCTAssertEqual(
            decoded?.attribute(.link, at: 0, effectiveRange: nil) as? URL,
            URL(string: "https://example.com/tokyo")
        )
    }

    func testGalleryUsesPersistedPhotoOrder() {
        let first = MediaReference(
            localIdentifier: "first",
            kind: .image,
            sortIndex: 1
        )
        let second = MediaReference(
            localIdentifier: "second",
            kind: .image,
            sortIndex: 0
        )
        let gallery = ContentBlock(type: .gallery, mediaReferences: [first, second])

        XCTAssertEqual(
            gallery.orderedMediaReferences.map(\.localIdentifier),
            ["second", "first"]
        )
    }

    func testMovesBlocksToExactDividerInsertionPoints() {
        let first = ContentBlock(type: .paragraph, sortIndex: 0, text: "First")
        let second = ContentBlock(type: .paragraph, sortIndex: 1, text: "Second")
        let third = ContentBlock(type: .paragraph, sortIndex: 2, text: "Third")
        let blocks = [first, second, third]

        let movedDown = BlockOrdering.moving(
            blocks,
            sourceID: first.id,
            toInsertionIndex: 2
        )
        XCTAssertEqual(movedDown?.map(\.text), ["Second", "First", "Third"])

        let movedUp = BlockOrdering.moving(
            blocks,
            sourceID: third.id,
            toInsertionIndex: 1
        )
        XCTAssertEqual(movedUp?.map(\.text), ["First", "Third", "Second"])

        XCTAssertNil(BlockOrdering.moving(
            blocks,
            sourceID: second.id,
            toInsertionIndex: 1
        ))
    }

    func testTripAndSectionDateRangesUseHourPrecision() {
        let start = Date(timeIntervalSince1970: 1_800_123_456)
        let end = start.addingTimeInterval(7_500)
        let trip = Trip(title: "Timed Trip", startDate: start, endDate: end)
        let section = TripSection(title: "Timed Section", startDate: start, endDate: end)

        XCTAssertEqual(Calendar.current.component(.minute, from: trip.startDate!), 0)
        XCTAssertEqual(Calendar.current.component(.second, from: trip.endDate!), 0)
        XCTAssertEqual(Calendar.current.component(.minute, from: section.startDate!), 0)
        XCTAssertEqual(Calendar.current.component(.second, from: section.endDate!), 0)
        XCTAssertGreaterThanOrEqual(section.endDate!, section.startDate!)
    }

    func testCodeBlockStoresSourceText() {
        let source = "func greet() {\n    print(\"Hello\")\n}"
        let block = ContentBlock(type: .code, text: source)

        XCTAssertEqual(block.type, .code)
        XCTAssertEqual(block.text, source)
    }

    func testPhotoBlockStoresNormalizedLink() {
        let block = ContentBlock(
            type: .photo,
            linkURLString: LinkAddress.normalizedURL(from: "example.com/story")!.absoluteString
        )

        XCTAssertEqual(block.linkURLString, "https://example.com/story")
    }

    @MainActor
    func testDocxExporterCreatesPackageForSelectedSections() async throws {
        let included = TripSection(title: "Included Stop", kind: .place, sortIndex: 0)
        included.blocks.append(ContentBlock(
            type: .paragraph,
            sortIndex: 0,
            title: "Arrival",
            text: "A selected-section export."
        ))
        let excluded = TripSection(title: "Excluded Stop", kind: .activity, sortIndex: 1)
        excluded.blocks.append(ContentBlock(type: .paragraph, text: "Do not export this."))

        let url = try await DocxExporter.export(
            title: "Selective Trip",
            sections: [included]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        XCTAssertNotNil(data.range(of: Data("word/document.xml".utf8)))
        XCTAssertNotNil(data.range(of: Data("Selective Trip".utf8)))
        XCTAssertNotNil(data.range(of: Data("Included Stop".utf8)))
        XCTAssertNil(data.range(of: Data("Excluded Stop".utf8)))
    }

    @MainActor
    func testHtmlExporterCreatesOfflinePackageForSelectedSections() async throws {
        let included = TripSection(title: "Kyoto & Tea", kind: .foodAndDrink, sortIndex: 0)
        included.blocks.append(ContentBlock(
            type: .paragraph,
            sortIndex: 0,
            title: "Morning",
            text: "Tea < ceremony"
        ))

        let url = try await HtmlExporter.export(
            title: "Japan Notes",
            sections: [included]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        XCTAssertNotNil(data.range(of: Data("index.html".utf8)))
        XCTAssertNotNil(data.range(of: Data("<!doctype html>".utf8)))
        XCTAssertNotNil(data.range(of: Data("Kyoto &amp; Tea".utf8)))
        XCTAssertNotNil(data.range(of: Data("Tea &lt; ceremony".utf8)))
        XCTAssertNil(data.range(of: Data("Do Not Include".utf8)))
    }

    @MainActor
    func testDeletingTripCascadesToSectionsAndBlocks() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Trip.self,
            TripSection.self,
            ContentBlock.self,
            MediaReference.self,
            configurations: configuration
        )
        let context = container.mainContext
        let trip = Trip(title: "Japan")
        let section = TripSection(title: "Shibuya")
        let block = ContentBlock(type: .paragraph, text: "Arrival")
        section.blocks.append(block)
        trip.sections.append(section)
        context.insert(trip)
        try context.save()

        context.delete(trip)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Trip>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TripSection>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ContentBlock>()), 0)
    }
}
