import MapKit
import Photos
import SwiftUI
import UIKit

enum HtmlExportError: LocalizedError {
    case noSections

    var errorDescription: String? {
        "Select at least one section to export."
    }
}

struct HtmlExporter {
    private struct BuildContext {
        var entries: [(String, Data)] = []
        var assetIndex = 0
        var galleryIndex = 0

        mutating func addAsset(data: Data, extension fileExtension: String) -> String {
            assetIndex += 1
            let filename = "asset-\(assetIndex).\(fileExtension)"
            entries.append(("assets/\(filename)", data))
            return "assets/\(filename)"
        }

        mutating func nextGalleryID() -> String {
            galleryIndex += 1
            return "gallery-\(galleryIndex)"
        }
    }

    static func export(
        title: String,
        sections: [TripSection],
        progress: ((Double, String) -> Void)? = nil
    ) async throws -> URL {
        guard !sections.isEmpty else { throw HtmlExportError.noSections }
        progress?(0.02, "Preparing HTML package…")

        var context = BuildContext()
        var sectionHTML = ""
        for (index, section) in sections.enumerated() {
            let sectionProgress = 0.08 + (Double(index) / Double(sections.count)) * 0.78
            progress?(sectionProgress, "Processing \(section.title)…")
            await Task.yield()
            sectionHTML += await render(section: section, context: &context)
            let completedProgress = 0.08 + (Double(index + 1) / Double(sections.count)) * 0.78
            progress?(completedProgress, "Processed \(section.title)")
        }

        let document = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(htmlEscape(title))</title>
          <style>
            :root { color-scheme: light dark; --paper:#fffdf8; --ink:#1d2530; --muted:#68717c; --accent:#e76542; --line:#d9d5cc; }
            * { box-sizing:border-box; }
            body { margin:0; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; background:#eef1f4; color:var(--ink); line-height:1.62; }
            main { width:min(900px,calc(100% - 28px)); margin:28px auto; background:var(--paper); padding:clamp(22px,5vw,64px); border-radius:18px; box-shadow:0 12px 40px #17202c18; }
            h1 { font-family:Georgia,serif; font-size:clamp(2rem,6vw,3.8rem); line-height:1.08; margin:0 0 2rem; }
            h2 { font-family:Georgia,serif; font-size:2rem; margin:2.6rem 0 .25rem; padding-top:1.5rem; border-top:1px solid var(--line); }
            h3 { font-size:1.25rem; margin:1.7rem 0 .45rem; }
            .meta,.caption,.coordinates { color:var(--muted); font-size:.9rem; }
            .block { margin:1.2rem 0; }
            img,video { display:block; width:100%; max-height:70vh; object-fit:contain; border-radius:12px; background:#101722; }
            .gallery-slider { position:relative; border-radius:12px; overflow:hidden; background:white; }
            .gallery-track { display:flex; overflow-x:auto; scroll-snap-type:x mandatory; scrollbar-width:none; overscroll-behavior-x:contain; }
            .gallery-track::-webkit-scrollbar { display:none; }
            .gallery-slide { flex:0 0 100%; scroll-snap-align:center; scroll-snap-stop:always; display:flex; flex-direction:column; justify-content:center; min-width:0; }
            .gallery-slide img { width:100%; height:clamp(260px,60vw,560px); object-fit:contain; border-radius:0; background:white; cursor:zoom-in; }
            .gallery-photo-caption { margin:0; padding:10px 18px 46px; color:#4f5864; font-size:.9rem; text-align:center; background:white; }
            .gallery-button { position:absolute; z-index:2; top:50%; translate:0 -50%; width:42px; height:42px; border:0; border-radius:50%; background:#17202ccc; color:white; font-size:1.5rem; cursor:pointer; }
            .gallery-button:disabled { opacity:.28; cursor:default; }
            .gallery-previous { left:12px; }
            .gallery-next { right:12px; }
            .gallery-dots { position:absolute; z-index:2; left:50%; bottom:12px; translate:-50% 0; display:flex; gap:7px; padding:7px 9px; border-radius:999px; background:#17202c99; }
            .gallery-dot { width:8px; height:8px; padding:0; border:0; border-radius:50%; background:#ffffff80; cursor:pointer; }
            .gallery-dot[aria-current="true"] { background:white; transform:scale(1.2); }
            .photo-lightbox { width:100vw; height:100vh; max-width:none; max-height:none; margin:0; padding:0; border:0; background:#05070a; overflow:hidden; }
            .photo-lightbox::backdrop { background:#05070a; }
            .photo-lightbox img { width:100%; height:100%; object-fit:contain; border-radius:0; background:#05070a; }
            .lightbox-close { position:fixed; z-index:4; top:max(16px,env(safe-area-inset-top)); right:max(16px,env(safe-area-inset-right)); width:44px; height:44px; border:0; border-radius:50%; background:#ffffffdc; color:#111820; font-size:1.6rem; line-height:1; cursor:pointer; }
            .lightbox-button { position:fixed; z-index:4; top:50%; translate:0 -50%; width:48px; height:48px; border:0; border-radius:50%; background:#ffffffc9; color:#111820; font-size:1.8rem; cursor:pointer; }
            .lightbox-button:disabled { display:none; }
            .lightbox-previous { left:max(16px,env(safe-area-inset-left)); }
            .lightbox-next { right:max(16px,env(safe-area-inset-right)); }
            .lightbox-position { position:fixed; z-index:4; left:50%; bottom:max(18px,env(safe-area-inset-bottom)); translate:-50% 0; padding:7px 12px; border-radius:999px; background:#000a; color:white; font-size:.9rem; }
            .lightbox-caption { position:fixed; z-index:4; left:50%; bottom:max(62px,calc(env(safe-area-inset-bottom) + 62px)); translate:-50% 0; width:min(680px,calc(100% - 40px)); padding:9px 13px; border-radius:10px; background:#000a; color:white; text-align:center; }
            blockquote { margin:1.2rem 0; padding:.5rem 1.2rem; border-left:4px solid var(--accent); color:#4f5864; }
            pre { overflow:auto; padding:1rem; border-radius:10px; background:#18202b; color:#f4f6f8; font:14px/1.55 ui-monospace,SFMono-Regular,Menlo,monospace; }
            hr { border:0; border-top:1px solid var(--line); margin:2rem 0; }
            a { color:#1769aa; text-decoration-thickness:.08em; }
            .linked-media { position:relative; display:block; }
            .linked-media::after { content:"↗"; position:absolute; top:10px; right:10px; width:34px; height:34px; display:grid; place-items:center; border-radius:50%; background:#1769aae8; color:white; font-weight:700; }
            @media (prefers-color-scheme:dark) { :root { --paper:#171b21; --ink:#f0f2f4; --muted:#a9b0b9; --line:#343b44; } body { background:#0d1117; } blockquote { color:#c1c7ce; } }
            @media print { body { background:white; } main { width:100%; margin:0; padding:0; box-shadow:none; } section { break-inside:avoid-page; } }
          </style>
        </head>
        <body>
          <main>
            <h1>\(htmlEscape(title))</h1>
            \(sectionHTML)
          </main>
          <dialog class="photo-lightbox" aria-label="Full-screen photo">
            <button class="lightbox-close" type="button" aria-label="Close full-screen photo">×</button>
            <button class="lightbox-button lightbox-previous" type="button" aria-label="Previous full-screen photo">‹</button>
            <img alt="">
            <button class="lightbox-button lightbox-next" type="button" aria-label="Next full-screen photo">›</button>
            <div class="lightbox-caption" aria-live="polite"></div>
            <div class="lightbox-position" aria-live="polite"></div>
          </dialog>
          <script>
            const lightbox = document.querySelector('.photo-lightbox');
            const lightboxImage = lightbox.querySelector('img');
            const lightboxPrevious = lightbox.querySelector('.lightbox-previous');
            const lightboxNext = lightbox.querySelector('.lightbox-next');
            const lightboxCaption = lightbox.querySelector('.lightbox-caption');
            const lightboxPosition = lightbox.querySelector('.lightbox-position');
            let lightboxImages = [];
            let lightboxIndex = 0;
            let lightboxTouchStart = null;
            const closeLightbox = () => lightbox.close();
            const updateLightbox = () => {
              const image = lightboxImages[lightboxIndex];
              if (!image) return;
              lightboxImage.src = image.src;
              lightboxImage.alt = image.alt;
              lightboxCaption.textContent = image.dataset.caption || '';
              lightboxCaption.hidden = !image.dataset.caption;
              lightboxPrevious.disabled = lightboxIndex === 0;
              lightboxNext.disabled = lightboxIndex === lightboxImages.length - 1;
              lightboxPosition.textContent = `${lightboxIndex + 1} of ${lightboxImages.length}`;
            };
            const showPreviousLightboxPhoto = () => {
              if (lightboxIndex > 0) {
                lightboxIndex -= 1;
                updateLightbox();
              }
            };
            const showNextLightboxPhoto = () => {
              if (lightboxIndex < lightboxImages.length - 1) {
                lightboxIndex += 1;
                updateLightbox();
              }
            };
            lightbox.querySelector('.lightbox-close').addEventListener('click', closeLightbox);
            lightboxPrevious.addEventListener('click', showPreviousLightboxPhoto);
            lightboxNext.addEventListener('click', showNextLightboxPhoto);
            lightbox.addEventListener('click', (event) => {
              if (event.target === lightbox) closeLightbox();
            });
            lightbox.addEventListener('keydown', (event) => {
              if (event.key === 'ArrowLeft') showPreviousLightboxPhoto();
              if (event.key === 'ArrowRight') showNextLightboxPhoto();
            });
            lightbox.addEventListener('touchstart', (event) => {
              lightboxTouchStart = event.changedTouches[0].clientX;
            }, { passive: true });
            lightbox.addEventListener('touchend', (event) => {
              if (lightboxTouchStart === null) return;
              const distance = event.changedTouches[0].clientX - lightboxTouchStart;
              lightboxTouchStart = null;
              if (distance > 45) showPreviousLightboxPhoto();
              if (distance < -45) showNextLightboxPhoto();
            }, { passive: true });

            document.querySelectorAll('.gallery-slider').forEach((gallery) => {
              const track = gallery.querySelector('.gallery-track');
              const slides = Array.from(track.children);
              const previous = gallery.querySelector('.gallery-previous');
              const next = gallery.querySelector('.gallery-next');
              const dots = gallery.querySelector('.gallery-dots');
              let activeIndex = 0;

              slides.forEach((_, index) => {
                const dot = document.createElement('button');
                dot.className = 'gallery-dot';
                dot.type = 'button';
                dot.setAttribute('aria-label', `Show photo ${index + 1}`);
                dot.addEventListener('click', () => {
                  track.scrollTo({ left: index * track.clientWidth, behavior: 'smooth' });
                });
                dots.appendChild(dot);
              });

              const update = () => {
                activeIndex = Math.max(0, Math.min(
                  slides.length - 1,
                  Math.round(track.scrollLeft / Math.max(track.clientWidth, 1))
                ));
                previous.disabled = activeIndex === 0;
                next.disabled = activeIndex === slides.length - 1;
                Array.from(dots.children).forEach((dot, index) => {
                  dot.setAttribute('aria-current', index === activeIndex ? 'true' : 'false');
                });
              };

              previous.addEventListener('click', () => {
                track.scrollBy({ left: -track.clientWidth, behavior: 'smooth' });
              });
              next.addEventListener('click', () => {
                track.scrollBy({ left: track.clientWidth, behavior: 'smooth' });
              });
              track.addEventListener('scroll', update, { passive: true });
              window.addEventListener('resize', update);
              const galleryImages = Array.from(gallery.querySelectorAll('.gallery-slide img'));
              galleryImages.forEach((image, index) => {
                image.addEventListener('click', () => {
                  lightboxImages = galleryImages;
                  lightboxIndex = index;
                  updateLightbox();
                  lightbox.showModal();
                });
              });
              update();
            });
          </script>
        </body>
        </html>
        """

        var entries: [(String, Data)] = [("index.html", Data(document.utf8))]
        entries.append(contentsOf: context.entries)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitizedFilename(title))-HTML-\(UUID().uuidString.prefix(8)).zip")
        progress?(0.9, "Packaging HTML and media…")
        await Task.yield()
        try ZipPackageWriter.write(entries: entries, to: outputURL)
        progress?(1, "Package ready")
        return outputURL
    }

    private static func render(section: TripSection, context: inout BuildContext) async -> String {
        var blocks = ""
        for block in section.orderedBlocks {
            blocks += await render(block: block, context: &context)
        }

        var metadata = [section.kind.label]
        if !section.placeName.isEmpty { metadata.append(section.placeName) }
        if let start = section.startDate, let end = section.endDate {
            metadata.append(DateRangeFormatting.summary(start: start, end: end))
        }

        return """
        <section>
          <h2>\(htmlEscape(section.title))</h2>
          <p class="meta">\(htmlEscape(metadata.joined(separator: " • ")))</p>
          \(blocks)
        </section>
        """
    }

    private static func render(block: ContentBlock, context: inout BuildContext) async -> String {
        switch block.type {
        case .heading:
            return "<h3>\(htmlEscape(block.text))</h3>"
        case .paragraph:
            let title = block.title.isEmpty ? "" : "<h3>\(htmlEscape(block.title))</h3>"
            return "<div class=\"block\">\(title)<p>\(richTextHTML(block))</p></div>"
        case .quote:
            let title = block.title.isEmpty ? "" : "<h3>\(htmlEscape(block.title))</h3>"
            return "<div class=\"block\">\(title)<blockquote>\(richTextHTML(block))</blockquote></div>"
        case .code:
            return "<pre><code>\(htmlEscape(block.text))</code></pre>"
        case .divider:
            return "<hr>"
        case .photo:
            guard let reference = block.orderedMediaReferences.first,
                  let image = await loadImage(reference: reference),
                  let data = image.jpegData(compressionQuality: 0.88) else {
                return "<p class=\"block meta\">Photo unavailable</p>"
            }
            let path = context.addAsset(data: data, extension: "jpg")
            let imageHTML = "<img src=\"\(path)\" alt=\"\(attributeEscape(block.caption.isEmpty ? "Travel journal photo" : block.caption))\">"
            let linkedImage: String
            if let url = LinkAddress.normalizedURL(from: block.linkURLString) {
                linkedImage = "<a class=\"linked-media\" href=\"\(attributeEscape(url.absoluteString))\">\(imageHTML)</a>"
            } else {
                linkedImage = imageHTML
            }
            return """
            <figure class="block">\(linkedImage)\(caption(block.caption))</figure>
            """
        case .gallery:
            var images = ""
            for reference in block.orderedMediaReferences {
                if let image = await loadImage(reference: reference),
                   let data = image.jpegData(compressionQuality: 0.86) {
                    let path = context.addAsset(data: data, extension: "jpg")
                    let photoCaptionText = reference.caption
                    let photoCaption = photoCaptionText.isEmpty
                        ? ""
                        : "<p class=\"gallery-photo-caption\">\(htmlEscape(photoCaptionText))</p>"
                    images += """
                    <div class="gallery-slide"><img src="\(path)" alt="\(attributeEscape(photoCaptionText.isEmpty ? "Gallery photo" : photoCaptionText))" data-caption="\(attributeEscape(photoCaptionText))">\(photoCaption)</div>
                    """
                }
            }
            guard !images.isEmpty else {
                return "<p class=\"block meta\">Gallery unavailable</p>"
            }
            let galleryID = context.nextGalleryID()
            let galleryTitle = block.title.isEmpty ? "" : "<h3>\(htmlEscape(block.title))</h3>"
            return """
            \(galleryTitle)
            <figure class="block">
              <div class="gallery-slider" id="\(galleryID)" aria-label="Photo gallery">
                <div class="gallery-track">\(images)</div>
                <button class="gallery-button gallery-previous" type="button" aria-label="Previous photo">‹</button>
                <button class="gallery-button gallery-next" type="button" aria-label="Next photo">›</button>
                <div class="gallery-dots" aria-label="Choose a photo"></div>
              </div>
            </figure>
            """
        case .video:
            guard let reference = block.orderedMediaReferences.first else {
                return "<p class=\"block meta\">Video unavailable</p>"
            }
            let posterPath: String?
            if let poster = await loadImage(reference: reference),
               let posterData = poster.jpegData(compressionQuality: 0.84) {
                posterPath = context.addAsset(data: posterData, extension: "jpg")
            } else {
                posterPath = nil
            }
            if let video = await loadVideo(reference: reference) {
                let path = context.addAsset(data: video.data, extension: video.fileExtension)
                let poster = posterPath.map { " poster=\"\($0)\"" } ?? ""
                return """
                <figure class="block"><video controls preload="metadata"\(poster)><source src="\(path)"></video>\(caption(block.caption))</figure>
                """
            }
            return posterPath.map {
                "<figure class=\"block\"><img src=\"\($0)\" alt=\"Video poster frame\">\(caption(block.caption))<p class=\"meta\">Video file unavailable</p></figure>"
            } ?? "<p class=\"block meta\">Video unavailable</p>"
        case .map:
            guard let section = block.section,
                  let latitude = section.latitude,
                  let longitude = section.longitude else {
                return "<p class=\"block meta\">Map unavailable</p>"
            }
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            var imageHTML = ""
            if let snapshot = await mapSnapshot(coordinate: coordinate, name: section.placeName),
               let data = snapshot.jpegData(compressionQuality: 0.86) {
                let path = context.addAsset(data: data, extension: "jpg")
                imageHTML = "<img src=\"\(path)\" alt=\"Map of \(attributeEscape(section.placeName))\">"
            }
            return """
            <div class="block"><h3>\(htmlEscape(section.placeName.isEmpty ? "Location" : section.placeName))</h3>\(imageHTML)<p class="coordinates">\(latitude.formatted()), \(longitude.formatted())</p><p>\(htmlEscape(block.mapDescription).replacingOccurrences(of: "\n", with: "<br>"))</p></div>
            """
        }
    }

    private static func richTextHTML(_ block: ContentBlock) -> String {
        guard let data = block.attributedTextData,
              let attributed = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSAttributedString.self,
                from: data
              ) else {
            return htmlEscape(block.text).replacingOccurrences(of: "\n", with: "<br>")
        }

        var result = ""
        attributed.enumerateAttributes(
            in: NSRange(location: 0, length: attributed.length)
        ) { attributes, range, _ in
            var value = htmlEscape(attributed.attributedSubstring(from: range).string)
                .replacingOccurrences(of: "\n", with: "<br>")
            if let font = attributes[.font] as? UIFont {
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.traitBold) { value = "<strong>\(value)</strong>" }
                if traits.contains(.traitItalic) { value = "<em>\(value)</em>" }
                value = "<span style=\"font-family:\(attributeEscape(font.familyName));font-size:\(Int(font.pointSize))px\">\(value)</span>"
            }
            if let underline = attributes[.underlineStyle] as? Int, underline != 0 {
                value = "<u>\(value)</u>"
            }
            if let url = attributes[.link] as? URL {
                value = "<a href=\"\(attributeEscape(url.absoluteString))\">\(value)</a>"
            }
            result += value
        }
        return result
    }

    private static func loadImage(reference: MediaReference) async -> UIImage? {
        guard await PhotoLibraryAccess.isAuthorized() else { return nil }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [reference.localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            var didResume = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 2200, height: 2200),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !degraded, !didResume {
                    didResume = true
                    continuation.resume(returning: image)
                }
            }
        }
    }

    private static func loadVideo(reference: MediaReference) async -> (data: Data, fileExtension: String)? {
        guard await PhotoLibraryAccess.isAuthorized() else { return nil }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [reference.localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: {
            $0.type == .video || $0.type == .fullSizeVideo
        }) else { return nil }

        let rawExtension = URL(fileURLWithPath: resource.originalFilename).pathExtension.lowercased()
        let safeExtension = !rawExtension.isEmpty
            && rawExtension.count <= 5
            && rawExtension.allSatisfy { $0.isLetter || $0.isNumber }
            ? rawExtension
            : "mov"
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("video-\(UUID().uuidString).\(safeExtension)")
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        let succeeded: Bool = await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: temporaryURL,
                options: options
            ) { error in
                continuation.resume(returning: error == nil)
            }
        }
        guard succeeded, let data = try? Data(contentsOf: temporaryURL) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            return nil
        }
        try? FileManager.default.removeItem(at: temporaryURL)
        return (data, safeExtension)
    }

    private static func mapSnapshot(
        coordinate: CLLocationCoordinate2D,
        name: String
    ) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
        )
        options.size = CGSize(width: 1200, height: 700)
        options.scale = 1
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let renderer = UIGraphicsImageRenderer(size: options.size)
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)
            let point = snapshot.point(for: coordinate)
            let marker = UIImage(systemName: "mappin.circle.fill")?
                .withTintColor(.systemRed, renderingMode: .alwaysOriginal)
            marker?.draw(in: CGRect(x: point.x - 18, y: point.y - 36, width: 36, height: 36))
            if !name.isEmpty {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 22),
                    .foregroundColor: UIColor.label,
                    .backgroundColor: UIColor.systemBackground.withAlphaComponent(0.85),
                ]
                NSString(string: name).draw(at: CGPoint(x: 18, y: 18), withAttributes: attributes)
            }
        }
    }

    private static func caption(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        return "<figcaption class=\"caption\">\(htmlEscape(text).replacingOccurrences(of: "\n", with: "<br>"))</figcaption>"
    }

    private static func htmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func attributeEscape(_ text: String) -> String {
        htmlEscape(text).replacingOccurrences(of: "\n", with: " ")
    }

    private static func sanitizedFilename(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let scalars = title.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let value = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "RoamStory" : value
    }
}

struct HtmlExportView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let sections: [TripSection]
    let allowsSelection: Bool

    @State private var selectedSectionIDs: Set<UUID>
    @State private var exportedURL: URL?
    @State private var isGenerating = false
    @State private var exportProgress = 0.0
    @State private var progressLabel = ""
    @State private var errorMessage: String?

    init(title: String, sections: [TripSection], allowsSelection: Bool) {
        self.title = title
        self.sections = sections
        self.allowsSelection = allowsSelection
        _selectedSectionIDs = State(initialValue: Set(sections.map(\.id)))
    }

    private var selectedSections: [TripSection] {
        sections.filter { selectedSectionIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if allowsSelection {
                    Section("Sections to Export") {
                        ForEach(sections) { section in
                            Toggle(isOn: selectionBinding(for: section.id)) {
                                Label(section.title, systemImage: section.kind.systemImage)
                            }
                        }
                        HStack {
                            Button("Select All") {
                                selectedSectionIDs = Set(sections.map(\.id))
                                exportedURL = nil
                            }
                            Spacer()
                            Button("Clear") {
                                selectedSectionIDs.removeAll()
                                exportedURL = nil
                            }
                        }
                        .font(.caption)
                    }
                } else if let section = sections.first {
                    Section("Section") {
                        Label(section.title, systemImage: section.kind.systemImage)
                    }
                }

                Section {
                    if isGenerating {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(progressLabel)
                                    .lineLimit(1)
                                Spacer()
                                Text(exportProgress, format: .percent.precision(.fractionLength(0)))
                                    .monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            ProgressView(value: exportProgress, total: 1)
                                .progressViewStyle(.linear)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    if let exportedURL {
                        ShareLink(item: exportedURL) {
                            Label("Share HTML ZIP", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            generate()
                        } label: {
                            if isGenerating {
                                Text("Generating HTML ZIP…")
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("Generate HTML ZIP", systemImage: "archivebox")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isGenerating || selectedSections.isEmpty)
                    }
                } footer: {
                    Text("Extract the ZIP on a computer and open index.html. Photos, videos, map snapshots, and styling are stored inside the package. Archives containing videos may be large.")
                }
            }
            .navigationTitle("Export HTML Package")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert(
                "Export Failed",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "The HTML package could not be generated.")
            }
        }
    }

    private func selectionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedSectionIDs.contains(id) },
            set: { selected in
                if selected {
                    selectedSectionIDs.insert(id)
                } else {
                    selectedSectionIDs.remove(id)
                }
                exportedURL = nil
            }
        )
    }

    private func generate() {
        isGenerating = true
        exportProgress = 0
        progressLabel = "Preparing HTML package…"
        errorMessage = nil
        Task {
            do {
                exportedURL = try await HtmlExporter.export(
                    title: title,
                    sections: selectedSections
                ) { progress, label in
                    exportProgress = progress
                    progressLabel = label
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }
}
