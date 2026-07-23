import Photos
import SwiftUI
import UIKit

enum DocxExportError: LocalizedError {
    case noSections
    case packageTooLarge

    var errorDescription: String? {
        switch self {
        case .noSections:
            "Select at least one section to export."
        case .packageTooLarge:
            "The document is too large to package."
        }
    }
}

struct DocxExporter {
    private struct Relationship {
        let id: String
        let type: String
        let target: String
    }

    private struct EmbeddedImage {
        let filename: String
        let data: Data
        let width: CGFloat
        let height: CGFloat
    }

    private struct BuildContext {
        var relationships: [Relationship] = []
        var images: [EmbeddedImage] = []

        mutating func addImage(_ image: UIImage) -> (relationshipID: String, imageIndex: Int)? {
            guard let data = image.jpegData(compressionQuality: 0.86) else { return nil }
            let imageIndex = images.count + 1
            let filename = "image\(imageIndex).jpg"
            images.append(EmbeddedImage(
                filename: filename,
                data: data,
                width: image.size.width,
                height: image.size.height
            ))
            let relationshipID = "rId\(relationships.count + 1)"
            relationships.append(Relationship(
                id: relationshipID,
                type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image",
                target: "media/\(filename)"
            ))
            return (relationshipID, imageIndex)
        }
    }

