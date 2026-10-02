import SwiftUI
import UIKit

// MARK: - ScreenHeader

/// Large bold title (with optional subtitle) and trailing controls, used at the top of each tab.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityAddTraits(.isHeader)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            trailing
        }
    }
}

// MARK: - ScreenHeader

extension ScreenHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - AppLogo

struct AppLogo: View {
    var size: CGFloat = 80
    var cornerRadius: CGFloat?

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.27, style: .continuous)
            .fill(Theme.primaryGradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "menucard")
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - InitialsAvatar

struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 44
    var background: Color = Theme.ink

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(background, in: Circle())
    }
}

// MARK: - FilterChip

/// Capsule filter button, e.g. the cuisine filters on Explore and period filters on History.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var selectedColor: Color = Theme.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(isSelected ? selectedColor : .white, in: Capsule())
                .shadow(color: .black.opacity(isSelected ? 0 : 0.05), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - SearchField

struct SearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

// MARK: - StatTile

/// Big number with a label underneath, e.g. "3 Visits".
struct StatTile: View {
    let value: String
    let label: String
    var valueColor: Color = Theme.ink

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(valueColor)
                .contentTransition(.numericText())

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ProgressBar

struct ProgressBar: View {
    let value: Double
    var tint: Color = Theme.ink
    var track: Color = Color(hex: 0xECECEE)
    var height: CGFloat = 10

    private var clampedValue: Double {
        min(max(value, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(tint)
                    .frame(width: proxy.size.width * clampedValue)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "\(Int(clampedValue * 100))%"))
    }
}

// MARK: - RingProgress

/// Circular progress ring, e.g. "2/3 cuisines tried" on Quest Detail.
struct RingProgress: View {
    let value: Double
    var lineWidth: CGFloat = 20
    var tint: Color = Theme.ink
    var track: Color = Color(hex: 0xF0F0F2)

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}

// MARK: - StarRatingView

struct StarRatingView: View {
    @Binding private var rating: Int
    private let size: CGFloat
    private let filledColor: Color
    private let isEditable: Bool

    /// Editable rating, used in the Log a Visit form.
    init(rating: Binding<Int>, size: CGFloat = 28, filledColor: Color = Theme.gold) {
        _rating = rating
        self.size = size
        self.filledColor = filledColor
        isEditable = true
    }

    /// Read-only rating, used in lists and detail screens.
    init(rating: Int, size: CGFloat = 28, filledColor: Color = Theme.gold) {
        _rating = .constant(rating)
        self.size = size
        self.filledColor = filledColor
        isEditable = false
    }

    var body: some View {
        HStack(spacing: size * 0.35) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(index <= rating ? filledColor : Color(.systemGray4))
                    .onTapGesture {
                        if isEditable { rating = index }
                    }
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue("\(rating) of 5 stars")
        .accessibilityAdjustableAction { direction in
            guard isEditable else { return }
            switch direction {
            case .increment: rating = min(rating + 1, 5)
            case .decrement: rating = max(rating - 1, 0)
            @unknown default: break
            }
        }
    }
}

// MARK: - PillLabel

/// Small capsule tag, e.g. "Location verified ✓", "Auto-detected" or a cuisine name.
struct PillLabel: View {
    enum Style {
        case gray
        case green
        case orange
        case yellow

        var foreground: Color {
            switch self {
            case .gray: Color(hex: 0x55555A)
            case .green: Theme.green
            case .orange: Theme.orange
            case .yellow: Color(hex: 0xE39500)
            }
        }

        var background: Color {
            switch self {
            case .gray: Color(hex: 0xEDEDEF)
            case .green: Theme.greenTint
            case .orange: Theme.orangeTint
            case .yellow: Theme.yellowTint
            }
        }
    }

    let text: String
    var systemImage: String?
    var trailingSystemImage: String?
    var style: Style = .gray
    var font: Font = .footnote.weight(.semibold)

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .font(.caption2.weight(.bold))
            }
        }
        .font(font)
        .foregroundStyle(style.foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(style.background, in: Capsule())
    }
}

// MARK: - SectionCaption

/// Small uppercase grey label above a field or inside a card, e.g. "DISH" or "WEEKLY SPENDING".
struct SectionCaption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .kerning(0.3)
    }
}

// MARK: - InputField

/// Rounded white text field from the prototype forms.
struct InputField: View {
    let placeholder: String
    @Binding var text: String
    var prefix: String?
    var isMultiline = false

