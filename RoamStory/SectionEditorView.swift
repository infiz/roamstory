import Combine
import MapKit
import SwiftData
import SwiftUI
import UIKit

private struct BlockUndoFocusTarget {
    let blockID: UUID
    let originalIndex: Int
}

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
    @State private var isExportingDocx = false
    @State private var isExportingHTML = false
    @State private var editMode: EditMode = .inactive
    @State private var sectionUndoManager = UndoManager()
    @State private var hasInitializedUndoScope = false
    @State private var undoStateVersion = 0
    @State private var pendingUndoFocusTarget: BlockUndoFocusTarget?
    @State private var undoFocusTargets: [BlockUndoFocusTarget?] = []
    @State private var redoFocusTargets: [BlockUndoFocusTarget?] = []
    @State private var isPerformingHistoryAction = false
    @State private var scrollTargetBlockID: UUID?
    @State private var highlightedBlockID: UUID?

    var body: some View {
        List {
            if let startDate = section.startDate, let endDate = section.endDate {
                HStack {
                    Label {
                        Text(DateRangeFormatting.summary(start: startDate, end: endDate))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Text(section.formattedDataSize)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }
                .padding(.vertical, 0)
                .listRowInsets(
                    EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .environment(\.defaultMinListRowHeight, 0)
                .accessibilityLabel(
                    "Section dates \(DateRangeFormatting.summary(start: startDate, end: endDate))"
                )
            } else {
                HStack {
                    Spacer()
                    Text(section.formattedDataSize)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }
                .padding(.vertical, 0)
                .listRowInsets(
                    EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .environment(\.defaultMinListRowHeight, 0)
            }

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
                                onDelete: { blockPendingDeletion = block },
                                onEditGallery: { galleryBeingEdited = block },
                                onChangePhoto: {
                                    photoBeingChanged = block
                                    mediaPickerMode = .singlePhoto
                                },
                                onChangeLocation: { isChangingMapLocation = true },
                                onEditPhotoLink: { photoLinkBeingEdited = block },
                                onRemovePhotoLink: {
                                    markBlockChanged(block.id)
                                    block.linkURLString = ""
                                    section.touch()
                                },
                                hasLink: !block.linkURLString.isEmpty,
                                canMoveUp: index > 0,
                                canMoveDown: index < section.orderedBlocks.count - 1,
                                onMoveUp: { moveBlock(block.id, by: -1) },
                                onMoveDown: { moveBlock(block.id, by: 1) }
                            )
                            BlockEditorView(
                                block: block,
                                undoManager: sectionUndoManager
                            ) {
                                markBlockChanged(block.id)
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
                    .id(block.id)
                    .swipeActions {
                        Button(role: .destructive) {
                            blockPendingDeletion = block
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                    .listRowBackground(Color.clear)
                    .overlay {
                        if highlightedBlockID == block.id {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.accentColor, lineWidth: 3)
                                .padding(.horizontal, 7)
                        }
                    }
                }
                .onMove(perform: moveBlocks)
                blockInsertionDivider(at: section.orderedBlocks.count)
            }
        }
        .environment(\.editMode, $editMode)
        .scrollPosition(id: $scrollTargetBlockID, anchor: .center)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            sectionUndoManager.groupsByEvent = true
            sectionUndoManager.levelsOfUndo = 100
            // Flush navigation/list mutations before installing the scoped manager.
            // Otherwise SwiftData can register a pending section insertion or
            // relationship change as the first "section edit" undo operation.
            modelContext.processPendingChanges()
            modelContext.undoManager = sectionUndoManager
            modelContext.processPendingChanges()
            if !hasInitializedUndoScope {
                sectionUndoManager.removeAllActions()
                hasInitializedUndoScope = true
            }
            refreshUndoAvailability()
        }
        .onDisappear {
            // The model context is shared by the navigation stack. Do not let this
            // section's history capture trip-list or other section operations.
            if modelContext.undoManager === sectionUndoManager {
                modelContext.undoManager = nil
                section.touch()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup)
        ) { notification in
            guard notification.object as? UndoManager === sectionUndoManager else { return }
            if !isPerformingHistoryAction,
               !sectionUndoManager.isUndoing,
               !sectionUndoManager.isRedoing,
               sectionUndoManager.canUndo {
                undoFocusTargets.append(pendingUndoFocusTarget)
                redoFocusTargets.removeAll()
                self.pendingUndoFocusTarget = nil
            }
            refreshUndoAvailability()
        }
        .contentMargins(.top, 2, for: .scrollContent)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Text(section.title)
                        .font(.headline)
                        .lineLimit(1)
                    sectionMetadataPill
                    Text(section.formattedDataSize)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode.isEditing ? "Done" : "Reorder") {
                    withAnimation {
                        editMode = editMode.isEditing ? .inactive : .active
                    }
                }
                .accessibilityHint(
                    editMode.isEditing
                        ? "Hides block reordering controls"
                        : "Shows block reordering controls"
                )
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        undo()
                    } label: {
                        Label(
                            sectionUndoManager.undoMenuItemTitle,
                            systemImage: "arrow.uturn.backward"
                        )
                    }
                    .disabled(!canUndo)
                    .keyboardShortcut("z", modifiers: .command)

                    Button {
                        redo()
                    } label: {
                        Label(
                            sectionUndoManager.redoMenuItemTitle,
                            systemImage: "arrow.uturn.forward"
                        )
                    }
                    .disabled(!canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])

                    Divider()

                    Button {
                        isEditingSection = true
                    } label: {
                        Label("Edit Section", systemImage: "pencil")
                    }
                    Button {
                        isExportingDocx = true
                    } label: {
                        Label("Export Section to Word", systemImage: "doc")
                    }
                    Button {
                        isExportingHTML = true
                    } label: {
                        Label("Export Section as HTML", systemImage: "archivebox")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Section actions")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    dismissKeyboard()
                } label: {
                    Text("Done")
                        .fontWeight(.semibold)
                }
                .accessibilityLabel("Done editing")
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!canUndo)
                .accessibilityHint("Reverses the most recent section change")

                Button {
                    redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!canRedo)
                .accessibilityHint("Restores the most recently undone section change")

                Spacer()
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
                markBlockChanged(block.id)
                section.touch()
            }
        }
        .sheet(isPresented: $isChangingMapLocation) {
            MapLocationPicker(
                initialName: section.placeName,
                initialCoordinate: sectionCoordinate
            ) { name, coordinate in
                if let mapBlock = section.orderedBlocks.first(where: { $0.type == .map }) {
                    markBlockChanged(mapBlock.id)
                }
                section.placeName = name
                section.latitude = coordinate.latitude
                section.longitude = coordinate.longitude
                section.touch()
            }
        }
        .sheet(item: $photoLinkBeingEdited) { block in
            PhotoBlockLinkEditor(block: block) {
                markBlockChanged(block.id)
                section.touch()
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isExportingDocx) {
            DocxExportView(
                title: section.title,
                sections: [section],
                allowsSelection: false
            )
        }
        .sheet(isPresented: $isExportingHTML) {
            HtmlExportView(
                title: section.title,
                sections: [section],
                allowsSelection: false
            )
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
                    markBlockChanged(blockPendingDeletion.id)
                    modelContext.delete(blockPendingDeletion)
                    try? modelContext.save()
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

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private var canUndo: Bool {
        _ = undoStateVersion
        return sectionUndoManager.canUndo
    }

    private var canRedo: Bool {
        _ = undoStateVersion
        return sectionUndoManager.canRedo
    }

    private func undo() {
        dismissKeyboard()
        guard sectionUndoManager.canUndo else { return }
        let focusTarget: BlockUndoFocusTarget? = undoFocusTargets.isEmpty
            ? nil
            : undoFocusTargets.removeLast()
        isPerformingHistoryAction = true
        sectionUndoManager.undo()
        isPerformingHistoryAction = false
        redoFocusTargets.append(focusTarget)
        if let focusTarget {
            reveal(focusTarget)
        }
        refreshUndoAvailability()
    }

    private func redo() {
        dismissKeyboard()
        guard sectionUndoManager.canRedo else { return }
        let focusTarget: BlockUndoFocusTarget? = redoFocusTargets.isEmpty
            ? nil
            : redoFocusTargets.removeLast()
        isPerformingHistoryAction = true
        sectionUndoManager.redo()
        isPerformingHistoryAction = false
        undoFocusTargets.append(focusTarget)
        if let focusTarget {
            reveal(focusTarget)
        }
        refreshUndoAvailability()
    }

    private func refreshUndoAvailability() {
        undoStateVersion &+= 1
    }

    private func markBlockChanged(_ blockID: UUID) {
        let index = section.orderedBlocks.firstIndex { $0.id == blockID }
            ?? section.orderedBlocks.count
        pendingUndoFocusTarget = BlockUndoFocusTarget(
            blockID: blockID,
            originalIndex: index
        )
    }

    private func reveal(_ target: BlockUndoFocusTarget) {
        Task { @MainActor in
            await Task.yield()
            let blocks = section.orderedBlocks
            let fallbackID = blocks.isEmpty
                ? nil
                : blocks[min(target.originalIndex, blocks.count - 1)].id
            let resolvedID = blocks.first(where: { $0.id == target.blockID })?.id
                ?? fallbackID
            guard let resolvedID else { return }
            scrollTargetBlockID = nil
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.25)) {
                scrollTargetBlockID = resolvedID
            }
            highlightedBlockID = resolvedID
            try? await Task.sleep(for: .seconds(1.2))
            if highlightedBlockID == resolvedID {
                highlightedBlockID = nil
            }
        }
    }

    private func blockInsertionDivider(at index: Int) -> some View {
        BlockBoundaryView { choice in
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
        markBlockChanged(block.id)

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

    private func moveBlocks(from source: IndexSet, to destination: Int) {
        var ordered = section.orderedBlocks
        if let sourceIndex = source.first, ordered.indices.contains(sourceIndex) {
            markBlockChanged(ordered[sourceIndex].id)
        }
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, block) in ordered.enumerated() {
            block.sortIndex = index
        }
        section.touch()
    }

    private func moveBlock(_ blockID: UUID, by offset: Int) {
        markBlockChanged(blockID)
        var ordered = section.orderedBlocks
        guard let sourceIndex = ordered.firstIndex(where: { $0.id == blockID }) else { return }
        let destination = sourceIndex + offset
        guard ordered.indices.contains(destination) else { return }
        ordered.swapAt(sourceIndex, destination)
        for (index, block) in ordered.enumerated() {
            block.sortIndex = index
        }
        section.touch()
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
        markBlockChanged(block.id)
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
    let onAdd: (BlockInsertionChoice) -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 5) {
                Capsule()
                    .fill(.secondary.opacity(0.22))
                    .frame(maxWidth: 36)
                    .frame(height: 1)
                Capsule()
                    .fill(.secondary.opacity(0.22))
                    .frame(maxWidth: 36)
                    .frame(height: 1)
            }
            .frame(maxWidth: .infinity)

            addMenu
        }
        .frame(maxWidth: .infinity)
        .frame(height: 26)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    private var addMenu: some View {
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
            Image(systemName: "plus.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add block at this divider")
        .accessibilityHint("Opens a menu of block types")
    }
}