    static func export(
        title: String,
        sections: [TripSection],
        progress: ((Double, String) -> Void)? = nil
    ) async throws -> URL {
        guard !sections.isEmpty else { throw DocxExportError.noSections }
        progress?(0.02, "Preparing document…")

        var context = BuildContext()
        var body = heading(title, level: 1)

        for (index, section) in sections.enumerated() {
            let sectionProgress = 0.08 + (Double(index) / Double(sections.count)) * 0.78
            progress?(sectionProgress, "Processing \(section.title)…")
            await Task.yield()
            body += heading(section.title, level: 2)
            body += sectionMetadata(section)

            for block in section.orderedBlocks {
                body += await render(block: block, context: &context)
            }
            let completedProgress = 0.08 + (Double(index + 1) / Double(sections.count)) * 0.78
            progress?(completedProgress, "Processed \(section.title)")
        }

        body += """
        <w:sectPr>
          <w:pgSz w:w="12240" w:h="15840"/>
          <w:pgMar w:top="1080" w:right="1080" w:bottom="1080" w:left="1080" w:header="720" w:footer="720" w:gutter="0"/>
        </w:sectPr>
        """

        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
          xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
          xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
          xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
          <w:body>\(body)</w:body>
        </w:document>
        """

        let relationshipXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        \(context.relationships.map {
            "<Relationship Id=\"\($0.id)\" Type=\"\($0.type)\" Target=\"\($0.target)\"/>"
        }.joined())
        </Relationships>
        """

        var entries: [(String, Data)] = [
            ("[Content_Types].xml", Data(contentTypesXML.utf8)),
            ("_rels/.rels", Data(rootRelationshipsXML.utf8)),
            ("docProps/app.xml", Data(appPropertiesXML.utf8)),
            ("docProps/core.xml", Data(corePropertiesXML(title: title).utf8)),
            ("word/document.xml", Data(documentXML.utf8)),
            ("word/_rels/document.xml.rels", Data(relationshipXML.utf8)),
            ("word/styles.xml", Data(stylesXML.utf8)),
        ]
        entries.append(contentsOf: context.images.map { ("word/media/\($0.filename)", $0.data) })

        let safeTitle = sanitizedFilename(title)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeTitle)-\(UUID().uuidString.prefix(8)).docx")
        progress?(0.9, "Packaging Word document…")
        await Task.yield()
        try ZipPackageWriter.write(entries: entries, to: outputURL)
        progress?(1, "Document ready")
        return outputURL
    }

    private static func render(block: ContentBlock, context: inout BuildContext) async -> String {
        switch block.type {
        case .heading:
            return heading(block.text, level: 3)
        case .paragraph:
            var result = block.title.isEmpty ? "" : heading(block.title, level: 3)
            result += paragraph(block.text)
            return result
        case .quote:
            var result = block.title.isEmpty ? "" : heading(block.title, level: 3)
            result += paragraph(block.text, style: "Quote")
            return result
        case .code:
            return paragraph(block.text, style: "Code")
        case .divider:
            return """
            <w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="B7B7B7"/></w:pBdr></w:pPr></w:p>
            """
        case .photo:
            var result = ""
            if let reference = block.orderedMediaReferences.first,
               let image = await loadImage(reference: reference),
               let embedded = context.addImage(image) {
                result += imageParagraph(
                    relationshipID: embedded.relationshipID,
                    imageIndex: embedded.imageIndex,
                    width: image.size.width,
                    height: image.size.height,
                    description: block.descriptionText
                )
            } else {
                result += paragraph("[Photo unavailable]")
            }
            if !block.descriptionText.isEmpty {
                result += paragraph(block.descriptionText, style: "Caption")
            }
            if !block.linkURLString.isEmpty {
                result += paragraph("Link: \(block.linkURLString)", style: "Caption")
            }
            return result
        case .gallery:
            var result = ""
            for reference in block.orderedMediaReferences {
                if let image = await loadImage(reference: reference),
                   let embedded = context.addImage(image) {
                    result += imageParagraph(
                        relationshipID: embedded.relationshipID,
                        imageIndex: embedded.imageIndex,
                        width: image.size.width,
                        height: image.size.height,
                        description: block.descriptionText
                    )
                }
            }
            if !block.descriptionText.isEmpty {
                result += paragraph(block.descriptionText, style: "Caption")
            }
            return result
        case .video:
            var result = heading("Video", level: 3)
            if let reference = block.orderedMediaReferences.first,
               let image = await loadImage(reference: reference),
               let embedded = context.addImage(image) {
                result += imageParagraph(
                    relationshipID: embedded.relationshipID,
                    imageIndex: embedded.imageIndex,
                    width: image.size.width,
                    height: image.size.height,
                    description: "Video poster frame"
                )
            }
            if !block.descriptionText.isEmpty {
                result += paragraph(block.descriptionText, style: "Caption")
            }
            return result
        case .map:
            guard let section = block.section else { return paragraph("[Map unavailable]") }
            var result = heading(section.placeName.isEmpty ? "Location" : section.placeName, level: 3)
            if let latitude = section.latitude, let longitude = section.longitude {
                result += paragraph("Coordinates: \(latitude.formatted()), \(longitude.formatted())")
            }
            if !block.descriptionText.isEmpty {
                result += paragraph(block.descriptionText)
            }
            return result
        }
    }

    private static func loadImage(reference: MediaReference) async -> UIImage? {
        guard await PhotoLibraryAccess.isAuthorized() else { return nil }

        let assets = PHAsset.fetchAssets(
            withLocalIdentifiers: [reference.localIdentifier],
            options: nil
        )
        guard let asset = assets.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            var didResume = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1800, height: 1800),
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

    private static func sectionMetadata(_ section: TripSection) -> String {
        var pieces = [section.kind.label]
        if !section.placeName.isEmpty { pieces.append(section.placeName) }
        if let start = section.startDate, let end = section.endDate {
            pieces.append(DateRangeFormatting.summary(start: start, end: end))
        }
        return paragraph(pieces.joined(separator: " • "), style: "Subtitle")
    }

    private static func heading(_ text: String, level: Int) -> String {
        guard !text.isEmpty else { return "" }
        return paragraph(text, style: "Heading\(level)")
    }

    private static func paragraph(_ text: String, style: String? = nil) -> String {
        let paragraphProperties = style.map { "<w:pPr><w:pStyle w:val=\"\($0)\"/></w:pPr>" } ?? ""
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let runs = lines.enumerated().map { index, line in
            let breakXML = index == 0 ? "" : "<w:r><w:br/></w:r>"
            return "\(breakXML)<w:r><w:t xml:space=\"preserve\">\(xmlEscape(String(line)))</w:t></w:r>"
        }.joined()
        return "<w:p>\(paragraphProperties)\(runs)</w:p>"
    }

    private static func imageParagraph(
        relationshipID: String,
        imageIndex: Int,
        width: CGFloat,
        height: CGFloat,
        description: String
    ) -> String {
        let maximumWidth = 5_524_500.0
        let maximumHeight = 4_286_250.0
        let safeWidth = max(width, 1)
        let safeHeight = max(height, 1)
        let scale = min(maximumWidth / safeWidth, maximumHeight / safeHeight)
        let cx = Int(safeWidth * scale)
        let cy = Int(safeHeight * scale)
        let escapedDescription = xmlEscape(description.isEmpty ? "Travel journal image" : description)

        return """
        <w:p>
          <w:r>
            <w:drawing>
              <wp:inline distT="0" distB="0" distL="0" distR="0">
                <wp:extent cx="\(cx)" cy="\(cy)"/>
                <wp:docPr id="\(imageIndex)" name="Picture \(imageIndex)" descr="\(escapedDescription)"/>
                <wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>
                <a:graphic>
                  <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                    <pic:pic>
                      <pic:nvPicPr><pic:cNvPr id="0" name="Picture \(imageIndex)"/><pic:cNvPicPr/></pic:nvPicPr>
                      <pic:blipFill><a:blip r:embed="\(relationshipID)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
                      <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>
                    </pic:pic>
                  </a:graphicData>
                </a:graphic>
              </wp:inline>
            </w:drawing>
          </w:r>
        </w:p>
        """
    }

    private static func xmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func sanitizedFilename(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let scalars = title.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let value = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "RoamStory" : value
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Default Extension="jpg" ContentType="image/jpeg"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
      <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
      <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
      <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
    </Types>
    """

    private static let rootRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
      <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
    </Relationships>
    """

    private static let appPropertiesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"
      xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
      <Application>RoamStory</Application>
    </Properties>
    """

    private static func corePropertiesXML(title: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
          xmlns:dc="http://purl.org/dc/elements/1.1/"
          xmlns:dcterms="http://purl.org/dc/terms/"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>\(xmlEscape(title))</dc:title>
          <dc:creator>RoamStory</dc:creator>
          <dcterms:created xsi:type="dcterms:W3CDTF">\(ISO8601DateFormatter().string(from: .now))</dcterms:created>
        </cp:coreProperties>
        """
    }

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:rPr><w:sz w:val="22"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:rPr><w:b/><w:sz w:val="36"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:rPr><w:b/><w:sz w:val="30"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:rPr><w:b/><w:sz w:val="26"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle"/><w:basedOn w:val="Normal"/><w:rPr><w:color w:val="666666"/><w:i/><w:sz w:val="18"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Caption"><w:name w:val="Caption"/><w:basedOn w:val="Normal"/><w:rPr><w:color w:val="666666"/><w:i/><w:sz w:val="18"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="720"/></w:pPr><w:rPr><w:i/><w:color w:val="555555"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Code"><w:name w:val="Code"/><w:basedOn w:val="Normal"/><w:pPr><w:shd w:fill="F2F2F2"/><w:spacing w:before="120" w:after="120"/></w:pPr><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"/><w:sz w:val="18"/></w:rPr></w:style>
    </w:styles>
    """
}

struct DocxExportView: View {
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
                            Label("Share DOCX", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            generate()
                        } label: {
                            if isGenerating {
                                Text("Generating DOCX…")
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("Generate DOCX", systemImage: "doc.badge.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isGenerating || selectedSections.isEmpty)
                    }
                } footer: {
                    Text("Photos are read from their original library references. Missing media is represented by a placeholder.")
                }
            }
            .navigationTitle("Export to Word")
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
                Text(errorMessage ?? "The document could not be generated.")
            }
        }
    }

    private func selectionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedSectionIDs.contains(id) },
            set: { isSelected in
                if isSelected {
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
        progressLabel = "Preparing document…"
        errorMessage = nil
        Task {
            do {
                exportedURL = try await DocxExporter.export(
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

enum ZipPackageWriter {
    private struct CentralEntry {
        let nameData: Data
        let crc32: UInt32
        let size: UInt32
        let offset: UInt32
        let dosTime: UInt16
        let dosDate: UInt16
    }

    static func write(entries: [(String, Data)], to url: URL) throws {
        var centralEntries: [CentralEntry] = []
        let (dosTime, dosDate) = dosTimestamp(for: .now)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        guard fileManager.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let fileHandle = try FileHandle(forWritingTo: url)

        do {
            var currentOffset: UInt64 = 0

            for (name, contents) in entries {
                guard let offset = UInt32(exactly: currentOffset),
                      let size = UInt32(exactly: contents.count) else {
                    throw DocxExportError.packageTooLarge
                }
                let nameData = Data(name.utf8)
                let checksum = crc32(contents)
                var localHeader = Data()
                localHeader.appendLE(UInt32(0x04034B50))
                localHeader.appendLE(UInt16(20))
                localHeader.appendLE(UInt16(0x0800))
                localHeader.appendLE(UInt16(0))
                localHeader.appendLE(dosTime)
                localHeader.appendLE(dosDate)
                localHeader.appendLE(checksum)
                localHeader.appendLE(size)
                localHeader.appendLE(size)
                localHeader.appendLE(UInt16(nameData.count))
                localHeader.appendLE(UInt16(0))
                localHeader.append(nameData)

                try fileHandle.write(contentsOf: localHeader)
                try fileHandle.write(contentsOf: contents)
                currentOffset += UInt64(localHeader.count) + UInt64(contents.count)

                centralEntries.append(CentralEntry(
                    nameData: nameData,
                    crc32: checksum,
                    size: size,
                    offset: offset,
                    dosTime: dosTime,
                    dosDate: dosDate
                ))
            }

            guard let centralOffset = UInt32(exactly: currentOffset) else {
                throw DocxExportError.packageTooLarge
            }
            var centralDirectory = Data()
            for entry in centralEntries {
                centralDirectory.appendLE(UInt32(0x02014B50))
                centralDirectory.appendLE(UInt16(20))
                centralDirectory.appendLE(UInt16(20))
                centralDirectory.appendLE(UInt16(0x0800))
                centralDirectory.appendLE(UInt16(0))
                centralDirectory.appendLE(entry.dosTime)
                centralDirectory.appendLE(entry.dosDate)
                centralDirectory.appendLE(entry.crc32)
                centralDirectory.appendLE(entry.size)
                centralDirectory.appendLE(entry.size)
                centralDirectory.appendLE(UInt16(entry.nameData.count))
                centralDirectory.appendLE(UInt16(0))
                centralDirectory.appendLE(UInt16(0))
                centralDirectory.appendLE(UInt16(0))
                centralDirectory.appendLE(UInt16(0))
                centralDirectory.appendLE(UInt32(0))
                centralDirectory.appendLE(entry.offset)
                centralDirectory.append(entry.nameData)
            }

            guard let centralSize = UInt32(exactly: centralDirectory.count),
                  let entryCount = UInt16(exactly: centralEntries.count) else {
                throw DocxExportError.packageTooLarge
            }
            var footer = Data()
            footer.appendLE(UInt32(0x06054B50))
            footer.appendLE(UInt16(0))
            footer.appendLE(UInt16(0))
            footer.appendLE(entryCount)
            footer.appendLE(entryCount)
            footer.appendLE(centralSize)
            footer.appendLE(centralOffset)
            footer.appendLE(UInt16(0))

            try fileHandle.write(contentsOf: centralDirectory)
            try fileHandle.write(contentsOf: footer)
            try fileHandle.close()
        } catch {
            try? fileHandle.close()
            try? fileManager.removeItem(at: url)
            throw error
        }
    }

    private static func dosTimestamp(for date: Date) -> (UInt16, UInt16) {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let year = max(1980, components.year ?? 1980)
        let dosTime = UInt16((components.hour ?? 0) << 11)
            | UInt16((components.minute ?? 0) << 5)
            | UInt16((components.second ?? 0) / 2)
        let dosDate = UInt16(year - 1980) << 9
            | UInt16(components.month ?? 1) << 5
            | UInt16(components.day ?? 1)
        return (dosTime, dosDate)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crc32Table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let crc32Table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1
                ? (value >> 1) ^ 0xEDB8_8320
                : value >> 1
        }
        return value
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
