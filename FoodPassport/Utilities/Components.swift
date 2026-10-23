import SwiftUI
import UIKit

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

extension ScreenHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// Bold title above a group of cards, with an optional action on the right, e.g. "Recent activity · View history".
struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.orange)
            }
        }
        .padding(.top, 6)
    }
}

/// Rounded-square icon used by rows, cards and settings, so icons look the same on every screen.
/// `isFilled` draws a white symbol on a solid tint (settings rows); otherwise the symbol sits on a soft tint.
struct IconTile: View {
    let systemImage: String
    var tint: Color = Theme.orange
    var size: CGFloat = 48
    var isFilled = false

    /// Grows the tile a little with the student's text size, but not so much that rows break.
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let side = size * min(scale, 1.35)

        Image(systemName: systemImage)
            .font(.system(size: side * 0.42, weight: .semibold))
            .foregroundStyle(isFilled ? .white : tint)
            .frame(width: side, height: side)
            .background(
                isFilled ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.14)),
                in: RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// Friendly placeholder for a list with nothing in it yet, e.g. "No visits yet".
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.orange)
                .frame(width: 92, height: 92)
                .background(Theme.orangeTint, in: Circle())
                .overlay { Circle().strokeBorder(Theme.orange.opacity(0.2), lineWidth: 1) }
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.ink)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.brandPrimary)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .cardBackground()
    }
}

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
            .shadow(color: Theme.orange.opacity(0.3), radius: size * 0.14, y: size * 0.07)
            .accessibilityHidden(true)
    }
}

struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 44
    var background: Color = Theme.ink
    var foreground: Color = Theme.onInk

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(background, in: Circle())
    }
}

/// Capsule filter button, e.g. the cuisine filters on Explore and period filters on History.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var selectedColor: Color = Theme.ink
    /// Text colour on the selected fill; use `.white` when `selectedColor` is orange.
    var selectedForeground: Color = Theme.onInk
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? selectedForeground : Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background {
                    if isSelected {
                        Capsule().fill(selectedColor)
                    } else {
                        Color.clear.surfaceBackground(Capsule(), shadowStrength: 0.6)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

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
        .frame(minHeight: 48)
        .cardBackground(cornerRadius: 14, shadowStrength: 0.6)
    }
}

/// Big number with a label underneath, e.g. "3 Visits".
struct StatTile: View {
    let value: String
    let label: String
    var systemImage: String?
    var valueColor: Color = Theme.ink

    /// The number's size follows the student's text size setting (Dynamic Type).
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 30

    var body: some View {
        VStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.orange)
                    .padding(.bottom, 2)
            }

            Text(value)
                .font(.system(size: valueSize, weight: .bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 6)
        .cardBackground()
        .accessibilityElement(children: .combine)
    }
}

struct ProgressBar: View {
    let value: Double
    var tint: Color = Theme.ink
    var track: Color = Theme.track
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
        .animation(.spring(duration: 0.5), value: clampedValue)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "\(Int(clampedValue * 100))%"))
    }
}

/// Circular progress ring, e.g. "2/3 cuisines tried" on Quest Detail.
struct RingProgress: View {
    let value: Double
    var lineWidth: CGFloat = 20
    var tint: AnyShapeStyle = AnyShapeStyle(Theme.ink)
    var track: Color = Color(light: 0xF0F0F2, dark: 0x3A3532)

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .animation(.spring(duration: 0.6), value: value)
        .accessibilityHidden(true)
    }
}

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

/// Icon and text with a small gap and a muted icon, e.g. the price line on restaurant cards.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .foregroundStyle(.secondary)
                .imageScale(.small)
            configuration.title
        }
    }
}

/// Small capsule tag, e.g. "Location verified ✓", "Auto-detected" or a cuisine name.
struct PillLabel: View {
    enum Style {
        case gray
        case green
        case orange
        case yellow

        var foreground: Color {
            switch self {
            case .gray: Color(light: 0x55555A, dark: 0xC7C2BE)
            case .green: Theme.green
            case .orange: Theme.orange
            case .yellow: Color(hex: 0xE39500)
            }
        }

        var background: Color {
            switch self {
            case .gray: Theme.subtleFill
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

/// Small uppercase grey label above a field or inside a card, e.g. "DISH" or "WEEKLY SPENDING".
struct SectionCaption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .kerning(0.6)
    }
}

/// Field surface shared by the text inputs: card background plus an orange outline while typing.
private struct FieldBackground: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .cardBackground(cornerRadius: Theme.Radius.field, shadowStrength: 0.5)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
                    .strokeBorder(Theme.orange, lineWidth: isFocused ? 1.5 : 0)
            }
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

/// Rounded white text field from the prototype forms.
struct InputField: View {
    let placeholder: String
    @Binding var text: String
    var prefix: String?
    var isMultiline = false

    @FocusState private var isFocused: Bool

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
                    .focused($isFocused)
            } else {
                TextField(placeholder, text: $text)
                    .focused($isFocused)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(minHeight: 54)
        .modifier(FieldBackground(isFocused: isFocused))
    }
}

/// Password field with a show/hide toggle.
struct SecureInputField: View {
    let placeholder: String
    @Binding var text: String
    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .focused($isFocused)
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .frame(minHeight: 54)
        .modifier(FieldBackground(isFocused: isFocused))
    }
}

/// Large amount field with a currency prefix, used for budgets.
struct CurrencyField: View {
    @Binding var amount: Int
    var currencyCode = "LKR"
    var background: Color = Theme.surface

    var body: some View {
        HStack(spacing: 8) {
            Text(currencyCode)
            TextField("Amount", value: $amount, format: .number)
                .keyboardType(.numberPad)
        }
        .font(.title3.bold())
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 18)
        .frame(minHeight: 58)
        .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        }
    }
}

