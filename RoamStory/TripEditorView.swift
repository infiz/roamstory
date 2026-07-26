import SwiftData
import SwiftUI

struct TripEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var authentication: AuthenticationStore
    @Bindable var trip: Trip

    @State private var isEditingTrip = false
    @State private var isCreatingSection = false
    @State private var isExportingDocx = false
    @State private var isExportingHTML = false
    @State private var sectionBeingEdited: TripSection?
    @State private var sectionPendingDeletion: TripSection?
    @State private var isPublishing = false
    @State private var publishingMessage: String?
    @State private var publishErrorMessage: String?
    @State private var publishedURL: URL?
    @State private var isShowingAccountMismatch = false
    @State private var pendingPublishConfirmation: PublishConfirmation?
    @State private var isShowingNoRepublishRequired = false

    var body: some View {
        List {
            if let startDate = trip.startDate, let endDate = trip.endDate {
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
                .padding(.vertical, 0)
                .listRowInsets(
                    EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .environment(\.defaultMinListRowHeight, 0)
                .accessibilityLabel(
                    "Trip dates \(DateRangeFormatting.summary(start: startDate, end: endDate))"
                )
            }

            if let publishedURL = trip.publishedURL {
                PublishedTripLinkRow(
                    tripTitle: trip.title,
                    url: publishedURL
                )
            }

            if trip.orderedSections.isEmpty {
                ContentUnavailableView {
                    Label("No Sections", systemImage: "rectangle.stack")
                } description: {
                    Text("Add a section for a place, activity, meal, stay, journey, event, wildlife encounter, or reflection.")
                } actions: {
                    Button("Add Section") { isCreatingSection = true }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(trip.orderedSections) { section in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            NavigationLink {
                                SectionLoadingDestination(section: section)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: section.kind.systemImage)
                                        .frame(width: 32, height: 32)
                                        .background(.blue.opacity(0.12), in: Circle())
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(section.title)
                                                .font(.headline)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                            Text(section.formattedDataSize)
                                                .font(.caption2.weight(.medium))
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(.secondary.opacity(0.12), in: Capsule())
                                                .fixedSize()
                                        }
                                        SectionBlockSummary(section: section)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(SectionNavigationButtonStyle())
                            .accessibilityLabel("Open \(section.title)")
                            Menu {
                                Button {
                                    sectionBeingEdited = section
                                } label: {
                                    Label("Edit Section", systemImage: "pencil")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    sectionPendingDeletion = section
                                } label: {
                                    Label("Delete Section", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .frame(width: 44, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("\(section.title) section actions")
                        }

                        HStack(spacing: 12) {
                            Image(systemName: "clock")
                                .frame(width: 32)
                            Text("Edited \(DateRangeFormatting.timestamp(section.modifiedAt))")
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if let startDate = section.startDate, let endDate = section.endDate {
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(
                                "Section dates \(DateRangeFormatting.summary(start: startDate, end: endDate))"
                            )
                        }
                    }
                }
                .onMove(perform: moveSections)
            }
        }
        .contentMargins(.top, 2, for: .scrollContent)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Text(trip.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(trip.formattedDataSize)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.12), in: Capsule())
                        .fixedSize()
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isCreatingSection = true
                } label: {
                    Label("Add Section", systemImage: "plus")
                }
                Menu {
                    Button {
                        isEditingTrip = true
                    } label: {
                        Label("Edit Trip Details", systemImage: "pencil")
                    }
                    Button {
                        isExportingDocx = true
                    } label: {
                        Label("Export to Word", systemImage: "doc")
                    }
                    Button {
                        isExportingHTML = true
                    } label: {
                        Label("Export HTML Package", systemImage: "archivebox")
                    }
                    Divider()
                    Button {
                        beginPublishing()
                    } label: {
                        Label(
                            trip.publicationID == nil ? "Publish Trip" : "Republish Trip",
                            systemImage: "icloud.and.arrow.up"
                        )
                    }
                    .disabled(isPublishing)
                    if let url = trip.publishedURL {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Open Published Trip", systemImage: "safari")
                        }
                        ShareLink(item: url) {
                            Label("Share Published Link", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Label("Trip Actions", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isCreatingSection) {
            CreateSectionView(trip: trip)
        }
        .sheet(isPresented: $isEditingTrip) {
            EditTripView(trip: trip)
        }
        .sheet(item: $sectionBeingEdited) { section in
            EditSectionView(section: section)
        }
        .sheet(isPresented: $isExportingDocx) {
            DocxExportView(
                title: trip.title,
                sections: trip.orderedSections,
                allowsSelection: true
            )
        }
        .sheet(isPresented: $isExportingHTML) {
            HtmlExportView(
                title: trip.title,
                sections: trip.orderedSections,
                allowsSelection: true
            )
        }
        .overlay {
            if isPublishing {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(publishingMessage ?? "Publishing…")
                            .font(.headline)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .alert(
            "Delete Section?",
            isPresented: Binding(
                get: { sectionPendingDeletion != nil },
                set: { if !$0 { sectionPendingDeletion = nil } }
            ),
            presenting: sectionPendingDeletion
        ) { section in
            Button("Delete", role: .destructive) {
                modelContext.delete(section)
                try? modelContext.save()
                trip.touch()
                sectionPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { sectionPendingDeletion = nil }
        } message: { section in
            Text("“\(section.title)” and its content will be removed.")
        }
        .alert(
            "Unable to Publish",
            isPresented: Binding(
                get: { publishErrorMessage != nil },
                set: { if !$0 { publishErrorMessage = nil } }
            )
        ) {
            Button("OK") { publishErrorMessage = nil }
        } message: {
            Text(publishErrorMessage ?? "")
        }
        .modifier(
            PublishConfirmationModifier(
                confirmation: $pendingPublishConfirmation,
                isRepublish: trip.publicationID != nil
            ) { confirmation in
                Task { await publishTrip(confirmation: confirmation) }
            }
        )
        .alert("No Republish Required", isPresented: $isShowingNoRepublishRequired) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The published trip already matches this trip and all media is up to date.")
        }
        .alert("Trip Published", isPresented: Binding(
            get: { publishedURL != nil },
            set: { if !$0 { publishedURL = nil } }
        )) {
            if let publishedURL {
                Button("Open") { openURL(publishedURL) }
                Button("Copy Link") {
                    UIPasteboard.general.string = publishedURL.absoluteString
                }
            }
            Button("Done", role: .cancel) { publishedURL = nil }
        } message: {
            Text("The latest version is available through its web link.")
        }
        .alert("Trip Linked to Another Account", isPresented: $isShowingAccountMismatch) {
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This trip is linked to another RoamStory account. Sign in to that account to republish it. Secure account transfer will be added in the account-transfer phase."
            )
        }
    }

    private func moveSections(from source: IndexSet, to destination: Int) {
        var ordered = trip.orderedSections
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, section) in ordered.enumerated() {
            section.sortIndex = index
        }
        trip.touch()
    }

    private func beginPublishing() {
        guard let account = authentication.account else {
            publishErrorMessage = "Sign in from Setup before publishing this trip."
            return
        }
        if let owner = trip.publishedOwnerAccountID, owner != account.id {
            isShowingAccountMismatch = true
            return
        }
        Task { await preparePublishConfirmation() }
    }

    @MainActor
    private func preparePublishConfirmation() async {
        guard !isPublishing else { return }
        isPublishing = true
        publishingMessage = "Calculating upload size…"
        defer {
            publishingMessage = nil
            isPublishing = false
        }

        do {
            let references = trip.orderedSections
                .flatMap(\.orderedBlocks)
                .flatMap(\.orderedMediaReferences)
            let localMedia = try await LocalPublishMedia.load(references)
            var preparedMedia: [PreparedPublishMedia] = []
            for (index, media) in localMedia.enumerated() {
                publishingMessage = "Checking media \(index + 1) of \(localMedia.count)…"
                let prepared = try await authentication.prepareMedia(media)
                preparedMedia.append(
                    PreparedPublishMedia(localMedia: media, upload: prepared)
                )
            }
            let mediaUuids = Dictionary(
                uniqueKeysWithValues: preparedMedia.map {
                    ($0.localMedia.referenceID, $0.upload.mediaUuid)
                }
            )
            let mediaMetadata = Dictionary(
                uniqueKeysWithValues: preparedMedia.compactMap { item in
                    item.localMedia.metadata.map {
                        (item.localMedia.referenceID, $0)
                    }
                }
            )
            let request = PublishTripRequest(
                trip: trip,
                mediaUuids: mediaUuids,
                mediaMetadata: mediaMetadata
            )
            let contentFingerprint = try request.contentFingerprint()
            let confirmation = PublishConfirmation(
                preparedMedia: preparedMedia,
                tripDataByteCount: try request.encodedByteCount(),
                contentFingerprint: contentFingerprint
            )
            if trip.publicationID != nil,
               trip.publishedContentFingerprint == contentFingerprint,
               !preparedMedia.contains(where: \.upload.uploadRequired) {
                isShowingNoRepublishRequired = true
            } else {
                pendingPublishConfirmation = confirmation
            }
        } catch {
            publishErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func publishTrip(confirmation: PublishConfirmation) async {
        guard !isPublishing else { return }
        let preparedMedia = confirmation.preparedMedia
        isPublishing = true
        publishingMessage = trip.publicationID == nil ? "Publishing trip…" : "Publishing update…"
        defer {
            publishingMessage = nil
            isPublishing = false
        }

        do {
            var mediaUuids: [UUID: UUID] = [:]
            for (index, item) in preparedMedia.enumerated() {
                if item.upload.uploadRequired {
                    publishingMessage = "Uploading media \(index + 1) of \(preparedMedia.count)…"
                    try await authentication.uploadMedia(
                        item.localMedia,
                        to: item.upload.mediaUuid
                    )
                }
                mediaUuids[item.localMedia.referenceID] = item.upload.mediaUuid
            }
            publishingMessage = trip.publicationID == nil ? "Publishing trip…" : "Publishing update…"
            let mediaMetadata = Dictionary(
                uniqueKeysWithValues: preparedMedia.compactMap { item in
                    item.localMedia.metadata.map {
                        (item.localMedia.referenceID, $0)
                    }
                }
            )
            let request = PublishTripRequest(
                trip: trip,
                mediaUuids: mediaUuids,
                mediaMetadata: mediaMetadata
            )
            let result = try await authentication.publish(request)
            trip.publishedOwnerAccountID = result.ownerAccountUuid
            trip.publishedTripID = result.tripUuid
            trip.publicationID = result.publicationUuid
            trip.publishedRevisionID = result.revisionUuid
            trip.publishedVersion = result.version
            trip.publishedURLString = result.publicURL.absoluteString
            trip.publishedAt = result.publishedAt
            trip.publishedContentFingerprint = confirmation.contentFingerprint
            try modelContext.save()
            publishedURL = result.publicURL
        } catch {
            publishErrorMessage = error.localizedDescription
        }
    }

}

private struct PublishedTripLinkRow: View {
    @Environment(\.openURL) private var openURL

    let tripTitle: String
    let url: URL

    var body: some View {
        HStack(spacing: 12) {
            Button {
                openURL(url)
            } label: {
                Label("Published Trip", systemImage: "checkmark.icloud")
                    .font(.headline)
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the published trip in your browser")

            Spacer()

            ShareLink(
                item: url,
                subject: Text(tripTitle),
                message: Text("View my RoamStory trip: \(tripTitle)")
            ) {
                Image(systemName: "square.and.arrow.up")
                    .font(.headline)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Share published trip")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }
}

private struct PreparedPublishMedia {
    let localMedia: LocalPublishMedia
    let upload: PreparedMediaUpload
}

private struct PublishConfirmation {
    let preparedMedia: [PreparedPublishMedia]
    let tripDataByteCount: Int64
    let contentFingerprint: String

    private var mediaByteCount: Int64 {
        preparedMedia.reduce(Int64.zero) { total, item in
            guard item.upload.uploadRequired else { return total }
            return total + Int64(item.localMedia.data.count)
        }
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(
            fromByteCount: tripDataByteCount + mediaByteCount,
            countStyle: .file
        )
    }

    var formattedTripDataSize: String {
        ByteCountFormatter.string(fromByteCount: tripDataByteCount, countStyle: .file)
    }

    var formattedMediaSize: String {
        ByteCountFormatter.string(fromByteCount: mediaByteCount, countStyle: .file)
    }
}

private struct PublishConfirmationModifier: ViewModifier {
    @Binding var confirmation: PublishConfirmation?
    let isRepublish: Bool
    let onConfirm: (PublishConfirmation) -> Void

    func body(content: Content) -> some View {
        content.alert(
            isRepublish ? "Republish Trip?" : "Publish Trip?",
            isPresented: Binding(
                get: { confirmation != nil },
                set: { if !$0 { confirmation = nil } }
            ),
            presenting: confirmation
        ) { pending in
            Button(isRepublish ? "Republish" : "Publish") {
                confirmation = nil
                onConfirm(pending)
            }
            Button("Cancel", role: .cancel) {
                confirmation = nil
            }
        } message: { pending in
            Text(
                "RoamStory will upload \(pending.formattedTotalSize): \(pending.formattedTripDataSize) of trip, section, and block data plus \(pending.formattedMediaSize) of new or changed media. Continue?"
            )
        }
    }
}

private struct SectionNavigationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.62 : 1)
            .background(
                configuration.isPressed ? Color.secondary.opacity(0.1) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct SectionLoadingDestination: View {
    let section: TripSection
    @State private var isReady = false

    var body: some View {
        Group {
            if isReady {
                SectionEditorView(section: section)
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Opening section…")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Opening section")
            }
        }
        .task {
            // Let the navigation transition render before constructing a media-heavy editor.
            await Task.yield()
            isReady = true
        }
    }
}

private struct SectionBlockSummary: View {
    @Environment(\.modelContext) private var modelContext
    let section: TripSection
    @State private var blockCount: Int?

    var body: some View {
        Text(summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .task(id: section.id) {
                await loadBlockCount()
            }
    }

    private var summary: String {
        guard let blockCount else { return section.kind.label }
        return "\(section.kind.label) · \(blockCount) \(blockCount == 1 ? "block" : "blocks")"
    }

    @MainActor
    private func loadBlockCount() async {
        await Task.yield()
        let sectionID = section.id
        let descriptor = FetchDescriptor<ContentBlock>(
            predicate: #Predicate { block in
                block.section?.id == sectionID
            }
        )
        blockCount = try? modelContext.fetchCount(descriptor)
    }
}

private struct CreateSectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let trip: Trip

    @State private var title = ""
    @State private var kind = SectionKind.activity
    @State private var hasDateRange = false
    @State private var startDate: Date
    @State private var endDate: Date

    init(trip: Trip) {
        self.trip = trip
        let proposedStart = trip.startDate ?? DateHourRangeEditor.defaultStart
        _startDate = State(initialValue: proposedStart)
        _endDate = State(
            initialValue: trip.endDate
                ?? Calendar.autoupdatingCurrent.date(byAdding: .hour, value: 1, to: proposedStart)
                ?? proposedStart.addingTimeInterval(3_600)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Section title", text: $title)
                Picker("Kind", selection: $kind) {
                    ForEach(SectionKind.allCases) { kind in
                        Label(kind.label, systemImage: kind.systemImage)
                            .tag(kind)
                    }
                }
                Section("Date Range") {
                    Toggle("Add date range", isOn: $hasDateRange)
                    if hasDateRange {
                        DateHourRangeEditor(startDate: $startDate, endDate: $endDate)
                    }
                }
            }
            .navigationTitle("New Section")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let section = TripSection(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            kind: kind,
                            sortIndex: trip.sections.count,
                            startDate: hasDateRange ? startDate : nil,
                            endDate: hasDateRange ? endDate : nil
                        )
                        modelContext.insert(section)
                        trip.sections.append(section)
                        trip.touch()
                        dismiss()
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        (hasDateRange && endDate < startDate)
                    )
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct EditTripView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var trip: Trip

    @State private var draftTitle: String
    @State private var draftSubtitle: String
    @State private var hasDateRange: Bool
    @State private var draftStartDate: Date
    @State private var draftEndDate: Date

    init(trip: Trip) {
        self.trip = trip
        _draftTitle = State(initialValue: trip.title)
        _draftSubtitle = State(initialValue: trip.subtitle)
        _hasDateRange = State(initialValue: trip.startDate != nil || trip.endDate != nil)
        let start = trip.startDate ?? DateHourRangeEditor.defaultStart
        _draftStartDate = State(initialValue: start)
        _draftEndDate = State(
            initialValue: trip.endDate
                ?? Calendar.autoupdatingCurrent.date(byAdding: .hour, value: 1, to: start)
                ?? start.addingTimeInterval(3_600)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $draftTitle)
                TextField("Subtitle", text: $draftSubtitle)
                Section("Date Range") {
                    Toggle("Add date range", isOn: $hasDateRange)
                    if hasDateRange {
                        DateHourRangeEditor(startDate: $draftStartDate, endDate: $draftEndDate)
                    }
                }
            }
            .navigationTitle("Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        trip.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        trip.subtitle = draftSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        trip.startDate = hasDateRange ? draftStartDate.alignedToHour : nil
                        trip.endDate = hasDateRange ? draftEndDate.alignedToHour : nil
                        trip.touch()
                        dismiss()
                    }
                    .disabled(
                        draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        (hasDateRange && draftEndDate < draftStartDate)
                    )
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct DateHourRangeEditor: View {
    @Binding var startDate: Date
    @Binding var endDate: Date

    static var defaultStart: Date {
        Calendar.autoupdatingCurrent.dateInterval(of: .hour, for: .now)?.start ?? .now
    }
    static var defaultEnd: Date {
        Calendar.autoupdatingCurrent.date(byAdding: .hour, value: 1, to: defaultStart)
            ?? defaultStart.addingTimeInterval(3_600)
    }

    var body: some View {
        DateHourRow(label: "Starts", date: $startDate)
        DateHourRow(label: "Ends", date: $endDate)
        if endDate < startDate {
            Label("End must be after start", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

private struct DateHourRow: View {
    let label: String
    @Binding var date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                DatePicker(label, selection: $date, displayedComponents: .date)
                    .labelsHidden()
                Spacer()
                Picker("Hour", selection: hourBinding) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(DateRangeFormatting.hourLabel(hour)).tag(hour)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: { Calendar.autoupdatingCurrent.component(.hour, from: date) },
            set: { hour in
                date = Calendar.autoupdatingCurrent.date(
                    bySettingHour: hour,
                    minute: 0,
                    second: 0,
                    of: date
                ) ?? date
            }
        )
    }
}

enum DateRangeFormatting {
    private static let deviceDateTimeFormatter: DateFormatter = makeFormatter(
        timeZone: .autoupdatingCurrent
    )

    static func summary(start: Date, end: Date) -> String {
        "\(deviceDateTimeFormatter.string(from: start)) - \(deviceDateTimeFormatter.string(from: end))"
    }

    static func summary(start: Date, end: Date, timeZone: TimeZone) -> String {
        let formatter = makeFormatter(timeZone: timeZone)
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    static func timestamp(_ date: Date) -> String {
        deviceDateTimeFormatter.string(from: date)
    }

    static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        makeFormatter(timeZone: timeZone).string(from: date)
    }

    private static func makeFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }

    static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.autoupdatingCurrent.date(from: components) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
