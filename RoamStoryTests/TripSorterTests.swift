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

    func testParagraphUnderlineStyleDefaultsOff() {
        let paragraph = ContentBlock(type: .paragraph)

        XCTAssertFalse(paragraph.isUnderlined)
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

    func testGalleryStoresTitleAndCaptionsForIndividualPhotos() {
        let photo = MediaReference(
            localIdentifier: "temple",
            kind: .image,
            caption: "Lanterns beside the temple gate"
        )
        let gallery = ContentBlock(
            type: .gallery,
            title: "Evening in Kyoto",
            mediaReferences: [photo]
        )

        XCTAssertEqual(gallery.title, "Evening in Kyoto")
        XCTAssertEqual(
            gallery.orderedMediaReferences.first?.caption,
            "Lanterns beside the temple gate"
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

    func testDateRangeSummaryUsesCompactNumericFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 22,
            hour: 9,
            minute: 0
        ))!
        let end = calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 24,
            hour: 18,
            minute: 0
        ))!

        XCTAssertEqual(
            DateRangeFormatting.summary(start: start, end: end),
            "2026/07/22 09:00 - 2026/07/24 18:00"
        )
    }

    func testDatesRemainAbsoluteAndDisplayInRequestedDeviceTimeZone() {
        let start = ISO8601DateFormatter().date(from: "2026-07-22T16:00:00Z")!
        let end = ISO8601DateFormatter().date(from: "2026-07-22T18:00:00Z")!
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!

        XCTAssertEqual(
            DateRangeFormatting.summary(
                start: start,
                end: end,
                timeZone: losAngeles
            ),
            "2026/07/22 09:00 - 2026/07/22 11:00"
        )
        XCTAssertEqual(
            DateRangeFormatting.summary(
                start: start,
                end: end,
                timeZone: tokyo
            ),
            "2026/07/23 01:00 - 2026/07/23 03:00"
        )
        XCTAssertEqual(
            DateRangeFormatting.timestamp(start, timeZone: losAngeles),
            "2026/07/22 09:00"
        )
        XCTAssertEqual(start.timeIntervalSince1970, 1_784_736_000)
    }

    func testTouchingSectionStoresLastEditedTimeAndUpdatesTrip() {
        let originalDate = Date(timeIntervalSince1970: 100)
        let editedDate = Date(timeIntervalSince1970: 500)
        let trip = Trip(title: "Japan", modifiedAt: originalDate)
        let section = TripSection(
            title: "Kyoto",
            modifiedAt: originalDate
        )
        trip.sections.append(section)

        section.touch(at: editedDate)

        XCTAssertEqual(section.modifiedAt, editedDate)
        XCTAssertEqual(trip.modifiedAt, editedDate)
    }

    @MainActor
    func testSectionChangesParticipateInModelContextUndoAndRedo() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Trip.self,
            TripSection.self,
            ContentBlock.self,
            MediaReference.self,
            configurations: configuration
        )
        let context = container.mainContext
        let undoManager = UndoManager()
        undoManager.groupsByEvent = true
        context.undoManager = undoManager

        let trip = Trip(title: "Japan")
        let section = TripSection(title: "Original")
        trip.sections.append(section)
        context.insert(trip)
        try context.save()
        context.processPendingChanges()
        context.undoManager = undoManager
        undoManager.removeAllActions()

        undoManager.beginUndoGrouping()
        section.title = "Edited"
        section.touch(at: Date(timeIntervalSince1970: 500))
        undoManager.endUndoGrouping()

        XCTAssertTrue(undoManager.canUndo)
        undoManager.undo()
        XCTAssertEqual(section.title, "Original")
        XCTAssertTrue(undoManager.canRedo)

        undoManager.redo()
        XCTAssertEqual(section.title, "Edited")
    }

    @MainActor
    func testBlockAddDeleteAndCaptionChangesSupportUndoAndRedo() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Trip.self,
            TripSection.self,
            ContentBlock.self,
            MediaReference.self,
            configurations: configuration
        )
        let context = container.mainContext
        let undoManager = UndoManager()
        undoManager.groupsByEvent = true

        let trip = Trip(title: "Japan")
        let section = TripSection(title: "Kyoto")
        trip.sections.append(section)
        context.insert(trip)
        try context.save()
        context.processPendingChanges()
        context.undoManager = undoManager
        context.processPendingChanges()
        undoManager.removeAllActions()

        let block = ContentBlock(type: .photo)
        undoManager.beginUndoGrouping()
        context.insert(block)
        section.blocks.append(block)
        section.touch()
        undoManager.endUndoGrouping()

        XCTAssertEqual(section.blocks.count, 1)
        undoManager.undo()
        XCTAssertTrue(section.blocks.isEmpty)
        undoManager.redo()
        XCTAssertEqual(section.blocks.count, 1)

        undoManager.beginUndoGrouping()
        block.caption = "Temple at sunset"
        section.touch()
        undoManager.endUndoGrouping()

        undoManager.undo()
        XCTAssertEqual(block.caption, "")
        undoManager.redo()
        XCTAssertEqual(block.caption, "Temple at sunset")

        undoManager.beginUndoGrouping()
        context.delete(block)
        section.touch()
        undoManager.endUndoGrouping()

        XCTAssertTrue(section.blocks.isEmpty)
        undoManager.undo()
        XCTAssertEqual(section.blocks.count, 1)
        undoManager.redo()
        XCTAssertTrue(section.blocks.isEmpty)
    }

    @MainActor
    func testRepeatedBlockUndoRedoKeepsSectionAttachedToTrip() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Trip.self,
            TripSection.self,
            ContentBlock.self,
            MediaReference.self,
            configurations: configuration
        )
        let context = container.mainContext
        let undoManager = UndoManager()
        undoManager.groupsByEvent = true

        let trip = Trip(title: "Japan")
        let section = TripSection(title: "Kyoto")
        let block = ContentBlock(type: .photo)
        section.blocks.append(block)
        trip.sections.append(section)
        context.insert(trip)
        try context.save()
        context.processPendingChanges()
        // Match the app: section history is attached only after the section
        // already exists, so its creation/relationship cannot enter this scope.
        context.undoManager = undoManager
        context.processPendingChanges()
        undoManager.removeAllActions()

        undoManager.beginUndoGrouping()
        block.caption = "Temple after rain"
        section.touch()
        undoManager.endUndoGrouping()

        for _ in 0..<3 {
            XCTAssertTrue(undoManager.canUndo)
            undoManager.undo()
            XCTAssertEqual(trip.sections.map(\.id), [section.id])
            XCTAssertEqual(section.trip?.id, trip.id)
            XCTAssertTrue(undoManager.canRedo)
            undoManager.redo()
            XCTAssertEqual(trip.sections.map(\.id), [section.id])
            XCTAssertEqual(section.trip?.id, trip.id)
        }

        let sectionCount = try context.fetchCount(FetchDescriptor<TripSection>())
        XCTAssertEqual(sectionCount, 1)
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
        XCTAssertNotNil(data.range(of: Data(".gallery-slider".utf8)))
        XCTAssertNotNil(data.range(of: Data(".block { display:block; width:100%".utf8)))
        XCTAssertNotNil(data.range(of: Data("object-fit:contain".utf8)))
        XCTAssertNotNil(data.range(of: Data("scroll-snap-type:x mandatory".utf8)))
        XCTAssertNotNil(data.range(of: Data("photo-lightbox".utf8)))
        XCTAssertNotNil(data.range(of: Data("photo-viewer-image".utf8)))
        XCTAssertNotNil(data.range(of: Data("lightboxImages = [image]".utf8)))
        XCTAssertNotNil(data.range(of: Data("lightbox.showModal()".utf8)))
        XCTAssertNotNil(data.range(of: Data("showNextLightboxPhoto".utf8)))
        XCTAssertNotNil(data.range(of: Data("touchend".utf8)))
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
