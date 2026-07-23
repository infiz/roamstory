import Foundation
import Photos
import SwiftData

enum TripSortField: String, CaseIterable, Identifiable {
    case title
    case created
    case modified

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: "Title"
        case .created: "Created"
        case .modified: "Modified"
        }
    }
}

enum SortDirection: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum SectionKind: String, CaseIterable, Identifiable, Codable {
    case place
    case activity
    case foodAndDrink
    case accommodation
    case transit
    case event
    case natureAndWildlife
    case reflection
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .place: "Place"
        case .activity: "Activity"
        case .foodAndDrink: "Food & Drink"
        case .accommodation: "Accommodation"
        case .transit: "Transit"
        case .event: "Event"
        case .natureAndWildlife: "Nature & Wildlife"
        case .reflection: "Reflection"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .place: "mappin.and.ellipse"
        case .activity: "figure.walk"
        case .foodAndDrink: "fork.knife"
        case .accommodation: "bed.double"
        case .transit: "car"
        case .event: "ticket"
        case .natureAndWildlife: "pawprint"
        case .reflection: "text.book.closed"
        case .other: "square.grid.2x2"
        }
    }

    static func storedValue(_ rawValue: String) -> SectionKind {
        if let current = SectionKind(rawValue: rawValue) {
            return current
        }

        // Preserve sections created by the original development schema.
        switch rawValue {
        case "location", "view": return .place
        case "meal": return .foodAndDrink
        case "animal": return .natureAndWildlife
        case "experience": return .activity
        default: return .other
        }
    }
}

enum BlockType: String, CaseIterable, Codable {
    case paragraph
    case heading
    case quote
    case code
    case divider
    case photo
    case gallery
    case video
    case map

    var label: String {
        switch self {
        case .paragraph: "Paragraph"
        case .heading: "Heading"
        case .quote: "Quote"
        case .code: "Code"
        case .divider: "Divider"
        case .photo: "Photo"
        case .gallery: "Gallery"
        case .video: "Video"
        case .map: "Map"
        }
    }

    var systemImage: String {
        switch self {
        case .paragraph: "text.alignleft"
        case .heading: "textformat.size.larger"
        case .quote: "quote.opening"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .divider: "minus"
        case .photo: "photo"
        case .gallery: "rectangle.stack"
        case .video: "video"
        case .map: "map"
        }
    }
}

enum MediaKind: String, Codable {
    case image
    case video
}

@Model
final class Trip {
    @Attribute(.unique) var id: UUID
    var title: String
    var subtitle: String
    var createdAt: Date
    var modifiedAt: Date
    var startDate: Date?
    var endDate: Date?

    @Relationship(deleteRule: .cascade, inverse: \TripSection.trip)
    var sections: [TripSection]

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String = "",
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        startDate: Date? = nil,
        endDate: Date? = nil,
        sections: [TripSection] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.startDate = startDate?.alignedToHour
        self.endDate = endDate?.alignedToHour
        self.sections = sections
    }

    var orderedSections: [TripSection] {
        sections.sorted {
            if $0.sortIndex == $1.sortIndex { return $0.createdAt < $1.createdAt }
            return $0.sortIndex < $1.sortIndex
        }
    }

    func touch(at date: Date = .now) {
        modifiedAt = date
    }
}

@Model
final class TripSection {
    @Attribute(.unique) var id: UUID
    var title: String
    var kindRawValue: String
    var createdAt: Date
    var modifiedAt: Date
    var sortIndex: Int
    var occurredAt: Date?
    var startDate: Date?
    var endDate: Date?
    var placeName: String
    var latitude: Double?
    var longitude: Double?
    var trip: Trip?

    @Relationship(deleteRule: .cascade, inverse: \ContentBlock.section)
    var blocks: [ContentBlock]

    init(
        id: UUID = UUID(),
        title: String,
        kind: SectionKind = .activity,
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        sortIndex: Int = 0,
        occurredAt: Date? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        placeName: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        blocks: [ContentBlock] = []
    ) {
        self.id = id
        self.title = title
        kindRawValue = kind.rawValue
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.sortIndex = sortIndex
        self.occurredAt = occurredAt
        self.startDate = (startDate ?? occurredAt)?.alignedToHour
        self.endDate = endDate?.alignedToHour
        self.placeName = placeName
        self.latitude = latitude
        self.longitude = longitude
        self.blocks = blocks
    }

    var kind: SectionKind {
        get { SectionKind.storedValue(kindRawValue) }
        set { kindRawValue = newValue.rawValue }
    }

    var orderedBlocks: [ContentBlock] {
        blocks.sorted {
            if $0.sortIndex == $1.sortIndex { return $0.createdAt < $1.createdAt }
            return $0.sortIndex < $1.sortIndex
        }
    }

