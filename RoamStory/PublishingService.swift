import CryptoKit
import Foundation
import Photos
import UniformTypeIdentifiers

struct PublishTripRequest: Encodable {
    let tripUuid: UUID
    let expectedVersion: Int64?
    let title: String
    let subtitle: String
    let startAt: Date?
    let endAt: Date?
    let sections: [PublishSectionSnapshot]

    enum CodingKeys: String, CodingKey {
        case tripUuid = "tripUuid"
        case expectedVersion = "expectedVersion"
        case title = "title"
        case subtitle = "subtitle"
        case startAt = "startAt"
        case endAt = "endAt"
        case sections = "sections"
    }
}

struct PublishSectionSnapshot: Encodable {
    let uuid: UUID
    let position: Int
    let title: String
    let kind: String
    let occurredAt: Date?
    let startAt: Date?
    let endAt: Date?
    let placeName: String
    let latitude: Double?
    let longitude: Double?
    let blocks: [PublishBlockSnapshot]

    enum CodingKeys: String, CodingKey {
        case uuid = "uuid"
        case position = "position"
        case title = "title"
        case kind = "kind"
        case occurredAt = "occurredAt"
        case startAt = "startAt"
        case endAt = "endAt"
        case placeName = "placeName"
        case latitude = "latitude"
        case longitude = "longitude"
        case blocks = "blocks"
    }
}

struct PublishBlockSnapshot: Encodable {
    let uuid: UUID
    let position: Int
    let blockType: String
    let title: String
    let plainText: String
    let content: [String: String]
    let media: [PublishMediaSnapshot]

    enum CodingKeys: String, CodingKey {
        case uuid = "uuid"
        case position = "position"
        case blockType = "blockType"
        case title = "title"
        case plainText = "plainText"
        case content = "content"
        case media = "media"
    }
}

struct PublishMediaSnapshot: Encodable {
    let uuid: UUID
    let mediaUuid: UUID
    let position: Int
    let kind: String
    let provider: String
    let originalFilename: String
    let caption: String
    let takenAt: Date?
    let timeZoneIdentifier: String?
    let byteSize: Int64?
    let pixelWidth: Int?
    let pixelHeight: Int?

    enum CodingKeys: String, CodingKey {
        case uuid = "uuid"
        case mediaUuid = "mediaUuid"
        case position = "position"
        case kind = "kind"
        case provider = "provider"
        case originalFilename = "originalFilename"
        case caption = "caption"
        case takenAt = "takenAt"
        case timeZoneIdentifier = "timeZoneIdentifier"
        case byteSize = "byteSize"
        case pixelWidth = "pixelWidth"
        case pixelHeight = "pixelHeight"
    }
}

struct PrepareMediaUploadRequest: Encodable {
    let sha256: String
    let byteSize: Int64
    let contentType: String

    enum CodingKeys: String, CodingKey {
        case sha256 = "sha256"
        case byteSize = "byteSize"
        case contentType = "contentType"
    }
}

struct PreparedMediaUpload: Decodable {
    let mediaUuid: UUID
    let uploadRequired: Bool

    private enum CodingKeys: String, CodingKey {
        case mediaUuid = "mediaUuid"
        case uploadRequired = "uploadRequired"
    }
}

struct LocalPublishMedia {
    let referenceID: UUID
    let data: Data
    let sha256: String
    let contentType: String
    let metadata: PhotoAssetMetadata?

    static func load(_ references: [MediaReference]) async throws -> [LocalPublishMedia] {
        var result: [LocalPublishMedia] = []
        for reference in references {
            let assets = PHAsset.fetchAssets(
                withLocalIdentifiers: [reference.localIdentifier],
                options: nil
            )
            guard let asset = assets.firstObject,
                  let resource = PHAssetResource.assetResources(for: asset).first else {
                throw AuthenticationError.server(
                    "Media “\(reference.originalFilename)” is no longer available."
                )
            }
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                var collected = Data()
                PHAssetResourceManager.default().requestData(
                    for: resource,
                    options: options
                ) { chunk in
                    collected.append(chunk)
                } completionHandler: { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: collected)
                    }
                }
            }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let fileExtension = URL(fileURLWithPath: resource.originalFilename).pathExtension
            let contentType = UTType(filenameExtension: fileExtension)?.preferredMIMEType
                ?? (reference.kind == .video ? "video/quicktime" : "image/jpeg")
            let metadata = reference.kind == .image
                ? await PhotoAssetMetadataLoader.load(reference: reference)
                : nil
            result.append(
                LocalPublishMedia(
                    referenceID: reference.id,
                    data: data,
                    sha256: digest,
                    contentType: contentType,
                    metadata: metadata
                )
            )
        }
        return result
    }
}