private struct BlockTypeHeader: View {
    let type: BlockType
    let onDelete: () -> Void
    let onEditGallery: () -> Void
    let onChangePhoto: () -> Void
    let onChangeLocation: () -> Void
    let onEditPhotoLink: () -> Void
    let onRemovePhotoLink: () -> Void
    let hasLink: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

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
                Button(action: onMoveUp) {
                    Label("Move Up", systemImage: "arrow.up")
                }
                .disabled(!canMoveUp)
                Button(action: onMoveDown) {
                    Label("Move Down", systemImage: "arrow.down")
                }
                .disabled(!canMoveDown)
                Divider()
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
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .contain)
    }
}

private struct BlockEditorView: View {
    @Bindable var block: ContentBlock
    let undoManager: UndoManager
    let onChange: () -> Void

    var body: some View {
        Group {
            switch block.type {
            case .paragraph:
                ParagraphBlockView(
                    block: block,
                    undoManager: undoManager,
                    onChange: onChange
                )
            case .heading, .quote:
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

private struct ParagraphBlockView: View {
    @Bindable var block: ContentBlock
    let undoManager: UndoManager
    let onChange: () -> Void
    @State private var isEditingFullScreen = false

    var body: some View {
        Button {
            isEditingFullScreen = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if !block.title.isEmpty {
                    Text(block.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                if block.text.isEmpty {
                    Text("Tap to write this paragraph")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    Text(displayText)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }

                Label("Tap to edit full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            block.title.isEmpty
                ? "Edit paragraph full screen"
                : "Edit \(block.title) paragraph full screen"
        )
        .fullScreenCover(isPresented: $isEditingFullScreen) {
            FullScreenParagraphEditor(
                block: block,
                sectionUndoManager: undoManager,
                onChange: onChange
            )
        }
    }

    private var displayText: AttributedString {
        guard let data = block.attributedTextData,
              let decoded = try? NSKeyedUnarchiver.unarchivedObject(
                  ofClass: NSAttributedString.self,
                  from: data
              ) else {
            return AttributedString(block.text)
        }
        return AttributedString(decoded)
    }
}

private struct FullScreenParagraphEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var block: ContentBlock
    let sectionUndoManager: UndoManager
    let onChange: () -> Void
    @State private var isClosing = false
    @State private var paragraphUndoManager = UndoManager()
    @State private var undoStateVersion = 0

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    RichParagraphView(
                        block: block,
                        onChange: onChange,
                        minimumEditorHeight: max(geometry.size.height - 170, 300)
                    )
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(block.title.isEmpty ? "Edit Paragraph" : block.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        guard !isClosing else { return }
                        isClosing = true
                        dismissKeyboard()
                        Task { @MainActor in
                            await Task.yield()
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(isClosing)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        undo()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!canUndo || isClosing)
                    .keyboardShortcut("z", modifiers: .command)

                    Button {
                        redo()
                    } label: {
                        Label("Redo", systemImage: "arrow.uturn.forward")
                    }
                    .disabled(!canRedo || isClosing)
                    .keyboardShortcut("z", modifiers: [.command, .shift])

                    Spacer()
                }
            }
        }
        .onAppear {
            paragraphUndoManager.groupsByEvent = true
            paragraphUndoManager.levelsOfUndo = 100
            paragraphUndoManager.removeAllActions()
            modelContext.undoManager = paragraphUndoManager
            refreshUndoAvailability()
        }
        .onDisappear {
            if modelContext.undoManager === paragraphUndoManager {
                modelContext.undoManager = sectionUndoManager
            }
        }
    }

    private var canUndo: Bool {
        _ = undoStateVersion
        return paragraphUndoManager.canUndo
    }

    private var canRedo: Bool {
        _ = undoStateVersion
        return paragraphUndoManager.canRedo
    }

    private func undo() {
        dismissKeyboard()
        paragraphUndoManager.undo()
        refreshUndoAvailability()
    }

    private func redo() {
        dismissKeyboard()
        paragraphUndoManager.redo()
        refreshUndoAvailability()
    }

    private func refreshUndoAvailability() {
        undoStateVersion &+= 1
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

private struct CodeBlockView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var block: ContentBlock
    let onChange: () -> Void
    @State private var draftText: String
    @State private var pendingCommitTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    init(block: ContentBlock, onChange: @escaping () -> Void) {
        self.block = block
        self.onChange = onChange
        _draftText = State(initialValue: block.text)
    }

    var body: some View {
        TextEditor(text: $draftText)
            .focused($isFocused)
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
            .onChange(of: draftText) { _, newValue in
                scheduleCommit(commitAtWordBoundary: newValue.last?.isWhitespace == true)
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { commitPendingText() }
            }
            .onChange(of: block.text) { _, newValue in
                if !isFocused { draftText = newValue }
            }
            .onDisappear { commitPendingText() }
            .accessibilityLabel("Code editor")
    }

    private func scheduleCommit(commitAtWordBoundary: Bool) {
        pendingCommitTask?.cancel()
        if commitAtWordBoundary {
            commitPendingText()
            return
        }
        pendingCommitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            commitPendingText()
        }
    }

    private func commitPendingText() {
        pendingCommitTask?.cancel()
        pendingCommitTask = nil
        guard block.text != draftText else { return }
        modelContext.undoManager?.beginUndoGrouping()
        block.text = draftText
        onChange()
        modelContext.undoManager?.endUndoGrouping()
        modelContext.undoManager?.setActionName("Edit Code")
    }
}

private struct RichParagraphView: View {
    @Bindable var block: ContentBlock
    let onChange: () -> Void
    var minimumEditorHeight: CGFloat? = nil
    @StateObject private var formattingController = RichTextFormattingController()
    @State private var isEditingLink = false
    @State private var linkAddress = ""

    private let fontChoices = ["New York", "SF Pro", "Georgia", "Avenir Next"]
    private let fontSizes: [CGFloat] = [14, 17, 20, 24, 30, 36]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if block.type == .paragraph || block.type == .quote {
                BatchedTextField(
                    "Paragraph title (optional)",
                    text: $block.title,
                    actionName: "Edit Title",
                    onChange: onChange
                )
                    .font(.headline)
                    .textInputAutocapitalization(.sentences)
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
                .frame(
                    minHeight: minimumEditorHeight
                        ?? (block.type == .heading ? 54 : 100)
                )
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
    @State private var isShowingFullScreenPhoto = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let reference = block.mediaReferences.first {
                GeometryReader { geometry in
                    Group {
                        if block.type == .video {
                            VideoAssetView(reference: reference)
                        } else {
                            Button {
                                isShowingFullScreenPhoto = true
                            } label: {
                                PhotoAssetView(reference: reference)
                                    .frame(
                                        width: geometry.size.width,
                                        height: geometry.size.height
                                    )
                            }
                            .frame(
                                width: geometry.size.width,
                                height: geometry.size.height
                            )
                            .buttonStyle(.plain)
                            .accessibilityLabel("View photo full screen")
                            .overlay(alignment: .topTrailing) {
                                if let linkURL = LinkAddress.normalizedURL(from: block.linkURLString) {
                                    Link(destination: linkURL) {
                                        Image(systemName: "link")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .frame(width: 36, height: 36)
                                            .background(.blue.opacity(0.92), in: Circle())
                                    }
                                    .padding(.top, 10)
                                    .padding(.trailing, 14)
                                    .accessibilityLabel("Open photo link")
                                    .accessibilityHint("Opens the attached web address")
                                }
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                MissingMediaView()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(block.type == .video ? "Video caption" : "Photo caption")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                BlockMultilineTextField(
                    prompt: "Add a caption",
                    text: $block.caption,
                    actionName: "Edit Caption",
                    accessibilityHint: "Tap anywhere in this row to edit the caption",
                    onChange: onChange
                )
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fullScreenCover(isPresented: $isShowingFullScreenPhoto) {
            if let reference = block.mediaReferences.first {
                FullScreenSinglePhotoView(
                    reference: reference,
                    caption: block.caption
                )
            }
        }
    }
}

private struct FullScreenSinglePhotoView: View {
    @Environment(\.dismiss) private var dismiss
    let reference: MediaReference
    let caption: String

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PhotoAssetView(
                reference: reference,
                fitEntireImage: true,
                backgroundColor: .black
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    .accessibilityLabel("Close full-screen photo")
                }
                .padding()
                Spacer()
                if !caption.isEmpty {
                    Text(caption)
                        .font(.body)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                        .accessibilityLabel("Photo caption")
                }
            }
        }
        .statusBarHidden()
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
    @State private var fullScreenPhotoIndex = 0
    @State private var isShowingFullScreenGallery = false
    @State private var selectedPhotoIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BatchedTextField(
                "Gallery title (optional)",
                text: $block.title,
                actionName: "Edit Gallery Title",
                onChange: onChange
            )
            .font(.headline)
            .textInputAutocapitalization(.sentences)

            TabView(selection: $selectedPhotoIndex) {
                ForEach(Array(block.orderedMediaReferences.enumerated()), id: \.element.id) { index, reference in
                    Button {
                        fullScreenPhotoIndex = index
                        isShowingFullScreenGallery = true
                    } label: {
                        PhotoAssetView(reference: reference, fitEntireImage: true)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 2)
                    }
                    .buttonStyle(.plain)
                    .tag(index)
                    .accessibilityLabel("View gallery photo \(index + 1) full screen")
                }
            }
            .frame(height: 240)
            .tabViewStyle(.page(indexDisplayMode: .always))

            if block.orderedMediaReferences.indices.contains(selectedPhotoIndex) {
                let selectedReference = block.orderedMediaReferences[selectedPhotoIndex]
                VStack(alignment: .leading, spacing: 3) {
                    Text("Photo \(selectedPhotoIndex + 1) caption")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    BatchedTextField(
                        "Add a caption",
                        text: Bindable(selectedReference).caption,
                        axis: .vertical,
                        actionName: "Edit Photo Caption",
                        onChange: onChange
                    )
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }

        }
        .padding(.vertical, 8)
        .onChange(of: block.orderedMediaReferences.count) { _, count in
            selectedPhotoIndex = min(selectedPhotoIndex, max(count - 1, 0))
        }
        .fullScreenCover(isPresented: $isShowingFullScreenGallery) {
            FullScreenGalleryView(
                references: block.orderedMediaReferences,
                initialIndex: fullScreenPhotoIndex
            )
        }
    }
}

private struct FullScreenGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    let references: [MediaReference]
    @State private var selectedIndex: Int

    init(references: [MediaReference], initialIndex: Int) {
        self.references = references
        _selectedIndex = State(
            initialValue: min(max(initialIndex, 0), max(references.count - 1, 0))
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(Array(references.enumerated()), id: \.element.id) { index, reference in
                    PhotoAssetView(
                        reference: reference,
                        fitEntireImage: true,
                        backgroundColor: .black
                    )
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack {
                HStack {
                    Text("\(selectedIndex + 1) of \(references.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(.black.opacity(0.55), in: Capsule())
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    .accessibilityLabel("Close full-screen gallery")
                }
                .padding()
                Spacer()
                if references.indices.contains(selectedIndex),
                   !references[selectedIndex].caption.isEmpty {
                    Text(references[selectedIndex].caption)
                        .font(.body)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                        .accessibilityLabel("Photo caption")
                }
            }
        }
        .statusBarHidden()
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
                                BatchedTextField(
                                    "Photo caption (optional)",
                                    text: Bindable(reference).caption,
                                    axis: .vertical,
                                    actionName: "Edit Photo Caption",
                                    onChange: onChange
                                )
                                .font(.caption)
                                .lineLimit(3)
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

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let section = block.section,
               let latitude = section.latitude,
               let longitude = section.longitude {
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                ZStack(alignment: .topTrailing) {
                    Map(position: $position) {
                        Marker(section.placeName.isEmpty ? section.title : section.placeName, coordinate: coordinate)
                    }
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                    }
                    .onAppear {
                        position = .camera(MapCamera(
                            centerCoordinate: coordinate,
                            distance: 3000,
                            heading: 0,
                            pitch: 0
                        ))
                    }

                    Button {
                        withAnimation(.easeInOut) {
                            position = .camera(MapCamera(
                                centerCoordinate: coordinate,
                                distance: 3000,
                                heading: 0,
                                pitch: 0
                            ))
                        }
                    } label: {
                        Image(systemName: "location.north.line.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    }
                    .padding(8)
                    .accessibilityLabel("Recenter map on location and face north")
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

            BlockMultilineTextField(
                prompt: "Describe this location",
                text: $block.mapDescription,
                actionName: "Edit Location Description",
                accessibilityHint: "Tap anywhere in this row to edit the location description",
                onChange: onChange
            )
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

private struct BlockMultilineTextField: View {
    var body: some View {
        BatchedTextField(
            prompt,
            text: $text,
            axis: .vertical,
            actionName: actionName,
            onChange: onChange
        )
            .font(.subheadline)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityHint(accessibilityHint)
    }

    let prompt: String
    @Binding var text: String
    let actionName: String
    let accessibilityHint: String
    let onChange: () -> Void
}

private struct BatchedTextField: View {
    @Environment(\.modelContext) private var modelContext
    let prompt: String
    @Binding var text: String
    let axis: Axis
    let actionName: String
    let onChange: () -> Void
    @State private var draftText: String
    @State private var pendingCommitTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    init(
        _ prompt: String,
        text: Binding<String>,
        axis: Axis = .horizontal,
        actionName: String,
        onChange: @escaping () -> Void
    ) {
        self.prompt = prompt
        _text = text
        self.axis = axis
        self.actionName = actionName
        self.onChange = onChange
        _draftText = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        TextField(prompt, text: $draftText, axis: axis)
            .focused($isFocused)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    isFocused = true
                }
            )
            .onChange(of: draftText) { _, newValue in
                scheduleCommit(commitAtWordBoundary: newValue.last?.isWhitespace == true)
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { commitPendingText() }
            }
            .onChange(of: text) { _, newValue in
                if !isFocused { draftText = newValue }
            }
            .onSubmit { commitPendingText() }
            .onDisappear { commitPendingText() }
    }

    private func scheduleCommit(commitAtWordBoundary: Bool) {
        pendingCommitTask?.cancel()
        if commitAtWordBoundary {
            commitPendingText()
            return
        }
        pendingCommitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            commitPendingText()
        }
    }

    private func commitPendingText() {
        pendingCommitTask?.cancel()
        pendingCommitTask = nil
        guard text != draftText else { return }
        modelContext.undoManager?.beginUndoGrouping()
        text = draftText
        onChange()
        modelContext.undoManager?.endUndoGrouping()
        modelContext.undoManager?.setActionName(actionName)
    }
}

struct EditSectionView: View {
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
        _draftEndDate = State(
            initialValue: section.endDate
                ?? Calendar.autoupdatingCurrent.date(byAdding: .hour, value: 1, to: start)
                ?? start.addingTimeInterval(3_600)
        )
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

    private let initialCoordinate: CLLocationCoordinate2D?
    let onSelect: (String, CLLocationCoordinate2D) -> Void

    init(
        initialName: String,
        initialCoordinate: CLLocationCoordinate2D?,
        onSelect: @escaping (String, CLLocationCoordinate2D) -> Void
    ) {
        self.initialCoordinate = initialCoordinate
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
                    ZStack(alignment: .topTrailing) {
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

                        if let targetCoordinate = selectedCoordinate ?? initialCoordinate {
                            Button {
                                withAnimation(.easeInOut) {
                                    position = .camera(MapCamera(
                                        centerCoordinate: targetCoordinate,
                                        distance: 3000,
                                        heading: 0,
                                        pitch: 0
                                    ))
                                }
                            } label: {
                                Image(systemName: "location.north.line.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.primary)
                                    .padding(10)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
                            }
                            .padding(12)
                            .accessibilityLabel("Recenter map on location and face north")
                        }
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
