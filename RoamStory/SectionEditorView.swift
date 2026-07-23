import MapKit
import SwiftData
import SwiftUI

struct SectionEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var section: TripSection

    @State private var isEditingSection = false
    @State private var mediaPickerMode: MediaPickerMode?
    @State private var blockPendingDeletion: ContentBlock?
    @State private var selectedInsertionIndex: Int?
    @State private var galleryBeingEdited: ContentBlock?
    @State private var photoBeingChanged: ContentBlock?
    @State private var isChangingMapLocation = false
    @State private var photoLinkBeingEdited: ContentBlock?

    var body: some View {
        List {
            if section.orderedBlocks.isEmpty {
                blockInsertionDivider(at: 0)
                ContentUnavailableView {
                    Label("Start This Story", systemImage: "text.badge.plus")
                } description: {
                    Text("Add a paragraph, photos, video, or map.")
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(Array(section.orderedBlocks.enumerated()), id: \.element.id) { index, block in
                    VStack(spacing: 3) {
                        blockInsertionDivider(at: index)

                        VStack(alignment: .leading, spacing: 8) {
                            BlockTypeHeader(
                                type: block.type,
                                blockID: block.id,
                                onDelete: { blockPendingDeletion = block },
                                onEditGallery: { galleryBeingEdited = block },
                                onChangePhoto: {
                                    photoBeingChanged = block
                                    mediaPickerMode = .singlePhoto
                                },
                                onChangeLocation: { isChangingMapLocation = true },
                                onEditPhotoLink: { photoLinkBeingEdited = block },
                                onRemovePhotoLink: {
                                    block.linkURLString = ""
                                    section.touch()
                                },
                                hasLink: !block.linkURLString.isEmpty
                            )
                            BlockEditorView(block: block) {
                                section.touch()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.background, in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(.secondary.opacity(0.22), lineWidth: 1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .swipeActions {
                        Button(role: .destructive) {
                            blockPendingDeletion = block
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let sourceValue = items.first,
                              let sourceID = UUID(uuidString: sourceValue) else { return false }
                        return moveBlock(sourceID: sourceID, before: block.id)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                    .listRowBackground(Color.clear)
                }
                blockInsertionDivider(at: section.orderedBlocks.count)
            }
        }
        .contentMargins(.top, 2, for: .scrollContent)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Text(section.title)
                        .font(.headline)
                        .lineLimit(1)
                    sectionMetadataPill
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Edit Section") { isEditingSection = true }
            }
        }
        .sheet(isPresented: $isEditingSection) {
            EditSectionView(section: section)
        }
        .sheet(item: $mediaPickerMode) { mode in
            MediaPickerView(mode: mode) { selections in
                if mode == .singlePhoto {
                    replacePhoto(with: selections)
                } else {
                    addMedia(selections, mode: mode)
                }
            }
        }
        .sheet(item: $galleryBeingEdited) { block in
            GalleryEditorView(block: block) {
                section.touch()
            }
        }
        .sheet(isPresented: $isChangingMapLocation) {
            MapLocationPicker(
                initialName: section.placeName,
                initialCoordinate: sectionCoordinate
            ) { name, coordinate in
                section.placeName = name
                section.latitude = coordinate.latitude
                section.longitude = coordinate.longitude
                section.touch()
            }
        }
        .sheet(item: $photoLinkBeingEdited) { block in
            PhotoBlockLinkEditor(block: block) {
                section.touch()
            }
            .presentationDetents([.medium])
        }
        .alert(
            "Delete Block?",
            isPresented: Binding(
                get: { blockPendingDeletion != nil },
                set: { if !$0 { blockPendingDeletion = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let blockPendingDeletion {
                    modelContext.delete(blockPendingDeletion)
                    normalizeBlockOrder()
                    section.touch()
                }
                blockPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { blockPendingDeletion = nil }
        } message: {
            Text("This content will be removed from the section. Photos and videos in your Photos library are not deleted.")
        }
    }

    private func blockInsertionDivider(at index: Int) -> some View {
        BlockBoundaryView(isSelected: selectedInsertionIndex == index) { choice in
            selectedInsertionIndex = index
            switch choice {
            case .block(let type): addTextBlock(type)
            case .photos: mediaPickerMode = .photos
            case .gallery: mediaPickerMode = .gallery
            case .videos: mediaPickerMode = .videos
            case .map: addMapBlock()
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 2, trailing: 10))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var sectionMetadataAccessibilityLabel: String {
        if section.placeName.isEmpty {
            return "\(section.kind.label) section"
        }
        return "\(section.kind.label) section at \(section.placeName)"
    }

    private var sectionCoordinate: CLLocationCoordinate2D? {
        guard let latitude = section.latitude, let longitude = section.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var sectionMetadataPill: some View {
        HStack(spacing: 4) {
            Image(systemName: section.kind.systemImage)
                .font(.caption2.weight(.semibold))
            Text(section.placeName.isEmpty ? section.kind.label : section.placeName)
                .lineLimit(1)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.tint.opacity(0.09), in: Capsule())
        .frame(maxWidth: 145)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sectionMetadataAccessibilityLabel)
    }

    private func addTextBlock(_ type: BlockType) {
        let block = ContentBlock(type: type)
        modelContext.insert(block)
        insertBlock(block)
    }

    private func addMapBlock() {
        let block = ContentBlock(type: .map)
        modelContext.insert(block)
        insertBlock(block)
    }

    private func addMedia(_ selections: [PickedMedia], mode: MediaPickerMode) {
        guard !selections.isEmpty else { return }

        if mode == .gallery {
            let references = selections
                .filter { $0.kind == .image }
                .enumerated()
                .map { index, selection in
                    MediaReference(
                        localIdentifier: selection.localIdentifier,
                        kind: .image,
                        originalFilename: selection.originalFilename,
                        sortIndex: index
                    )
                }
            guard !references.isEmpty else { return }
            let block = ContentBlock(
                type: .gallery,
                mediaReferences: references
            )
            modelContext.insert(block)
            insertBlock(block)
        } else {
            for selection in selections {
                let reference = MediaReference(
                    localIdentifier: selection.localIdentifier,
                    kind: selection.kind,
                    originalFilename: selection.originalFilename
                )
                let block = ContentBlock(
                    type: selection.kind == .image ? .photo : .video,
                    mediaReferences: [reference]
                )
                modelContext.insert(block)
                insertBlock(block)
            }
        }
    }

    private func replacePhoto(with selections: [PickedMedia]) {
        defer { photoBeingChanged = nil }
        guard let block = photoBeingChanged,
              let selection = selections.first(where: { $0.kind == .image }) else { return }

        for reference in block.mediaReferences {
            modelContext.delete(reference)
        }
        let replacement = MediaReference(
            localIdentifier: selection.localIdentifier,
            kind: .image,
            originalFilename: selection.originalFilename
        )
        modelContext.insert(replacement)
        block.mediaReferences = [replacement]
        section.touch()
    }

    @discardableResult
    private func moveBlock(sourceID: UUID, before targetID: UUID) -> Bool {
        guard sourceID != targetID else { return false }
        var ordered = section.orderedBlocks
        guard let sourceIndex = ordered.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = ordered.firstIndex(where: { $0.id == targetID }) else { return false }
        let movingBlock = ordered.remove(at: sourceIndex)
        let adjustedTarget = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        ordered.insert(movingBlock, at: adjustedTarget)
        for (index, block) in ordered.enumerated() {
            block.sortIndex = index
        }
        section.touch()
        return true
    }

    private func normalizeBlockOrder() {
        for (index, block) in section.orderedBlocks.enumerated() {
            block.sortIndex = index
        }
    }

    private func insertBlock(_ block: ContentBlock) {
        var ordered = section.orderedBlocks
        let index = min(selectedInsertionIndex ?? ordered.count, ordered.count)
        section.blocks.append(block)
        ordered.insert(block, at: index)
        for (newIndex, orderedBlock) in ordered.enumerated() {
            orderedBlock.sortIndex = newIndex
        }
        selectedInsertionIndex = index + 1
        section.touch()
    }
}

private enum BlockInsertionChoice {
    case block(BlockType)
    case photos
    case gallery
    case videos
    case map
}

private struct BlockBoundaryView: View {
    let isSelected: Bool
    let onAdd: (BlockInsertionChoice) -> Void

    var body: some View {
        Menu {
            Button { onAdd(.block(.paragraph)) } label: {
                Label("Paragraph", systemImage: "text.alignleft")
            }
            Button { onAdd(.block(.heading)) } label: {
                Label("Heading", systemImage: "textformat.size.larger")
            }
            Button { onAdd(.block(.quote)) } label: {
                Label("Quote", systemImage: "quote.opening")
            }
            Button { onAdd(.block(.code)) } label: {
                Label("Code", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Button { onAdd(.block(.divider)) } label: {
                Label("Divider", systemImage: "minus")
            }
            Divider()
            Button { onAdd(.photos) } label: {
                Label("Photos", systemImage: "photo.on.rectangle")
            }
            Button { onAdd(.gallery) } label: {
                Label("Photo Gallery", systemImage: "rectangle.stack")
            }
            Button { onAdd(.videos) } label: {
                Label("Videos", systemImage: "video")
            }
            Button { onAdd(.map) } label: {
                Label("Map", systemImage: "map")
            }
        } label: {
            HStack(spacing: 5) {
                Capsule()
                    .fill(isSelected ? Color.accentColor : .secondary.opacity(0.22))
                    .frame(width: 36, height: 1)
                Image(systemName: isSelected ? "plus.circle.fill" : "plus.circle")
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Capsule()
                    .fill(isSelected ? Color.accentColor : .secondary.opacity(0.22))
                    .frame(width: 36, height: 1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add block at this divider")
        .accessibilityHint("Opens a menu of block types")
    }
}

private struct BlockTypeHeader: View {
    let type: BlockType
    let blockID: UUID
    let onDelete: () -> Void
    let onEditGallery: () -> Void
    let onChangePhoto: () -> Void
    let onChangeLocation: () -> Void
    let onEditPhotoLink: () -> Void
    let onRemovePhotoLink: () -> Void
    let hasLink: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: type.systemImage)
            Text(type.label)
            Spacer()
            Menu {
                if type == .gallery {
                    Button(action: onEditGallery) {
                        Label("Edit Gallery Photos", systemImage: "photo.stack")
                    }
                }
                if type == .photo {
                    Button(action: onChangePhoto) {
                        Label("Change Photo", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(action: onEditPhotoLink) {
                        Label(hasLink ? "Edit Photo Link" : "Add Photo Link", systemImage: "link")
                    }
                    if hasLink {
                        Button(role: .destructive, action: onRemovePhotoLink) {
                            Label("Remove Photo Link", systemImage: "link.badge.minus")
                        }
                    }
                }
                if type == .map {
                    Button(action: onChangeLocation) {
                        Label("Change Location", systemImage: "map")
                    }
                }
                if type == .gallery || type == .photo || type == .map {
                    Divider()
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete \(type.label)", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(type.label) block actions")
            Image(systemName: "line.3.horizontal")
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
                .draggable(blockID.uuidString)
                .accessibilityLabel("Move \(type.label) block")
                .accessibilityHint("Drag to another block to reorder")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .contain)
    }
}

private struct BlockEditorView: View {
    @Bindable var block: ContentBlock
    let onChange: () -> Void

    var body: some View {
        Group {
            switch block.type {
            case .paragraph, .heading, .quote:
                RichParagraphView(block: block, onChange: onChange)
            case .code:
                CodeBlockView(block: block, onChange: onChange)
            case .divider:
                Divider()
                    .padding(.vertical, 12)
            case .photo:
                MediaBlockView(block: block, onChange: onChange)
            case .gallery:
                GalleryBlockView(block: block, onChange: onChange)
            case .video:
                MediaBlockView(block: block, onChange: onChange)
            case .map:
                MapBlockView(block: block, onChange: onChange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowSeparator(.hidden)
    }
}

private struct CodeBlockView: View {
    @Bindable var block: ContentBlock
    let onChange: () -> Void

    var body: some View {
        TextEditor(text: $block.text)
            .font(.system(.body, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.secondary.opacity(0.18), lineWidth: 1)
            }
            .onChange(of: block.text) { _, _ in onChange() }
            .accessibilityLabel("Code editor")
    }
}

private struct RichParagraphView: View {
    @Bindable var block: ContentBlock
    let onChange: () -> Void
    @StateObject private var formattingController = RichTextFormattingController()
    @State private var isEditingLink = false
    @State private var linkAddress = ""

    private let fontChoices = ["New York", "SF Pro", "Georgia", "Avenir Next"]
    private let fontSizes: [CGFloat] = [14, 17, 20, 24, 30, 36]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if block.type == .paragraph || block.type == .quote {
                TextField("Paragraph title (optional)", text: $block.title)
                    .font(.headline)
                    .textInputAutocapitalization(.sentences)
                    .onChange(of: block.title) { _, _ in onChange() }
                    .accessibilityLabel("Paragraph title")
            }

            HStack(spacing: 6) {
                Menu(formattingController.fontFamily) {
                    ForEach(fontChoices, id: \.self) { family in
                        Button(family) {
                            formattingController.applyFontFamily(family)
                        }
                    }
                }
                .buttonStyle(.bordered)

                Menu("\(Int(formattingController.fontSize)) pt") {
                    ForEach(fontSizes, id: \.self) { size in
                        Button("\(Int(size)) pt") {
                            formattingController.applyFontSize(size)
                        }
                    }
                }
                .buttonStyle(.bordered)

                Button {
                    formattingController.toggleBold()
                } label: {
                    Image(systemName: "bold")
                }
                .buttonStyle(.bordered)
                .tint(formattingController.isBold ? .accentColor : .secondary)
                .accessibilityLabel("Toggle bold for selected text")

                Button {
                    formattingController.toggleItalic()
                } label: {
                    Image(systemName: "italic")
                }
                .buttonStyle(.bordered)
                .tint(formattingController.isItalic ? .accentColor : .secondary)
                .accessibilityLabel("Toggle italic for selected text")

                Button {
                    formattingController.toggleUnderline()
                } label: {
                    Image(systemName: "underline")
                }
                .buttonStyle(.bordered)
                .tint(formattingController.isUnderlined ? .accentColor : .secondary)
                .accessibilityLabel("Toggle underline for selected text")

                Button {
                    linkAddress = formattingController.currentLinkURL?.absoluteString ?? ""
                    isEditingLink = true
                } label: {
                    Image(systemName: "link")
                }
                .buttonStyle(.bordered)
                .tint(formattingController.isLinked ? .accentColor : .secondary)
                .disabled(!formattingController.hasTextSelection)
                .accessibilityLabel("Add or edit link for selected text")
            }
            .font(.caption)

            RichTextEditor(
                block: block,
                controller: formattingController,
                onChange: onChange
            )
                .frame(minHeight: block.type == .heading ? 54 : 100)
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $isEditingLink) {
            ParagraphLinkEditor(
                address: $linkAddress,
                hasExistingLink: formattingController.isLinked,
                isValid: { formattingController.isValidLinkAddress($0) },
                onApply: { formattingController.applyLink($0) },
                onRemove: { formattingController.removeLink() }
            )
            .presentationDetents([.medium])
        }
    }
}

private struct ParagraphLinkEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var address: String
    let hasExistingLink: Bool
    let isValid: (String) -> Bool
    let onApply: (String) -> Bool
    let onRemove: () -> Void

    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Web Address") {
                    TextField("Enter a web address", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    if trimmedAddress.isEmpty {
                        Label("A web address is required.", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if !isValid(trimmedAddress) {
                        Label("Enter a valid web address.", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("Addresses without a scheme will use https://.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if hasExistingLink {
                    Section {
                        Button("Remove Link", role: .destructive) {
                            onRemove()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(hasExistingLink ? "Edit Link" : "Add Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        if onApply(trimmedAddress) {
                            dismiss()
                        }
                    }
                    .disabled(!isValid(trimmedAddress))
                }
            }
        }
    }
}

private struct MediaBlockView: View {
    @Bindable var block: ContentBlock
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let reference = block.mediaReferences.first {
                Group {
                    if block.type == .video {
                        VideoAssetView(reference: reference)
                    } else if let linkURL = LinkAddress.normalizedURL(from: block.linkURLString) {
                        Link(destination: linkURL) {
                            PhotoAssetView(reference: reference)
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: "link.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.white, .blue)
                                        .padding(10)
                                }
                        }
                        .accessibilityHint("Opens the photo link")
                    } else {
                        PhotoAssetView(reference: reference)
                    }
                }
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                MissingMediaView()
            }

            TextField(
                block.type == .video ? "Describe this video" : "Describe this photo",
                text: $block.descriptionText,
                axis: .vertical
            )
            .font(.subheadline)
            .onChange(of: block.descriptionText) { _, _ in onChange() }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PhotoBlockLinkEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var block: ContentBlock
    let onChange: () -> Void
    @State private var address: String

    init(block: ContentBlock, onChange: @escaping () -> Void) {
        self.block = block
        self.onChange = onChange
        _address = State(initialValue: block.linkURLString)
    }

    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        LinkAddress.normalizedURL(from: trimmedAddress) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Web Address") {
                    TextField("Enter a web address", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    if trimmedAddress.isEmpty {
                        Label("A web address is required.", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if !isValid {
                        Label("Enter a valid web address.", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("Tapping the photo will open this address. Addresses without a scheme use https://.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !block.linkURLString.isEmpty {
                    Section {
                        Button("Remove Photo Link", role: .destructive) {
                            block.linkURLString = ""
                            onChange()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(block.linkURLString.isEmpty ? "Add Photo Link" : "Edit Photo Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        guard let url = LinkAddress.normalizedURL(from: trimmedAddress) else { return }
                        block.linkURLString = url.absoluteString
                        onChange()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

private struct GalleryBlockView: View {
    @Bindable var block: ContentBlock
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TabView {
                ForEach(block.orderedMediaReferences) { reference in
                    PhotoAssetView(reference: reference)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 2)
                }
            }
            .frame(height: 240)
            .tabViewStyle(.page(indexDisplayMode: .always))

            TextField("Describe this gallery", text: $block.descriptionText, axis: .vertical)
                .font(.subheadline)
                .onChange(of: block.descriptionText) { _, _ in onChange() }

        }
        .padding(.vertical, 8)
    }
}

private struct GalleryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var block: ContentBlock
    let onChange: () -> Void

    @State private var isAddingPhotos = false
    @State private var referencePendingDeletion: MediaReference?

    var body: some View {
        NavigationStack {
            List {
                if block.orderedMediaReferences.isEmpty {
                    ContentUnavailableView(
                        "Empty Gallery",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Add photos to rebuild this gallery.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(block.orderedMediaReferences) { reference in
                        HStack(spacing: 12) {
                            PhotoAssetView(reference: reference)
                                .frame(width: 88, height: 66)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(reference.originalFilename.isEmpty ? "Photo" : reference.originalFilename)
                                    .lineLimit(1)
                                Text("Drag to reorder")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .contentShape(Rectangle())
                                .draggable(reference.id.uuidString)
                                .accessibilityLabel("Move photo")
                                .accessibilityHint("Drag to another photo to reorder")
                            Menu {
                                Button(role: .destructive) {
                                    referencePendingDeletion = reference
                                } label: {
                                    Label("Remove Photo", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                            }
                            .accessibilityLabel("Photo actions")
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                referencePendingDeletion = reference
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let sourceValue = items.first,
                                  let sourceID = UUID(uuidString: sourceValue) else { return false }
                            return movePhoto(sourceID: sourceID, before: reference.id)
                        }
                    }
                }
            }
            .navigationTitle("Gallery Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddingPhotos = true
                    } label: {
                        Label("Add Photos", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingPhotos) {
                MediaPickerView(mode: .gallery, onComplete: addPhotos)
            }
            .alert(
                "Remove Photo from Gallery?",
                isPresented: Binding(
                    get: { referencePendingDeletion != nil },
                    set: { if !$0 { referencePendingDeletion = nil } }
                )
            ) {
                Button("Remove", role: .destructive) { removePendingPhoto() }
                Button("Cancel", role: .cancel) { referencePendingDeletion = nil }
            } message: {
                Text("The photo will be removed from this gallery. The original in your Photos library will not be deleted.")
            }
        }
    }

    private func addPhotos(_ selections: [PickedMedia]) {
        let existingIdentifiers = Set(block.mediaReferences.map(\.localIdentifier))
        let newSelections = selections.filter {
            $0.kind == .image && !existingIdentifiers.contains($0.localIdentifier)
        }
        guard !newSelections.isEmpty else { return }

        var nextIndex = block.orderedMediaReferences.count
        for selection in newSelections {
            let reference = MediaReference(
                localIdentifier: selection.localIdentifier,
                kind: .image,
                originalFilename: selection.originalFilename,
                sortIndex: nextIndex
            )
            modelContext.insert(reference)
            block.mediaReferences.append(reference)
            nextIndex += 1
        }
        onChange()
    }

    @discardableResult
    private func movePhoto(sourceID: UUID, before targetID: UUID) -> Bool {
        guard sourceID != targetID else { return false }
        var ordered = block.orderedMediaReferences
        guard let sourceIndex = ordered.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = ordered.firstIndex(where: { $0.id == targetID }) else { return false }
        let movingPhoto = ordered.remove(at: sourceIndex)
        let adjustedTarget = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        ordered.insert(movingPhoto, at: adjustedTarget)
        for (index, reference) in ordered.enumerated() {
            reference.sortIndex = index
        }
        onChange()
        return true
    }

    private func removePendingPhoto() {
        guard let referencePendingDeletion else { return }
        block.mediaReferences.removeAll { $0.id == referencePendingDeletion.id }
        modelContext.delete(referencePendingDeletion)
        normalizePhotoOrder()
        onChange()
        self.referencePendingDeletion = nil
    }

    private func normalizePhotoOrder() {
        for (index, reference) in block.orderedMediaReferences.enumerated() {
            reference.sortIndex = index
        }
    }
}

private struct MapBlockView: View {
    @Bindable var block: ContentBlock
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let section = block.section,
               let latitude = section.latitude,
               let longitude = section.longitude {
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                ))) {
                    Marker(section.placeName.isEmpty ? section.title : section.placeName, coordinate: coordinate)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                ContentUnavailableView(
                    "No Location",
                    systemImage: "map",
                    description: Text("Use Change Location from the map block actions.")
                )
                .frame(maxWidth: .infinity)
                .frame(height: 180)
            }

            TextField("Describe this location", text: $block.descriptionText, axis: .vertical)
                .font(.subheadline)
                .onChange(of: block.descriptionText) { _, _ in onChange() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

private struct MissingMediaView: View {
    var body: some View {
        ContentUnavailableView(
            "Media Unavailable",
            systemImage: "photo.badge.exclamationmark",
            description: Text("The Photos reference is missing or access is unavailable.")
        )
        .frame(height: 200)
    }
}

private struct EditSectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var section: TripSection

    @State private var draftTitle: String
    @State private var draftKind: SectionKind
    @State private var draftPlaceName: String
    @State private var draftCoordinate: CLLocationCoordinate2D?
    @State private var isChoosingLocation = false
    @State private var hasDateRange: Bool
    @State private var draftStartDate: Date
    @State private var draftEndDate: Date

    init(section: TripSection) {
        self.section = section
        _draftTitle = State(initialValue: section.title)
        _draftKind = State(initialValue: section.kind)
        _draftPlaceName = State(initialValue: section.placeName)
        let legacyStart = section.startDate ?? section.occurredAt
        _hasDateRange = State(initialValue: legacyStart != nil || section.endDate != nil)
        let start = legacyStart ?? DateHourRangeEditor.defaultStart
        _draftStartDate = State(initialValue: start)
        _draftEndDate = State(initialValue: section.endDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: start)!)
        if let latitude = section.latitude, let longitude = section.longitude {
            _draftCoordinate = State(initialValue: CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            ))
        } else {
            _draftCoordinate = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Section") {
                    TextField("Title", text: $draftTitle)
                    Picker("Kind", selection: $draftKind) {
                        ForEach(SectionKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                }
                Section("Date Range") {
                    Toggle("Add date range", isOn: $hasDateRange)
                    if hasDateRange {
                        DateHourRangeEditor(startDate: $draftStartDate, endDate: $draftEndDate)
                    }
                }
                Section("Location (optional)") {
                    if let draftCoordinate {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: draftCoordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                        ))) {
                            Marker(
                                draftPlaceName.isEmpty ? "Selected location" : draftPlaceName,
                                coordinate: draftCoordinate
                            )
                        }
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        if !draftPlaceName.isEmpty {
                            Label(draftPlaceName, systemImage: "mappin.and.ellipse")
                        }
                    } else {
                        ContentUnavailableView(
                            "No Location Selected",
                            systemImage: "map",
                            description: Text("Choose a place by searching or tapping the map.")
                        )
                        .frame(height: 140)
                    }

                    Button {
                        isChoosingLocation = true
                    } label: {
                        Label(
                            draftCoordinate == nil ? "Choose on Map" : "Change Location",
                            systemImage: "map"
                        )
                    }

                    if draftCoordinate != nil {
                        Button("Remove Location", role: .destructive) {
                            draftCoordinate = nil
                            draftPlaceName = ""
                        }
                    }
                }
            }
            .navigationTitle("Edit Section")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        section.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        section.kind = draftKind
                        section.placeName = draftPlaceName.trimmingCharacters(in: .whitespacesAndNewlines)
                        section.latitude = draftCoordinate?.latitude
                        section.longitude = draftCoordinate?.longitude
                        section.startDate = hasDateRange ? draftStartDate.alignedToHour : nil
                        section.endDate = hasDateRange ? draftEndDate.alignedToHour : nil
                        section.occurredAt = nil
                        section.touch()
                        dismiss()
                    }
                    .disabled(
                        draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        (hasDateRange && draftEndDate < draftStartDate)
                    )
                }
            }
            .sheet(isPresented: $isChoosingLocation) {
                MapLocationPicker(
                    initialName: draftPlaceName,
                    initialCoordinate: draftCoordinate
                ) { name, coordinate in
                    draftPlaceName = name
                    draftCoordinate = coordinate
                }
            }
        }
    }
}

private struct MapLocationPicker: View {
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var searchResults: [LocationSearchResult] = []
    @State private var selectedName: String
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var position: MapCameraPosition
    @State private var isSearching = false

    let onSelect: (String, CLLocationCoordinate2D) -> Void

    init(
        initialName: String,
        initialCoordinate: CLLocationCoordinate2D?,
        onSelect: @escaping (String, CLLocationCoordinate2D) -> Void
    ) {
        _selectedName = State(initialValue: initialName)
        _selectedCoordinate = State(initialValue: initialCoordinate)
        let region = MKCoordinateRegion(
            center: initialCoordinate ?? CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
            span: MKCoordinateSpan(
                latitudeDelta: initialCoordinate == nil ? 60 : 0.03,
                longitudeDelta: initialCoordinate == nil ? 60 : 0.03
            )
        )
        _position = State(initialValue: .region(region))
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !searchResults.isEmpty {
                    List(searchResults) { result in
                        Button {
                            select(result)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.name)
                                    .foregroundStyle(.primary)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .frame(maxHeight: 220)
                }

                MapReader { proxy in
                    Map(position: $position) {
                        if let selectedCoordinate {
                            Marker(
                                selectedName.isEmpty ? "Selected location" : selectedName,
                                coordinate: selectedCoordinate
                            )
                        }
                    }
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                    }
                    .onTapGesture { point in
                        guard let coordinate = proxy.convert(point, from: .local) else { return }
                        selectedCoordinate = coordinate
                        selectedName = "Dropped Pin"
                        searchResults = []
                        reverseGeocode(coordinate)
                    }
                }

                if let selectedCoordinate {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Place name", text: $selectedName)
                            .font(.headline)
                        Text(
                            "\(selectedCoordinate.latitude.formatted(.number.precision(.fractionLength(5)))), " +
                            "\(selectedCoordinate.longitude.formatted(.number.precision(.fractionLength(5))))"
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
                }
            }
            .navigationTitle("Choose Location")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search places or addresses")
            .onSubmit(of: .search) { search() }
            .onChange(of: searchText) { _, newValue in
                if newValue.isEmpty { searchResults = [] }
            }
            .overlay {
                if isSearching {
                    ProgressView("Searching…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Location") {
                        guard let selectedCoordinate else { return }
                        let name = selectedName.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSelect(name.isEmpty ? "Dropped Pin" : name, selectedCoordinate)
                        dismiss()
                    }
                    .disabled(selectedCoordinate == nil)
                }
            }
        }
    }

    private func search() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearching = true
        Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            if let region = position.region { request.region = region }
            do {
                let response = try await MKLocalSearch(request: request).start()
                searchResults = response.mapItems.map(LocationSearchResult.init)
            } catch {
                searchResults = []
            }
            isSearching = false
        }
    }

    private func select(_ result: LocationSearchResult) {
        selectedName = result.name
        selectedCoordinate = result.coordinate
        searchText = ""
        searchResults = []
        position = .region(MKCoordinateRegion(
            center: result.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        ))
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) {
        Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "\(coordinate.latitude),\(coordinate.longitude)"
            request.region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            if let item = try? await MKLocalSearch(request: request).start().mapItems.first,
               let name = item.name,
               !name.isEmpty {
                selectedName = name
            }
        }
    }
}

private struct LocationSearchResult: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D

    init(mapItem: MKMapItem) {
        name = mapItem.name ?? "Unnamed Place"
        subtitle = mapItem.placemark.title ?? ""
        coordinate = mapItem.placemark.coordinate
    }
}