struct PublishedTrip: Decodable {
    let ownerAccountUuid: UUID
    let tripUuid: UUID
    let publicationUuid: UUID
    let revisionUuid: UUID
    let version: Int64
    let publicURL: URL
    let publishedAt: Date

    enum CodingKeys: String, CodingKey {
        case ownerAccountUuid = "ownerAccountUuid"
        case tripUuid = "tripUuid"
        case publicationUuid = "publicationUuid"
        case revisionUuid = "revisionUuid"
        case version = "version"
        case publicURL = "publicURL"
        case publishedAt = "publishedAt"
    }
}

struct PublishedTripLikeSummary: Equatable {
    let count: Int
    let recentLikers: [PublishedLiker]
}

struct PublishedLiker: Decodable, Equatable {
    let displayName: String?
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case displayName = "displayName"
        case avatarURL = "avatarURL"
    }
}

struct PublishedLikesResponse: Decodable {
    let likes: [PublishedLike]
}

struct PublishedLike: Decodable {
    let targetType: String
    let targetUuid: UUID
    let count: Int
    let recentLikers: [PublishedLiker]

    enum CodingKeys: String, CodingKey {
        case targetType = "targetType"
        case targetUuid = "targetUuid"
        case count = "count"
        case recentLikers = "recentLikers"
    }
}

extension PublishTripRequest {
    func encodedByteCount() throws -> Int64 {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return Int64(try encoder.encode(self).count)
    }

    func contentFingerprint() throws -> String {
        let content = PublishTripRequest(
            tripUuid: tripUuid,
            expectedVersion: nil,
            title: title,
            subtitle: subtitle,
            startAt: startAt,
            endAt: endAt,
            sections: sections
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(content))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    init(
        trip: Trip,
        selectedSections: [TripSection]? = nil,
        mediaUuids: [UUID: UUID],
        mediaMetadata: [UUID: PhotoAssetMetadata] = [:]
    ) {
        let sectionsToPublish = selectedSections ?? trip.orderedSections
        self.init(
            tripUuid: trip.publishedTripID ?? trip.id,
            expectedVersion: trip.publishedVersion,
            title: trip.title,
            subtitle: trip.subtitle,
            startAt: trip.startDate,
            endAt: trip.endDate,
            sections: sectionsToPublish.enumerated().map { sectionIndex, section in
                PublishSectionSnapshot(
                    uuid: section.id,
                    position: sectionIndex,
                    title: section.title,
                    kind: section.kind.rawValue,
                    occurredAt: section.occurredAt,
                    startAt: section.startDate,
                    endAt: section.endDate,
                    placeName: section.placeName,
                    latitude: section.latitude,
                    longitude: section.longitude,
                    blocks: section.orderedBlocks.enumerated().map { blockIndex, block in
                        PublishBlockSnapshot(
                            uuid: block.id,
                            position: blockIndex,
                            blockType: block.type.rawValue,
                            title: block.title,
                            plainText: block.text,
                            content: [
                                "caption": block.caption,
                                "mapDescription": block.mapDescription,
                                "linkURL": block.linkURLString,
                                "fontFamily": block.fontFamily,
                                "fontSize": String(block.fontSize),
                                "isBold": String(block.isBold),
                                "isItalic": String(block.isItalic),
                                "isUnderlined": String(block.isUnderlined),
                            ],
                            media: block.orderedMediaReferences.enumerated().compactMap {
                                mediaIndex, reference in
                                guard let mediaUuid = mediaUuids[reference.id] else { return nil }
                                let metadata = mediaMetadata[reference.id]
                                return PublishMediaSnapshot(
                                    uuid: reference.id,
                                    mediaUuid: mediaUuid,
                                    position: mediaIndex,
                                    kind: reference.kind.rawValue,
                                    provider: reference.provider,
                                    originalFilename: reference.originalFilename,
                                    caption: reference.caption,
                                    takenAt: metadata?.takenAt,
                                    timeZoneIdentifier: metadata?.timeZone.identifier,
                                    byteSize: metadata?.byteCount,
                                    pixelWidth: metadata?.pixelWidth,
                                    pixelHeight: metadata?.pixelHeight
                                )
                            }
                        )
                    }
                )
            }
        )
    }
}
