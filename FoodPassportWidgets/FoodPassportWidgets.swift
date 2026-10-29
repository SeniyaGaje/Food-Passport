import SwiftUI
import WidgetKit
import AppIntents

struct PassportEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct PassportProvider: TimelineProvider {
    func placeholder(in context: Context) -> PassportEntry {
        PassportEntry(date: .now, snapshot: .sample)
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

extension WidgetSnapshot {
    /// What the widget gallery shows before the app has saved anything.
    static var sample: WidgetSnapshot {
        var sample = WidgetSnapshot(isSignedIn: true, questTitle: "Try 3 new cuisines", cuisinesTried: 2, targetCuisines: 3,
            questEndsAt: Calendar.current.date(byAdding: .day, value: 9, to: .now), monthlyBudget: 10000, monthlySpent: 3200,
            budgetMonth: WidgetSnapshot.monthKey(for: .now))
        sample.questBudgetLeft = 800
        sample.nextPickName = "Dragon Wok"
        sample.nextPickCost = 750
        sample.challengeTitle = "Try 3 cuisines this week"
        sample.challengeCompleted = 1
        sample.challengeTarget = 3
        sample.challengeEndsAt = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.end
        return sample
    }
}

/// The widgets' colours and small pieces, so the three widgets look like one set.
private enum WidgetStyle {
    static let orange = Color(red: 0.95, green: 0.42, blue: 0.11)
    /// Darker orange for small text on the light background (and lighter in dark mode).
    static let orangeText = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 1, green: 0.54, blue: 0.24, alpha: 1)
        : UIColor(red: 0.76, green: 0.25, blue: 0.05, alpha: 1) })
    static let green = Color(red: 0.12, green: 0.62, blue: 0.34)

    static func lkr(_ amount: Int) -> String { "LKR \(amount.formatted())" }
}

