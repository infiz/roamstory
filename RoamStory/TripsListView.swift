import SwiftData
import SwiftUI

struct TripsListView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage("tripSortField") private var sortFieldRawValue = TripSortField.modified.rawValue
    @AppStorage("tripSortDirection") private var sortDirectionRawValue = SortDirection.descending.rawValue
    @State private var trips: [Trip] = []
    @State private var isLoadingTrips = true
    @State private var loadErrorMessage: String?
    @State private var isCreatingTrip = false
    @State private var tripBeingEdited: Trip?
    @State private var tripPendingDeletion: Trip?

    private var sortField: TripSortField {
        TripSortField(rawValue: sortFieldRawValue) ?? .modified
    }

    private var sortDirection: SortDirection {
        SortDirection(rawValue: sortDirectionRawValue) ?? .descending
    }

    private var sortedTrips: [Trip] {
        TripSorter.sort(trips, by: sortField, direction: sortDirection)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoadingTrips {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Loading trips…")
                            .font(.subheadline.weight(.semibold))
                        Text("Preparing your travel stories")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Loading trips")
                } else if let loadErrorMessage {
                    ContentUnavailableView {
                        Label("Trips Unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadErrorMessage)
                    } actions: {
                        Button("Try Again") {
                            Task { await loadTrips(showProgress: true) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if sortedTrips.isEmpty {
                    ContentUnavailableView {
                        Label("No Trips", systemImage: "map")
                    } description: {
                        Text("Create a trip, then add sections for the places and experiences you want to remember.")
                    } actions: {
                        Button("Create Trip") { isCreatingTrip = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(sortedTrips) { trip in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(spacing: 8) {
                                    NavigationLink(value: trip) {
                                        TripRowView(trip: trip)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(TripNavigationButtonStyle())
                                    .accessibilityLabel("Open \(trip.title)")
                                    Menu {
                                        Button {
                                            tripBeingEdited = trip
                                        } label: {
                                            Label("Edit Trip", systemImage: "pencil")
                                        }
                                        Divider()
                                        Button(role: .destructive) {
                                            tripPendingDeletion = trip
                                        } label: {
                                            Label("Delete Trip", systemImage: "trash")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .frame(width: 44, height: 32)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("\(trip.title) trip actions")
                                }

                                HStack(spacing: 12) {
                                    Image(systemName: "clock")
                                        .frame(width: 32)
                                    Text("Edited \(DateRangeFormatting.timestamp(trip.modifiedAt))")
                                }
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                if let startDate = trip.startDate, let endDate = trip.endDate {
                                    HStack(spacing: 12) {
                                        Image(systemName: "calendar")
                                            .frame(width: 32)
                                        Text(DateRangeFormatting.summary(start: startDate, end: endDate))
                                            .monospacedDigit()
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityLabel(
                                        "Trip dates \(DateRangeFormatting.summary(start: startDate, end: endDate))"
                                    )
                                }
                            }
                            .accessibilityAction(named: "Delete trip") {
                                tripPendingDeletion = trip
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Trips")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Trip.self) { trip in
                TripEditorView(trip: trip)
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    sortMenu
                    Button {
                        isCreatingTrip = true
                    } label: {
                        Label("Create Trip", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isCreatingTrip, onDismiss: {
                Task { await loadTrips(showProgress: trips.isEmpty) }
            }) {
                CreateTripView()
            }
            .sheet(item: $tripBeingEdited) { trip in
                EditTripView(trip: trip)
            }
            .alert(
                "Delete Trip?",
                isPresented: Binding(
                    get: { tripPendingDeletion != nil },
                    set: { if !$0 { tripPendingDeletion = nil } }
                ),
                presenting: tripPendingDeletion
            ) { trip in
                Button("Delete", role: .destructive) {
                    modelContext.delete(trip)
                    trips.removeAll { $0.id == trip.id }
                    tripPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    tripPendingDeletion = nil
                }
            } message: { trip in
                Text("“\(trip.title)” and all of its sections will be removed from this device.")
            }
        }
        .task {
            await loadTrips(showProgress: true)
        }
    }

    @MainActor
    private func loadTrips(showProgress: Bool) async {
        if showProgress {
            isLoadingTrips = true
        }
        loadErrorMessage = nil
        await Task.yield()

        do {
            trips = try modelContext.fetch(FetchDescriptor<Trip>())
        } catch {
            trips = []
            loadErrorMessage = error.localizedDescription
        }
        isLoadingTrips = false
    }

    private var sortMenu: some View {
        Menu {
            Section("Sort by") {
                ForEach(TripSortField.allCases) { field in
                    Button {
                        sortFieldRawValue = field.rawValue
                    } label: {
                        if field == sortField {
                            Label(field.label, systemImage: "checkmark")
                        } else {
                            Text(field.label)
                        }
                    }
                }
            }

            Section("Order") {
                ForEach(SortDirection.allCases) { direction in
                    Button {
                        sortDirectionRawValue = direction.rawValue
                    } label: {
                        if direction == sortDirection {
                            Label(direction.label, systemImage: "checkmark")
                        } else {
                            Text(direction.label)
                        }
                    }
                }
            }
        } label: {
            Label("Sort Trips", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort trips by \(sortField.label), \(sortDirection.label)")
    }
}

private struct TripRowView: View {
    @Environment(\.modelContext) private var modelContext
    let trip: Trip
    @State private var sectionCount: Int?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "map.fill")
                .frame(width: 32, height: 32)
                .background(.blue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(trip.title)
                    .font(.headline)
                    .lineLimit(1)
                if !trip.subtitle.isEmpty {
                    Text(trip.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let sectionCount {
                    Text("\(sectionCount) \(sectionCount == 1 ? "section" : "sections")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .task(id: trip.id) {
            await loadSectionCount()
        }
    }

    @MainActor
    private func loadSectionCount() async {
        await Task.yield()
        let tripID = trip.id
        let descriptor = FetchDescriptor<TripSection>(
            predicate: #Predicate { section in
                section.trip?.id == tripID
            }
        )
        do {
            // fetchCount avoids materializing section blocks and media relationships.
            sectionCount = try modelContext.fetchCount(descriptor)
        } catch {
            sectionCount = nil
        }
    }
}

private struct TripNavigationButtonStyle: ButtonStyle {
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

private struct CreateTripView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""
    @State private var subtitle = ""
    @State private var hasDateRange = false
    @State private var startDate = DateHourRangeEditor.defaultStart
    @State private var endDate = DateHourRangeEditor.defaultEnd

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                    TextField("Subtitle (optional)", text: $subtitle)
                }
                Section("Date Range") {
                    Toggle("Add date range", isOn: $hasDateRange)
                    if hasDateRange {
                        DateHourRangeEditor(startDate: $startDate, endDate: $endDate)
                    }
                }
            }
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trip = Trip(
                            title: trimmedTitle,
                            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
                            startDate: hasDateRange ? startDate : nil,
                            endDate: hasDateRange ? endDate : nil
                        )
                        modelContext.insert(trip)
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
