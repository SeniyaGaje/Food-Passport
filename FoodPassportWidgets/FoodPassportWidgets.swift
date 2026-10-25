import SwiftUI
import WidgetKit

struct PassportEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct PassportProvider: TimelineProvider {
    func placeholder(in context: Context) -> PassportEntry {
        PassportEntry(date: .now, snapshot: WidgetSnapshot(isSignedIn: true, questTitle: "Explore new cuisines",
            cuisinesTried: 1, targetCuisines: 3, monthlyBudget: 10000, monthlySpent: 2500,
            budgetMonth: WidgetSnapshot.monthKey(for: .now)))
    }

    func getSnapshot(in context: Context, completion: @escaping (PassportEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : PassportEntry(date: .now, snapshot: WidgetSnapshotStore().read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PassportEntry>) -> Void) {
        let now = Date.now
        let store = WidgetSnapshotStore()
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(24 * 60 * 60)
        let nextRefresh = min(now.addingTimeInterval(30 * 60), nextDay)
        let entry = PassportEntry(date: now, snapshot: store.read(at: now))
        let rollover = PassportEntry(date: nextDay, snapshot: store.read(at: nextDay))
        completion(Timeline(entries: [entry, rollover], policy: .after(nextRefresh)))
    }
}

struct QuestWidgetView: View {
    let entry: PassportEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("FoodPassport", systemImage: "globe.asia.australia.fill")
                .font(.caption.bold()).foregroundStyle(.orange)
            if !entry.snapshot.isSignedIn {
                Text("Open your passport").font(.headline)
                Text("Sign in to see your quest.").font(.caption)
            } else if let title = entry.snapshot.questTitle {
                Text(title).font(.headline).lineLimit(2)
                ProgressView(value: Double(entry.snapshot.cuisinesTried), total: Double(max(1, entry.snapshot.targetCuisines)))
                    .tint(.orange)
                Text("\(entry.snapshot.cuisinesTried) of \(entry.snapshot.targetCuisines) \(entry.snapshot.questUnit)").font(.caption)
                if family == .systemMedium {
                    Text("Open Passport to plan your next meal.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Start a new quest").font(.headline)
                Text("Choose a goal in Passport.").font(.caption)
            }
        }
        .privacySensitive()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.orange.opacity(0.08) }
        .widgetURL(URL(string: "foodpassport://quest"))
    }
}

struct BudgetWidgetView: View {
    let entry: PassportEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if !entry.snapshot.isSignedIn {
                Image(systemName: "lock.fill").accessibilityLabel("Sign in to see your budget")
            } else if family == .accessoryRectangular {
                VStack(alignment: .leading) {
                    Text("Monthly food budget").font(.caption.bold())
                    ProgressView(value: entry.snapshot.budgetFraction)
                    Text("LKR \(entry.snapshot.remainingBudget) left").font(.caption)
                }
            } else {
                Gauge(value: entry.snapshot.budgetFraction) {
                    Image(systemName: "banknote")
                } currentValueLabel: {
                    Text("\(Int(entry.snapshot.budgetFraction * 100))%")
                }
                .gaugeStyle(.accessoryCircular)
                .accessibilityLabel("Monthly food budget")
                .accessibilityValue("\(Int(entry.snapshot.budgetFraction * 100)) percent spent, LKR \(entry.snapshot.remainingBudget) remaining")
            }
        }
        .privacySensitive()
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "foodpassport://budget"))
    }
}

struct QuestWidget: Widget {
    let kind = "FoodPassportQuest"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PassportProvider()) { QuestWidgetView(entry: $0) }
            .configurationDisplayName("My food quest")
            .description("Your current cuisine quest and progress.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BudgetWidget: Widget {
    let kind = "FoodPassportBudget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PassportProvider()) { BudgetWidgetView(entry: $0) }
            .configurationDisplayName("Food budget")
            .description("How much of this month's food budget you have spent.")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

@main
struct FoodPassportWidgets: WidgetBundle {
    var body: some Widget {
        QuestWidget()
        BudgetWidget()
    }
}