/// The widget background: a soft orange wash, or nothing on the Lock Screen.
private struct WidgetBackground: View {
    var body: some View {
        LinearGradient(colors: [WidgetStyle.orange.opacity(0.16), WidgetStyle.orange.opacity(0.04)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct BrandHeader: View {
    var title = "FoodPassport"
    var systemImage = "globe.asia.australia.fill"

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(WidgetStyle.orangeText)
            .lineLimit(1)
    }
}

/// A rounded bar, drawn by hand so it looks the same on every Home Screen and Lock Screen.
private struct WidgetProgressBar: View {
    let value: Double
    var tint: Color = WidgetStyle.orange

    var body: some View {
        GeometryReader { space in
            Capsule()
                .fill(tint.opacity(0.22))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(6, space.size.width * min(max(value, 0), 1)))
                        .widgetAccentable()
                }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// Opens Log your visit. On the Home Screen this runs the App Intent; elsewhere the widget's link is used.
private struct LogVisitButton: View {
    var compact = false

    var body: some View {
        Button(intent: LogVisitIntent()) {
            Label(compact ? "Log" : "Log visit", systemImage: "plus.circle.fill")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: compact ? nil : .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(WidgetStyle.orange)
        .accessibilityLabel("Log a visit")
    }
}

/// Shown when no one is signed in or the app is locked with Face ID.
private struct SignedOutView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BrandHeader()
            Spacer(minLength: 0)
            Image(systemName: "lock.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Open your passport")
                .font(.headline)
                .minimumScaleFactor(0.8)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// Quest widget

struct QuestWidgetView: View {
    let entry: PassportEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        content
            .privacySensitive()
            .containerBackground(for: .widget) { WidgetBackground() }
            .widgetURL(URL(string: "foodpassport://quest"))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            if snapshot.isSignedIn, snapshot.questTitle != nil {
                Label("Quest \(snapshot.cuisinesTried)/\(snapshot.targetCuisines)", systemImage: "flag.checkered")
            } else {
                Label("FoodPassport", systemImage: "globe.asia.australia.fill")
            }
        case .accessoryCircular:
            Gauge(value: snapshot.isSignedIn ? snapshot.questFraction : 0) {
                Image(systemName: "flag.checkered")
            } currentValueLabel: {
                Text(snapshot.isSignedIn ? "\(snapshot.cuisinesTried)/\(snapshot.targetCuisines)" : "–")
            }
            .gaugeStyle(.accessoryCircular)
            .accessibilityLabel("Quest progress")
            .accessibilityValue("\(snapshot.cuisinesTried) of \(snapshot.targetCuisines) \(snapshot.questUnit)")
        case .accessoryRectangular:
            accessoryRectangular
        default:
            if !snapshot.isSignedIn {
                SignedOutView(message: "Sign in to see your quest.")
            } else if let title = snapshot.questTitle {
                switch family {
                case .systemSmall: small(title: title)
                case .systemMedium: medium(title: title)
                case .systemExtraLarge: extraLarge(title: title)
                default: large(title: title)
                }
            } else {
                noQuest
            }
        }
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.questTitle ?? "No active quest")
                .font(.headline)
                .widgetAccentable()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if snapshot.isSignedIn, snapshot.questTitle != nil {
                Text("\(snapshot.cuisinesTried) of \(snapshot.targetCuisines) \(snapshot.questUnit)")
                    .font(.caption)
                    .lineLimit(1)
                if let left = snapshot.questBudgetLeft {
                    Text("\(WidgetStyle.lkr(left)) left")
                        .font(.caption)
                        .lineLimit(1)
                }
            } else {
                Text(snapshot.isSignedIn ? "Start one in Passport" : "Sign in to see it")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func small(title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            BrandHeader(title: "Quest", systemImage: "flag.checkered")
            Text(title)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            progress
            if let left = snapshot.questBudgetLeft {
                Text("\(WidgetStyle.lkr(left)) left")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(title: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                BrandHeader(title: "Quest", systemImage: "flag.checkered")
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                progress
                budgetLeft
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                nextPick
                Spacer(minLength: 0)
                LogVisitButton()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func large(title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            BrandHeader()
            Text(title)
                .font(.title3.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            progress
            HStack(alignment: .top) {
                budgetLeft
                Spacer(minLength: 8)
                endsIn
            }
            Divider()
            nextPick
            Divider()
            ChallengeSummary(snapshot: snapshot)
            Spacer(minLength: 0)
            LogVisitButton()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The iPad's extra large widget: the quest on the left, this month and the challenge on the right.
    private func extraLarge(title: String) -> some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                BrandHeader()
                Text(title)
                    .font(.title2.bold())
                    .lineLimit(2)
                progress
                HStack(alignment: .top) {
                    budgetLeft
                    Spacer(minLength: 8)
                    endsIn
                }
                Divider()
                nextPick
                Spacer(minLength: 0)
                LogVisitButton()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 12) {
                MonthlyBudgetSummary(snapshot: snapshot)
                Divider()
                ChallengeSummary(snapshot: snapshot)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var noQuest: some View {
        VStack(alignment: .leading, spacing: 6) {
            BrandHeader()
            Spacer(minLength: 0)
            Text("Start a new quest")
                .font(.headline)
            Text("Choose a goal in Passport.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if family != .systemSmall {
                LogVisitButton()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetProgressBar(value: snapshot.questFraction)
            Text("\(snapshot.cuisinesTried) of \(snapshot.targetCuisines) \(snapshot.questUnit)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var budgetLeft: some View {
        if let left = snapshot.questBudgetLeft {
            VStack(alignment: .leading, spacing: 1) {
                Text(WidgetStyle.lkr(left))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                Text("quest budget left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var endsIn: some View {
        if let end = snapshot.questEndsAt {
            VStack(alignment: .trailing, spacing: 1) {
                Text(end, style: .relative)
                    .font(.subheadline.weight(.bold))
                    .multilineTextAlignment(.trailing)
                Text("left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var nextPick: some View {
        if let name = snapshot.nextPickName {
            VStack(alignment: .leading, spacing: 2) {
                Text("Next pick")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let cost = snapshot.nextPickCost {
                    Text("About \(WidgetStyle.lkr(cost))")
                        .font(.caption)
                        .foregroundStyle(WidgetStyle.orangeText)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("No place fits what's left. Open the quest to adjust it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }
}

/// This month's food budget: spent, left and a bar.
private struct MonthlyBudgetSummary: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This month")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text("\(WidgetStyle.lkr(snapshot.remainingBudget)) left")
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            WidgetProgressBar(value: snapshot.budgetFraction)
            Text("\(WidgetStyle.lkr(snapshot.monthlySpent)) of \(WidgetStyle.lkr(snapshot.monthlyBudget)) spent")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// This week's challenge: title, progress and days left.
private struct ChallengeSummary: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Weekly challenge")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(snapshot.challengeTitle ?? "Try 3 cuisines this week")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            WidgetProgressBar(value: snapshot.challengeFraction, tint: WidgetStyle.green)
            Text("\(snapshot.challengeCompleted ?? 0) of \(snapshot.challengeTarget ?? 3) done")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// Budget widget

struct BudgetWidgetView: View {
    let entry: PassportEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var percent: Int { Int(snapshot.budgetFraction * 100) }

    var body: some View {
        content
            .privacySensitive()
            .containerBackground(for: .widget) { WidgetBackground() }
            .widgetURL(URL(string: "foodpassport://budget"))
    }

    @ViewBuilder
    private var content: some View {
        if !snapshot.isSignedIn {
            switch family {
            case .accessoryCircular, .accessoryInline:
                Image(systemName: "lock.fill").accessibilityLabel("Sign in to see your budget")
            case .accessoryRectangular:
                Text("Sign in to see your budget").font(.caption)
            default:
                SignedOutView(message: "Sign in to see your budget.")
            }
        } else {
            switch family {
            case .accessoryInline:
                Label("\(WidgetStyle.lkr(snapshot.remainingBudget)) left", systemImage: "banknote")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Food budget")
                        .font(.headline)
                        .widgetAccentable()
                    WidgetProgressBar(value: snapshot.budgetFraction, tint: .primary)
                    Text("\(WidgetStyle.lkr(snapshot.remainingBudget)) left")
                        .font(.caption)
                }
                .accessibilityElement(children: .combine)
            case .accessoryCircular:
                Gauge(value: snapshot.budgetFraction) {
                    Image(systemName: "banknote")
                } currentValueLabel: {
                    Text("\(percent)%")
                }
                .gaugeStyle(.accessoryCircular)
                .accessibilityLabel("Monthly food budget")
                .accessibilityValue("\(percent) percent spent, \(WidgetStyle.lkr(snapshot.remainingBudget)) remaining")
            case .systemMedium:
                HStack(spacing: 16) {
                    ring
                    VStack(alignment: .leading, spacing: 8) {
                        MonthlyBudgetSummary(snapshot: snapshot)
                        Spacer(minLength: 0)
                        LogVisitButton()
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    BrandHeader(title: "Budget", systemImage: "banknote")
                    Spacer(minLength: 0)
                    Text(WidgetStyle.lkr(snapshot.remainingBudget))
                        .font(.title3.bold())
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("left this month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    WidgetProgressBar(value: snapshot.budgetFraction)
                    Text("\(percent)% of \(WidgetStyle.lkr(snapshot.monthlyBudget))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(WidgetStyle.orange.opacity(0.2), lineWidth: 10)
            Circle()
                .trim(from: 0, to: snapshot.budgetFraction)
                .stroke(WidgetStyle.orange, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(percent)%")
                    .font(.headline)
                    .monospacedDigit()
                Text("spent")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// Weekly challenge widget

struct ChallengeWidgetView: View {
    let entry: PassportEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        content
            .privacySensitive()
            .containerBackground(for: .widget) { WidgetBackground() }
            .widgetURL(URL(string: "foodpassport://challenge"))
    }

    @ViewBuilder
    private var content: some View {
        let completed = snapshot.challengeCompleted ?? 0
        let target = snapshot.challengeTarget ?? 3
        switch family {
        case .accessoryCircular:
            Gauge(value: snapshot.isSignedIn ? snapshot.challengeFraction : 0) {
                Image(systemName: "trophy")
            } currentValueLabel: {
                Text(snapshot.isSignedIn ? "\(completed)/\(target)" : "–")
            }
            .gaugeStyle(.accessoryCircular)
            .accessibilityLabel("Weekly challenge")
            .accessibilityValue("\(completed) of \(target) done")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly challenge")
                    .font(.headline)
                    .widgetAccentable()
                Text(snapshot.isSignedIn ? "\(completed) of \(target) done" : "Sign in to see it")
                    .font(.caption)
                if snapshot.isSignedIn, let end = snapshot.challengeEndsAt {
                    Text("Ends \(end, format: .relative(presentation: .named))")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            if !snapshot.isSignedIn {
                SignedOutView(message: "Sign in to see this week's challenge.")
            } else {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        BrandHeader(title: "This week", systemImage: "trophy.fill")
                        Text(snapshot.challengeTitle ?? "Try 3 cuisines this week")
                            .font(.headline)
                            .lineLimit(family == .systemSmall ? 3 : 2)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        WidgetProgressBar(value: snapshot.challengeFraction, tint: WidgetStyle.green)
                        Text("\(completed) of \(target) done")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)

                    if family == .systemMedium {
                        VStack(alignment: .leading, spacing: 8) {
                            if let end = snapshot.challengeEndsAt {
                                Text("Ends \(end, format: .relative(presentation: .named))")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                            }
                            Text(completed >= target ? "Challenge complete!" : "\(max(0, target - completed)) more to go")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            LogVisitButton()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

// The widgets

struct QuestWidget: Widget {
    let kind = "FoodPassportQuest"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PassportProvider()) { QuestWidgetView(entry: $0) }
            .configurationDisplayName("My food quest")
            .description("Your quest progress, budget left and next pick.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
                                .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct BudgetWidget: Widget {
    let kind = "FoodPassportBudget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PassportProvider()) { BudgetWidgetView(entry: $0) }
            .configurationDisplayName("Food budget")
            .description("How much of this month's food budget you have left.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct ChallengeWidget: Widget {
    let kind = "FoodPassportChallenge"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PassportProvider()) { ChallengeWidgetView(entry: $0) }
            .configurationDisplayName("Weekly challenge")
            .description("This week's challenge and how close you are.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct FoodPassportWidgets: WidgetBundle {
    var body: some Widget {
        QuestWidget()
        BudgetWidget()
        ChallengeWidget()
    }
}

// Previews

#Preview("Quest small", as: .systemSmall) {
    QuestWidget()
} timeline: {
    PassportEntry(date: .now, snapshot: .sample)
}

#Preview("Quest medium", as: .systemMedium) {
    QuestWidget()
} timeline: {
    PassportEntry(date: .now, snapshot: .sample)
}

#Preview("Quest large", as: .systemLarge) {
    QuestWidget()
} timeline: {
    PassportEntry(date: .now, snapshot: .sample)
}

#Preview("Budget medium", as: .systemMedium) {
    BudgetWidget()
} timeline: {
    PassportEntry(date: .now, snapshot: .sample)
}

#Preview("Challenge small", as: .systemSmall) {
    ChallengeWidget()
} timeline: {
    PassportEntry(date: .now, snapshot: .sample)
}
