import SwiftUI
import MapKit

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
                        FilterChip(title: option.rawValue, isSelected: option == filter, selectedColor: Theme.orange, selectedForeground: .white) {
                            filter = option
                        }
                    }
                }

                content
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .appBackground()
        .navigationTitle("History")
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: filter)
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
                HStack(alignment: .firstTextBaseline) {
                    SectionCaption(section.group.title)
                    Spacer()
                    Text(section.visits.map(\.amount).reduce(0, +).lkr)
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Spent \(section.visits.map(\.amount).reduce(0, +).lkr)")
                }
                .padding(.top, 8)

                ForEach(section.visits) { visit in
                    NavigationLink(value: AppRoute.visitDetail(visit)) {
                        VisitRow(visit: visit)
                    }
                    .buttonStyle(.pressableCard)
                }
            }
        }
    }
}

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

/// "No visits yet" state shown when the student hasn't logged anything.
private struct EmptyHistoryView: View {
    let onExplore: () -> Void

    var body: some View {
        EmptyStateView(
            systemImage: "fork.knife",
            title: "No visits yet",
            message: "Start exploring and your visits will show up here.",
            actionTitle: "Explore places",
            action: onExplore
        )
        .padding(.top, 24)
    }
}

struct VisitDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false

    let visit: Visit

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero

                HStack(spacing: Theme.Spacing.xs) {
                    PillLabel(text: visit.cuisine.rawValue, systemImage: visit.cuisine.symbolName, style: .green)
                    if visit.isAutoDetected {
                        PillLabel(text: "Auto-detected", systemImage: "sparkles", style: .orange)
                    }
                }

                restaurantCard
                amountCard

                VStack(alignment: .leading, spacing: 10) {
                    SectionCaption("Rating")
                    StarRatingView(rating: visit.rating, size: 24)
                }
                .cardStyle(padding: 18)

                if !visit.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionCaption("Notes")
                        Text(visit.notes)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .cardStyle(padding: 18)
                }

                Label(visit.date.formatted(date: .complete, time: .shortened), systemImage: "calendar")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete visit", systemImage: "trash")
                }
                .buttonStyle(BrandTextButtonStyle(color: Theme.destructive))
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
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

    /// Meal photo with the dish name on a dark fade; same shape on every iPhone.
    private var hero: some View {
        FoodImageView(imageName: visit.imageName, cuisine: visit.cuisine)
            .aspectRatio(1.45, contentMode: .fit)
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    PhotoTag(text: visit.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)), systemImage: "calendar")
                    Text(visit.dishName)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
                .padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous))
            .shadow(color: Theme.shadow.opacity(0.14), radius: 18, y: 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(visit.dishName)
            .accessibilityAddTraits(.isHeader)
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
                    .font(.title.bold())
                    .monospacedDigit()
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

// Previews

#Preview {
    HistoryView()
        .previewInNavigationStack()
}

#Preview {
    VisitDetailView(visit: MockData.visits[0])
        .previewInNavigationStack()
}
