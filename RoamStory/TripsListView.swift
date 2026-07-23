import SwiftData
import SwiftUI

struct TripsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var trips: [Trip]

    @AppStorage("tripSortField") private var sortFieldRawValue = TripSortField.modified.rawValue
    @AppStorage("tripSortDirection") private var sortDirectionRawValue = SortDirection.descending.rawValue
    @State private var isCreatingTrip = false
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
                if sortedTrips.isEmpty {
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
                            NavigationLink(value: trip) {
                                TripRowView(trip: trip)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    tripPendingDeletion = trip
                                } label: {
                                    Label("Delete", systemImage: "trash")
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
            .sheet(isPresented: $isCreatingTrip) {
                CreateTripView()
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
                    tripPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    tripPendingDeletion = nil
                }
            } message: { trip in
                Text("“\(trip.title)” and all of its sections will be removed from this device.")
            }
        }
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
    let trip: Trip

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.blue.gradient)
                .frame(width: 58, height: 58)
                .overlay {
                    Image(systemName: "map.fill")
                        .foregroundStyle(.white)
                        .font(.title2)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(trip.title)
                    .font(.headline)
                    .lineLimit(1)
                if !trip.subtitle.isEmpty {
                    Text(trip.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let startDate = trip.startDate, let endDate = trip.endDate {
                    Label(
                        DateRangeFormatting.summary(start: startDate, end: endDate),
                        systemImage: "calendar"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Text("\(trip.sections.count) sections · Edited \(trip.modifiedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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