/// Row of preset amounts, e.g. LKR 3,000 / 5,000 / 8,000.
struct AmountPresetPicker: View {
    let presets: [Int]
    @Binding var selection: Int

    var body: some View {
        // One row when the amounts fit; one per line with large text sizes.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { presetButtons }
            VStack(spacing: 10) { presetButtons }
        }
    }

    private var presetButtons: some View {
        ForEach(presets, id: \.self) { amount in
            let isSelected = amount == selection
            Button {
                selection = amount
            } label: {
                Text(amount.lkr)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(isSelected ? Theme.onInk : Theme.ink)
                    .background(isSelected ? Theme.ink : Theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(Theme.ink, lineWidth: isSelected ? 0 : 1.2))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

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
                .background(Theme.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// "Cancel · Title · Action" bar at the top of bottom sheets.
struct SheetHeader: View {
    let title: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void
    var isConfirmEnabled = true

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
                    .foregroundStyle(isConfirmEnabled ? Theme.orange : .secondary)
                    .disabled(!isConfirmEnabled)
            }
        }
    }
}

/// Rounded card used for centred pop-ups such as "New stamp earned!".
struct PopupCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 16) {
            content
        }
        .padding(24)
        .frame(maxWidth: 360)
        .cardBackground(cornerRadius: Theme.Radius.sheet, shadowStrength: 3)
    }
}

/// Round tinted icon at the top of a pop-up.
struct PopupIcon: View {
    let systemImage: String

    /// Flipped once the pop-up appears, so the icon gives a single bounce to draw the eye.
    @State private var hasAppeared = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.title.weight(.semibold))
            .foregroundStyle(Theme.orange)
            .symbolEffect(.bounce, value: hasAppeared)
            .frame(width: 76, height: 76)
            .background(Theme.orangeTint, in: Circle())
            .overlay { Circle().strokeBorder(Theme.orange.opacity(0.2), lineWidth: 1) }
            .onAppear { hasAppeared = true }
            .accessibilityHidden(true)
    }
}

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

/// Looks like an iOS notification; used in-app to preview notifications such as the arrival alert.
struct NotificationBannerView: View {
    let title: String
    let message: String
    var timestamp = "now"
    var imageName: String?
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

                if let imageName {
                    FoodImageView(imageName: imageName, cornerRadius: 8)
                        .frame(width: 40, height: 40)
                        .padding(.top, 22)
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

/// The orange quest gradient with a large, faint globe in the corner, shared by the Home and Passport quest cards.
struct QuestCardBackground: View {
    var cornerRadius: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.questGradient)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "globe.asia.australia.fill")
                    .font(.system(size: 150))
                    .foregroundStyle(.white.opacity(0.1))
                    .rotationEffect(.degrees(-12))
                    .offset(x: 40, y: 40)
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Small frosted tag drawn on top of a photo, e.g. the cuisine on Place Detail.
struct PhotoTag: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.35), in: Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1) }
    }
}

/// A passport stamp. Pass `nil` for an empty "?" slot that hasn't been earned yet.
struct StampBadgeView: View {
    let cuisine: Cuisine?
    var size: CGFloat = 84
    var showsCheckmark = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let cuisine {
                // Looks like a rubber passport stamp: a solid ring, a dashed inner ring and a slight tilt.
                Circle()
                    .fill(Theme.orangeTint)
                    .overlay(Circle().strokeBorder(Theme.orange, lineWidth: max(2, size * 0.035)))
                    .overlay {
                        Circle()
                            .strokeBorder(
                                Theme.orange.opacity(0.55),
                                style: StrokeStyle(lineWidth: max(1, size * 0.016), dash: [size * 0.04, size * 0.03])
                            )
                            .padding(size * 0.1)
                    }
                    .overlay {
                        Image(systemName: cuisine.symbolName)
                            .font(.system(size: size * 0.32, weight: .semibold))
                            .foregroundStyle(Theme.orange)
                    }
                    .rotationEffect(.degrees(cuisine.stampTilt))
            } else {
                Circle()
                    .strokeBorder(Theme.faintInk, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
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
                    .background(Circle().fill(Theme.surface))
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A logged visit as shown in History and Recent activity.
struct VisitRow: View {
    let visit: Visit

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// With very large text there isn't room for the amount beside the dish, so it moves underneath.
    private var stacksAmount: Bool {
        dynamicTypeSize >= .xxxLarge
    }

    var body: some View {
        HStack(spacing: 14) {
            FoodImageView(imageName: visit.imageName, cuisine: visit.cuisine, cornerRadius: 14)
                .frame(width: 64, height: 64)

            // Only the amount keeps its full width; everything else can shrink,
            // so the row fits inside the margins on the narrowest iPhone.
            VStack(alignment: .leading, spacing: 4) {
                Text(visit.dishName)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text(visit.restaurant.name)
                        .lineLimit(1)
                    if visit.isLocationVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Theme.green)
                            .accessibilityLabel("Location verified")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                StarRatingView(rating: visit.rating, size: 12, filledColor: Theme.gold)

                if stacksAmount {
                    amountText
                }
            }

            Spacer(minLength: 8)

            if !stacksAmount {
                amountText
                    .fixedSize()
            }
        }
        .cardStyle(padding: 14)
        .accessibilityElement(children: .combine)
    }

    private var amountText: some View {
        Text(visit.amount.lkr)
            .font(.headline)
            .monospacedDigit()
            .foregroundStyle(Theme.ink)
    }
}

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

struct BookmarkButton: View {
    let isBookmarked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                .font(.title3)
                .foregroundStyle(isBookmarked ? Theme.orange : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: isBookmarked)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isBookmarked)
        .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark")
    }
}
