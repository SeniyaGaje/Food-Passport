import SwiftUI

/// The "New stamp earned!" pop-up.
struct StampEarnedPopup: View {
    let cuisine: Cuisine
    /// nil if there's no quest running, so there's no progress to show.
    let quest: Quest?
    let onViewPassport: () -> Void
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Starts the stamping animation when the pop-up appears.
    @State private var isStamped = false

    var body: some View {
        PopupCard {
            ZStack {
                Circle()
                    .strokeBorder(Theme.orange, style: StrokeStyle(lineWidth: 3, dash: [7, 5]))
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(isStamped ? 0 : -40))

                Circle()
                    .fill(Theme.primaryGradient)
                    .frame(width: 122, height: 122)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: cuisine.symbolName)
                                .font(.title.weight(.bold))
                                .symbolEffect(.bounce, value: reduceMotion ? false : isStamped)
                            Text(cuisine.rawValue.uppercased())
                                .font(.caption.weight(.heavy))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .padding(10)
                        // It's artwork with a fixed size, so its text stops growing at large sizes.
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    }
                    .shadow(color: Theme.orange.opacity(0.4), radius: 12, y: 6)
            }
            .rotationEffect(.degrees(cuisine.stampTilt))
            .scaleEffect(isStamped || reduceMotion ? 1 : 1.35)
            .opacity(isStamped || reduceMotion ? 1 : 0)
            .onAppear {
                // With Reduce Motion on, the stamp just appears instead of spinning and bouncing in.
                if reduceMotion {
                    isStamped = true
                } else {
                    withAnimation(.spring(duration: 0.5, bounce: 0.45).delay(0.1)) {
                        isStamped = true
                    }
                }
            }
            .sensoryFeedback(.success, trigger: isStamped)
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("New stamp earned!")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)
                if let quest {
                    Text("Quest progress: \(quest.cuisinesTried) of \(quest.targetCuisines) \(quest.progressUnit)")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Your \(cuisine.rawValue) stamp is in your passport.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }

            if let quest {
                ProgressBar(value: quest.cuisineProgress, tint: Theme.orange, label: "Quest progress")
                    .frame(maxWidth: 200)
            }

            VStack(spacing: 10) {
                Button("View passport", action: onViewPassport)
                    .buttonStyle(.brandPrimary)
                Button("Done", action: onDone)
                    .buttonStyle(.brandTinted)
            }
            .padding(.top, 4)
        }
    }
}

// Previews

#Preview {
    StampEarnedPopup(cuisine: .sriLankan, quest: MockData.activeQuest, onViewPassport: {}, onDone: {})
        .padding()
        .background(Color.black.opacity(0.4))
}