    var body: some View {
        HStack(spacing: 8) {
            if let prefix {
                Text(prefix)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.ink)
            }

            if isMultiline {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(3...6)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(minHeight: 54)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

// MARK: - SecureInputField

/// Password field with a show/hide toggle.
struct SecureInputField: View {
    let placeholder: String
    @Binding var text: String
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

// MARK: - CurrencyField

/// Large amount field with a currency prefix, used for budgets.
struct CurrencyField: View {
    @Binding var amount: Int
    var currencyCode = "LKR"
    var background: Color = .white

    var body: some View {
        HStack(spacing: 8) {
            Text(currencyCode)
            TextField("Amount", value: $amount, format: .number)
                .keyboardType(.numberPad)
        }
        .font(.title3.bold())
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: - AmountPresetPicker

/// Row of preset amounts, e.g. LKR 3,000 / 5,000 / 8,000.
struct AmountPresetPicker: View {
    let presets: [Int]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(presets, id: \.self) { amount in
                let isSelected = amount == selection
                Button {
                    selection = amount
                } label: {
                    Text(amount.lkr)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(isSelected ? .white : Theme.ink)
                        .background(isSelected ? Theme.ink : .white, in: Capsule())
                        .overlay(Capsule().stroke(Theme.ink, lineWidth: isSelected ? 0 : 1.2))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

// MARK: - CountStepper

/// − value + control from the quest editor.
struct CountStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 14) {
            stepButton(systemImage: "minus", isEnabled: value > range.lowerBound) { value -= 1 }

            Text("\(value)")
                .font(.title3.bold())
                .monospacedDigit()
                .frame(minWidth: 24)

            stepButton(systemImage: "plus", isEnabled: value < range.upperBound) { value += 1 }
        }
        .padding(5)
        .background(Theme.fieldGray, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 1, range.upperBound)
            case .decrement: value = max(value - 1, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private func stepButton(systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .frame(width: 38, height: 38)
                .background(.white, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

// MARK: - SheetHeader

/// "Cancel · Title · Action" bar at the top of bottom sheets.
struct SheetHeader: View {
    let title: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)

            HStack {
                Button("Cancel", action: onCancel)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(confirmTitle, action: onConfirm)
                    .font(.headline)
                    .foregroundStyle(Theme.orange)
            }
        }
    }
}

// MARK: - PopupCard

/// White rounded card used for centred pop-ups such as "New stamp earned!".
struct PopupCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 16) {
            content
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 30, y: 12)
    }
}

// MARK: - PopupIcon

/// Round tinted icon at the top of a pop-up.
struct PopupIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.title.weight(.semibold))
            .foregroundStyle(Theme.orange)
            .frame(width: 76, height: 76)
            .background(Theme.orangeTint, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - ToastView

/// Dark confirmation message, e.g. "Visit logged! You earned a Sri Lankan stamp ✓".
struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color(hex: 0x3A3A3C).opacity(0.95), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
    }
}

// MARK: - NotificationBannerView

/// Looks like an iOS notification; used in-app to preview notifications such as the arrival alert.
struct NotificationBannerView: View {
    let title: String
    let message: String
    var timestamp = "now"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                AppLogo(size: 38, cornerRadius: 9)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("FoodPassport")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(timestamp)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Log a Visit")
    }
}

// MARK: - FoodImageView

/// Shows a photo from the asset catalog when one exists, otherwise a cuisine-coloured placeholder.
/// To use real photos, add images to Assets.xcassets with the same names as in MockData
/// (e.g. "restaurant_campus_bites", "dish_kottu", "welcome_hero").
struct FoodImageView: View {
    let imageName: String?
    var cuisine: Cuisine?
    var cornerRadius: CGFloat = 0

    var body: some View {
        Color.clear
            .overlay {
                if let imageName, UIImage(named: imageName) != nil {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                LinearGradient(
                    colors: (cuisine ?? .sriLankan).placeholderColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if side > 180 {
                    FoodSymbolPattern(size: proxy.size)
                } else {
                    Image(systemName: cuisine?.symbolName ?? "fork.knife")
                        .font(.system(size: side * 0.36, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
    }
}

// MARK: - FoodSymbolPattern

/// Tiled food icons used to fill large placeholders such as the welcome hero.
private struct FoodSymbolPattern: View {
    let size: CGSize

    private let symbols = [
        "fork.knife", "cup.and.saucer.fill", "carrot.fill", "fish.fill",
        "takeoutbag.and.cup.and.straw.fill", "birthday.cake.fill", "leaf.fill", "flame.fill",
    ]
    private let spacing: CGFloat = 64

    var body: some View {
        let columns = Int(size.width / spacing) + 2
        let rows = Int(size.height / spacing) + 2

        VStack(spacing: spacing * 0.4) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: spacing * 0.4) {
                    ForEach(0..<columns, id: \.self) { column in
                        Image(systemName: symbols[(row * 3 + column) % symbols.count])
                            .font(.system(size: 30, weight: .medium))
                            .frame(width: spacing * 0.6, height: spacing * 0.6)
                    }
                }
                .offset(x: row.isMultiple(of: 2) ? 0 : spacing * 0.5)
            }
        }
        .foregroundStyle(.white.opacity(0.22))
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

// MARK: - StampBadgeView

/// A passport stamp. Pass `nil` for an empty "?" slot that hasn't been earned yet.
struct StampBadgeView: View {
    let cuisine: Cuisine?
    var size: CGFloat = 84
    var showsCheckmark = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let cuisine {
                Circle()
                    .fill(Theme.orangeTint)
                    .overlay(Circle().strokeBorder(Theme.orange, lineWidth: 3))
                    .overlay {
                        Image(systemName: cuisine.symbolName)
                            .font(.system(size: size * 0.32, weight: .semibold))
                            .foregroundStyle(Theme.orange)
                    }
            } else {
                Circle()
                    .strokeBorder(Color(.systemGray4), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .overlay {
                        Text("?")
                            .font(.system(size: size * 0.28, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            }

            if showsCheckmark {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Theme.green)
                    .font(.system(size: size * 0.3))
                    .background(Circle().fill(.white))
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - VisitRow

/// A logged visit as shown in History and Recent activity.
struct VisitRow: View {
    let visit: Visit

    var body: some View {
        HStack(spacing: 14) {
            FoodImageView(imageName: visit.imageName, cuisine: visit.cuisine, cornerRadius: 14)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(visit.dishName)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)

                Text(visit.restaurant.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    StarRatingView(rating: visit.rating, size: 12, filledColor: Theme.ink)

                    if visit.isLocationVerified {
                        PillLabel(text: "Verified", systemImage: "checkmark", font: .caption2.weight(.semibold))
                            .fixedSize()
                    }
                }
            }

            Spacer(minLength: 8)

            Text(visit.amount.lkr)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .fixedSize()
        }
        .cardStyle(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - RestaurantPin

/// Fork-and-knife pin for a restaurant on the map; orange and larger when selected.
struct RestaurantPin: View {
    var isSelected = false

    private var color: Color {
        isSelected ? Theme.orange : Color(hex: 0x5A5A5E)
    }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "fork.knife")
                .font(.system(size: isSelected ? 18 : 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: isSelected ? 44 : 34, height: isSelected ? 44 : 34)
                .background(color, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)

            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
        .animation(.spring(duration: 0.25), value: isSelected)
    }
}

// MARK: - UserLocationDot

/// Blue dot for the student's current location.
struct UserLocationDot: View {
    var body: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .background {
                Circle()
                    .fill(Color.blue.opacity(0.18))
                    .frame(width: 44, height: 44)
            }
            .shadow(color: .black.opacity(0.2), radius: 2)
            .accessibilityLabel("Your location")
    }
}

// MARK: - NumberedMapMarker

/// Numbered stop marker on a food trail map.
struct NumberedMapMarker: View {
    let number: Int
    let status: TrailStopStatus

    var body: some View {
        ZStack {
            Circle()
                .fill(fillColor)
            if status == .visited {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.bold))
            } else {
                Text("\(number)")
                    .font(.headline)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 36, height: 36)
        .overlay(Circle().stroke(.white, lineWidth: 3))
        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }

    private var fillColor: Color {
        switch status {
        case .visited: Theme.green
        case .next: Theme.orange
        case .upcoming: Color(hex: 0x6B6B70)
        }
    }
}

// MARK: - ProfileAvatarButton

/// The "JD" avatar in screen headers; tapping it opens the Profile tab.
struct ProfileAvatarButton: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.selectedTab = .profile
        } label: {
            InitialsAvatar(initials: appState.profile.initials)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile")
    }
}

// MARK: - BookmarkButton

struct BookmarkButton: View {
    let isBookmarked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                .font(.title3)
                .foregroundStyle(isBookmarked ? Theme.orange : Color.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isBookmarked)
        .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark")
    }
}
