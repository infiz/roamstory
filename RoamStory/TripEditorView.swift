import SwiftData
import SwiftUI

struct TripEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var trip: Trip

    @State private var isEditingTrip = false
    @State private var isCreatingSection = false
    @State private var isExportingDocx = false
    @State private var isExportingHTML = false
    @State private var sectionPendingDeletion: TripSection?
    @State private var sectionListEditMode: EditMode = .inactive

    var body: some View {
        List {
            if !trip.subtitle.isEmpty {
                Text(trip.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                    HStack(spacing: 8) {
                        NavigationLink {
                            SectionLoadingDestination(section: section)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: section.kind.systemImage)
                                    .frame(width: 32, height: 32)
                                    .background(.blue.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(section.title)
                                        .font(.headline)
                                    SectionBlockSummary(section: section)
                                    if let startDate = section.startDate, let endDate = section.endDate {
                                        Text(DateRangeFormatting.summary(start: startDate, end: endDate))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Label {
                                        Text(
                                            "Edited \(section.modifiedAt.formatted(date: .abbreviated, time: .shortened))"
                                        )
                                    } icon: {
                                        Image(systemName: "clock")
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(SectionNavigationButtonStyle())
                        .accessibilityLabel("Open \(section.title)")
                        Menu {
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
                    .swipeActions {
                        Button(role: .destructive) {
                            sectionPendingDeletion = section
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: moveSections)
            }
        }
        .environment(\.editMode, $sectionListEditMode)
        .navigationTitle(trip.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(sectionListEditMode.isEditing ? "Done" : "Reorder") {
                    withAnimation {
                        sectionListEditMode = sectionListEditMode.isEditing
                            ? .inactive
                            : .active
                    }
                }
                .accessibilityHint(
                    sectionListEditMode.isEditing
                        ? "Finishes reordering sections"
                        : "Shows controls for reordering sections"
                )
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
                trip.touch()
                sectionPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { sectionPendingDeletion = nil }
        } message: { section in
            Text("“\(section.title)” and its content will be removed.")
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

private struct EditTripView: View {
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
