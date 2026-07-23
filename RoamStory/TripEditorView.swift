import SwiftData
import SwiftUI

struct TripEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var trip: Trip

    @State private var isEditingTrip = false
    @State private var isCreatingSection = false
    @State private var sectionPendingDeletion: TripSection?

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
                            SectionEditorView(section: section)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: section.kind.systemImage)
                                    .frame(width: 32, height: 32)
                                    .background(.blue.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(section.title)
                                        .font(.headline)
                                    Text("\(section.kind.label) · \(section.blocks.count) blocks")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let startDate = section.startDate, let endDate = section.endDate {
                                        Text(DateRangeFormatting.summary(start: startDate, end: endDate))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
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
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 32)
                            .contentShape(Rectangle())
                            .draggable(section.id.uuidString)
                            .accessibilityLabel("Move \(section.title) section")
                            .accessibilityHint("Drag to another section to reorder")
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let sourceValue = items.first,
                              let sourceID = UUID(uuidString: sourceValue) else { return false }
                        return moveSection(sourceID: sourceID, before: section.id)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            sectionPendingDeletion = section
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle(trip.title)
        .toolbar {
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

    @discardableResult
    private func moveSection(sourceID: UUID, before targetID: UUID) -> Bool {
        guard sourceID != targetID else { return false }
        var ordered = trip.orderedSections
        guard let sourceIndex = ordered.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = ordered.firstIndex(where: { $0.id == targetID }) else { return false }
        let movingSection = ordered.remove(at: sourceIndex)
        let adjustedTarget = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        ordered.insert(movingSection, at: adjustedTarget)
        for (index, section) in ordered.enumerated() {
            section.sortIndex = index
        }
        trip.touch()
        return true
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
        _endDate = State(initialValue: trip.endDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: proposedStart)!)
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
        _draftEndDate = State(initialValue: trip.endDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: start)!)
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

    static var defaultStart: Date { Calendar.current.dateInterval(of: .hour, for: .now)?.start ?? .now }
    static var defaultEnd: Date { Calendar.current.date(byAdding: .hour, value: 1, to: defaultStart)! }

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
            get: { Calendar.current.component(.hour, from: date) },
            set: { hour in
                date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
            }
        )
    }
}

enum DateRangeFormatting {
    static func summary(start: Date, end: Date) -> String {
        "\(start.formatted(date: .abbreviated, time: .shortened)) – \(end.formatted(date: .abbreviated, time: .shortened))"
    }

    static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
