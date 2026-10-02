import SwiftUI
import MapKit

// MARK: - HistoryView

/// History tab: all logged visits grouped by date, with search and period filters.
struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var searchText = ""
    @State private var filter: HistoryFilter = .all

    private var filteredVisits: [Visit] {
        appState.visits
            .filter { filter.includes($0.date) }
            .filter { visit in
                searchText.isEmpty
                    || visit.dishName.localizedCaseInsensitiveContains(searchText)
                    || visit.restaurant.name.localizedCaseInsensitiveContains(searchText)
                    || visit.cuisine.rawValue.localizedCaseInsensitiveContains(searchText)
            }
    }

    private var sections: [(group: VisitDateGroup, visits: [Visit])] {
        let grouped = Dictionary(grouping: filteredVisits) { visit in
            VisitDateGroup(date: visit.date)
        }
        return grouped.keys.sorted().map { group in
            let visits = (grouped[group] ?? []).sorted { $0.date > $1.date }
            return (group: group, visits: visits)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader("History") {
                    ProfileAvatarButton()
                }

                SearchField(placeholder: "Search visits", text: $searchText)

                HStack(spacing: 8) {
                    ForEach(HistoryFilter.allCases) { option in
                        FilterChip(title: option.rawValue, isSelected: option == filter, selectedColor: Theme.orange) {
                            filter = option
                        }
                    }
                }

                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .appBackground()
        .navigationTitle("History")
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var content: some View {
        if appState.visits.isEmpty {
            EmptyHistoryView {
                router.selectedTab = .explore
            }
        } else if filteredVisits.isEmpty {
            if searchText.isEmpty {
                ContentUnavailableView("No visits in this period", systemImage: "calendar", description: Text("Try a different filter."))
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        } else {
            ForEach(sections, id: \.group) { section in
                SectionCaption(section.group.title)
                    .padding(.top, 8)

                ForEach(section.visits) { visit in
                    NavigationLink(value: AppRoute.visitDetail(visit)) {
                        VisitRow(visit: visit)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - HistoryFilter

private enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case thisWeek = "This week"
    case thisMonth = "This month"

    var id: Self { self }

    func includes(_ date: Date) -> Bool {
        switch self {
        case .all: true
        case .thisWeek: Calendar.current.isDate(date, equalTo: .now, toGranularity: .weekOfYear)
        case .thisMonth: Calendar.current.isDate(date, equalTo: .now, toGranularity: .month)
        }
    }
}

// MARK: - EmptyHistoryView

/// "No visits yet" state shown when the student hasn't logged anything.
private struct EmptyHistoryView: View {
    let onExplore: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.ink)
                .frame(width: 200, height: 200)
                .background(Theme.orangeTint.opacity(0.7), in: Circle())

            VStack(spacing: 6) {
                Text("No visits yet")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)
                Text("Start exploring and your visits will show up here.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Button("Explore places", action: onExplore)
                .buttonStyle(.brandPrimary)
                .padding(.top, 8)
        }
        .padding(.top, 48)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - VisitDetailView

struct VisitDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false

    let visit: Visit

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FoodImageView(imageName: visit.imageName, cuisine: visit.cuisine)
                    .frame(height: 240)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(visit.dishName)
                            .font(.largeTitle.bold())
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        if visit.isAutoDetected {
                            PillLabel(text: "Auto-detected", style: .orange)
                        }
                    }

                    PillLabel(text: visit.cuisine.rawValue, style: .green, font: .subheadline.weight(.medium))

                    restaurantCard
                    amountCard

                    VStack(alignment: .leading, spacing: 8) {
                        SectionCaption("Rating")
                        StarRatingView(rating: visit.rating)
                    }

                    if !visit.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionCaption("Notes")
                            Text(visit.notes)
                                .foregroundStyle(Theme.ink)
                                .cardStyle()
                        }
                    }

                    Text(visit.date.formatted(date: .complete, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("Delete visit", role: .destructive) {
                        isConfirmingDelete = true
                    }
                    .buttonStyle(BrandTextButtonStyle(color: Theme.destructive))
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .appBackground()
        .navigationTitleHidden(visit.dishName)
        .alert("Delete Visit?", isPresented: $isConfirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                appState.deleteVisit(visit)
                dismiss()
            }
        } message: {
            Text("This will remove the visit from your history and passport.")
        }
    }

    private var restaurantCard: some View {
        HStack(spacing: 14) {
            Map(
                initialPosition: .region(
                    MKCoordinateRegion(center: visit.restaurant.coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
                ),
                interactionModes: []
            ) {
                Marker(visit.restaurant.name, systemImage: "fork.knife", coordinate: visit.restaurant.coordinate)
                    .tint(Theme.orange)
                    .annotationTitles(.hidden)
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(visit.restaurant.name)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.ink)

                if visit.isLocationVerified {
                    PillLabel(text: "Location verified", trailingSystemImage: "checkmark", style: .green)
                } else {
                    PillLabel(text: "Not verified", systemImage: "location.slash")
                }
            }

            Spacer(minLength: 0)
        }
        .cardStyle()
    }

    private var amountCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                SectionCaption("Amount spent")
                Text(visit.amount.lkr)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }

            Spacer()

            if visit.isFromReceipt {
                HStack(spacing: 8) {
                    ReceiptThumbnail()
                    Text("From receipt")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .cardStyle()
    }
}

// MARK: - ReceiptThumbnail

/// Tiny receipt illustration next to "From receipt".
private struct ReceiptThumbnail: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<5, id: \.self) { line in
                Capsule()
                    .fill(Color(hex: 0xC9C9CE))
                    .frame(width: line == 4 ? 16 : 26, height: 3)
            }
        }
        .padding(7)
        .frame(width: 42, height: 54, alignment: .top)
        .background(Color(hex: 0xFAFAF7), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0xE2E2E6)))
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview {
    HistoryView()
        .previewInNavigationStack()
}

#Preview {
    VisitDetailView(visit: MockData.visits[0])
        .previewInNavigationStack()
}
