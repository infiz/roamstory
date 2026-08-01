import CryptoKit
import Foundation
import Photos
import SwiftUI
import UniformTypeIdentifiers
import WebKit

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

struct DraftSitePreview {
    let html: String
    let baseURL: URL
    let pages: [String: String]
}

struct DraftSitePreviewResponse: Decodable {
    let html: String
    let pages: [String: String]
}

struct PublishedSitePreview: Identifiable {
    let html: String
    let baseURL: URL
    let media: [UUID: LocalPublishMedia]
    let pages: [String: String]
    let id = UUID()

    func replacingMediaURLs(in source: String) -> String {
        media.keys.reduce(source) { result, mediaUuid in
            result.replacingOccurrences(
                of: "/media/\(mediaUuid.uuidString.lowercased())",
                with: "\(PreviewMediaSchemeHandler.scheme)://media/\(mediaUuid.uuidString.lowercased())"
            )
        }
    }
}

struct PublishedSitePreviewView: UIViewRepresentable {
    let preview: PublishedSitePreview

    func makeCoordinator() -> Coordinator {
        Coordinator(
            pages: preview.pages.mapValues { preview.replacingMediaURLs(in: $0) }
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.setURLSchemeHandler(
            PreviewMediaSchemeHandler(media: preview.media),
            forURLScheme: PreviewMediaSchemeHandler.scheme
        )
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        let html = preview.replacingMediaURLs(in: preview.html)
        view.loadHTMLString(html, baseURL: preview.baseURL)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let pages: [String: String]

        init(pages: [String: String]) {
            self.pages = pages
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url,
                  let page = pages[url.path] else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            let encodedPage = Self.javascriptString(page)
            let encodedPath = Self.javascriptString(url.path)
            webView.evaluateJavaScript(
                """
                (() => {
                  const content = document.querySelector('#published-content');
                  const navigation = document.querySelector('.section-navigation');
                  if (!content || !navigation) return;
                  content.innerHTML = \(encodedPage);
                  navigation.querySelectorAll('a').forEach(link => {
                    if (new URL(link.href).pathname === \(encodedPath)) {
                      link.setAttribute('aria-current', 'page');
                    } else {
                      link.removeAttribute('aria-current');
                    }
                  });
                  window.roamstoryInitializePublishedContent?.(content);
                  window.scrollTo({ top: 0, behavior: 'smooth' });
                })();
                """
            )
        }

        private static func javascriptString(_ value: String) -> String {
            guard let data = try? JSONEncoder().encode(value),
                  let string = String(data: data, encoding: .utf8) else {
                return "\"\""
            }
            return string
                .replacingOccurrences(of: "<", with: "\\u003c")
                .replacingOccurrences(of: " ", with: "\\u2028")
                .replacingOccurrences(of: " ", with: "\\u2029")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            webView.evaluateJavaScript("window.roamstoryPreviewReady === true") {
                result,
                _ in
                guard result as? Bool != true else { return }
                webView.evaluateJavaScript(
                    """
                    document.querySelectorAll('script:not([src])').forEach(original => {
                      const replacement = document.createElement('script');
                      replacement.textContent = original.textContent;
                      document.body.appendChild(replacement);
                      replacement.remove();
                    });
                    """
                )
            }
        }
    }
}

private final class PreviewMediaSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "roamstory-preview-media"
    private let media: [UUID: LocalPublishMedia]

    init(media: [UUID: LocalPublishMedia]) {
        self.media = media
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let uuid = UUID(uuidString: url.lastPathComponent),
              let item = media[uuid] else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = URLResponse(
            url: url,
            mimeType: item.contentType,
            expectedContentLength: item.data.count,
            textEncodingName: nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(item.data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
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