    func touch(at date: Date = .now) {
        // Modification timestamps are bookkeeping rather than editable content.
        // Mutating this child while a SwiftData undo scope is active can capture
        // its inverse relationship and detach it from the trip. The editor calls
        // touch again after detaching its scoped manager, before returning to the
        // section list.
        guard modelContext?.undoManager == nil else { return }
        modifiedAt = date
        trip?.touch(at: date)
    }
}

@Model
final class ContentBlock {
    @Attribute(.unique) var id: UUID
    var typeRawValue: String
    var sortIndex: Int
    var createdAt: Date
    var title: String = ""
    var text: String
    var attributedTextData: Data?
    var descriptionText: String
    var linkURLString: String = ""
    var fontFamily: String
    var fontSize: Double
    var isBold: Bool
    var isItalic: Bool
    var isUnderlined: Bool
    var section: TripSection?

    @Relationship(deleteRule: .cascade, inverse: \MediaReference.block)
    var mediaReferences: [MediaReference]

    init(
        id: UUID = UUID(),
        type: BlockType,
        sortIndex: Int = 0,
        createdAt: Date = .now,
        title: String = "",
        text: String = "",
        attributedTextData: Data? = nil,
        descriptionText: String = "",
        linkURLString: String = "",
        fontFamily: String = "New York",
        fontSize: Double = 17,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderlined: Bool = false,
        mediaReferences: [MediaReference] = []
    ) {
        self.id = id
        typeRawValue = type.rawValue
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.title = title
        self.text = text
        self.attributedTextData = attributedTextData
        self.descriptionText = descriptionText
        self.linkURLString = linkURLString
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.mediaReferences = mediaReferences
    }

    var type: BlockType {
        get { BlockType(rawValue: typeRawValue) ?? .paragraph }
        set { typeRawValue = newValue.rawValue }
    }
}

@Model
final class MediaReference {
    @Attribute(.unique) var id: UUID
    var provider: String
    var localIdentifier: String
    var kindRawValue: String
    var originalFilename: String
    var createdAt: Date
    var sortIndex: Int = 0
    var block: ContentBlock?

    init(
        id: UUID = UUID(),
        provider: String = "applePhotos",
        localIdentifier: String,
        kind: MediaKind,
        originalFilename: String = "",
        sortIndex: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.provider = provider
        self.localIdentifier = localIdentifier
        kindRawValue = kind.rawValue
        self.originalFilename = originalFilename
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }

    var kind: MediaKind {
        get { MediaKind(rawValue: kindRawValue) ?? .image }
        set { kindRawValue = newValue.rawValue }
    }
}

extension ContentBlock {
    var orderedMediaReferences: [MediaReference] {
        mediaReferences.sorted {
            if $0.sortIndex == $1.sortIndex { return $0.createdAt < $1.createdAt }
            return $0.sortIndex < $1.sortIndex
        }
    }
}

enum BlockOrdering {
    static func moving(
        _ blocks: [ContentBlock],
        sourceID: UUID,
        toInsertionIndex insertionIndex: Int
    ) -> [ContentBlock]? {
        guard let sourceIndex = blocks.firstIndex(where: { $0.id == sourceID }) else { return nil }
        var reordered = blocks
        let movingBlock = reordered.remove(at: sourceIndex)
        var destination = min(max(insertionIndex, 0), reordered.count + 1)
        if sourceIndex < destination { destination -= 1 }
        destination = min(max(destination, 0), reordered.count)
        guard destination != sourceIndex else { return nil }
        reordered.insert(movingBlock, at: destination)
        return reordered
    }
}

extension Date {
    /// `Date` is persisted as an absolute instant. The device calendar is used
    /// only to interpret the user's local hour before SwiftData stores that instant.
    var alignedToHour: Date {
        Calendar.autoupdatingCurrent.dateInterval(of: .hour, for: self)?.start ?? self
    }
}

enum TripSorter {
    static func sort(
        _ trips: [Trip],
        by field: TripSortField,
        direction: SortDirection,
        locale: Locale = .current
    ) -> [Trip] {
        let ascending = direction == .ascending

        return trips.sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch field {
            case .title:
                comparison = lhs.title.compare(
                    rhs.title,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: nil,
                    locale: locale
                )
            case .created:
                comparison = lhs.createdAt.compare(rhs.createdAt)
            case .modified:
                comparison = lhs.modifiedAt.compare(rhs.modifiedAt)
            }

            if comparison == .orderedSame {
                let titleComparison = lhs.title.compare(
                    rhs.title,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: nil,
                    locale: locale
                )
                if titleComparison == .orderedSame {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return titleComparison == .orderedAscending
            }

            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }
}
