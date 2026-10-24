import SwiftUI
import Foundation
import MapKit

/// The app's colours and sizes, from the Figma prototype.
/// Each colour has a light and a dark version. Use these in screens instead of `.white` or `.black`,
/// so dark mode looks right.
enum Theme {

    // Brand orange (the same in light and dark mode)

    static let orange = Color(hex: 0xF26B1D)
    static let orangeLight = Color(hex: 0xFF8A3D)
    static let orangeDark = Color(hex: 0xE5530E)
    static let orangeTint = Color(light: 0xFFEDE2, dark: 0x3D2414)

    // Neutrals

    /// Main text colour. Also used for selected chips.
    static let ink = Color(light: 0x1C1C1E, dark: 0xF2F2F7)
    /// Text on top of an `ink` background.
    static let onInk = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    /// Background of cards, fields and pop-ups.
    static let surface = Color(light: 0xFFFFFF, dark: 0x262220)
    static let fieldGray = Color(light: 0xEEEEF1, dark: 0x332E2B)
    static let buttonGray = Color(light: 0xE4E4E6, dark: 0x3A3532)
    static let sheetBackground = Color(light: 0xF8F5F2, dark: 0x1A1716)
    /// Light grey fill, e.g. unselected chips and icon circles.
    static let subtleFill = Color(light: 0xEDEDEF, dark: 0x332E2B)
    /// Slightly darker fill for fields inside a card.
    static let insetFill = Color(light: 0xF6F6F7, dark: 0x2E2A27)
    /// The empty part of progress bars and charts.
    static let track = Color(light: 0xECECEE, dark: 0x3A3532)
    /// Thin borders and dividers.
    static let hairline = Color(light: 0xE2E2E6, dark: 0x45403C)
    /// Medium grey for less important icons.
    static let mutedInk = Color(light: 0x6B6B70, dark: 0xA19C98)
    /// Light grey for empty stars and unticked circles.
    static let faintInk = Color(light: 0xC7C7CC, dark: 0x5C5652)
    /// Shadow colour (stronger in dark mode so it still shows).
    static let shadow = Color(light: 0x000000, dark: 0x000000, darkOpacity: 0.5)
    /// Thin border around cards, so their edges show on the dark background.
    static let cardBorder = Color(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.05, darkOpacity: 0.08)

    // Status

    static let green = Color(light: 0x1E9E57, dark: 0x34C474)
    static let greenTint = Color(light: 0xE3F5EA, dark: 0x163423)
    static let gold = Color(hex: 0xF5A524)
    static let yellowTint = Color(light: 0xFFF4D6, dark: 0x3A2F12)
    static let destructive = Color(light: 0xF0453A, dark: 0xFF5A4F)

    // Gradients

    static let primaryGradient = LinearGradient(
        colors: [orangeLight, orangeDark],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let questGradient = LinearGradient(
        colors: [Color(hex: 0xFF9A4D), Color(hex: 0xE8550F)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(light: 0xFFD3B6, dark: 0x2B1B12),
            Color(light: 0xFAF0EA, dark: 0x141211),
            Color(light: 0xFFD9C2, dark: 0x24170F)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Colours for the charts.
    static let chartPalette: [Color] = [
        orange,
        gold,
        Color(light: 0x9C5B36, dark: 0xD08A5E),
        mutedInk,
    ]

    // Shape

    enum Radius {
        static let small: CGFloat = 12
        static let card: CGFloat = 22
        static let button: CGFloat = 18
        static let field: CGFloat = 16
        static let sheet: CGFloat = 28
    }

    // Layout
    // Every screen uses the same spacing, so they all line up.

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 20
        static let xl: CGFloat = 24
    }

    /// Space at the left and right of each screen.
    static let screenMargin: CGFloat = 20
}

extension Color {
    /// A colour from a hex number, e.g. `Color(hex: 0xF26B1D)`.
    init(hex: UInt32, opacity: Double = 1) {
        // 0xF26B1D is three pairs of digits: red (F2), green (6B) and blue (1D).
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// A colour with one value for light mode and another for dark mode.
    init(light: UInt32, dark: UInt32, lightOpacity: Double = 1, darkOpacity: Double = 1) {
        // iOS runs this again whenever the app switches between light and dark mode.
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkOpacity)
                : UIColor(hex: light, alpha: lightOpacity)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: Double) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// The "Dark mode" setting from Profile, saved on the phone.
enum AppearanceSetting {
    /// The name it's saved under.
    static let darkModeKey = "isDarkModeOn"
}

extension Cuisine {
    /// The icon for this cuisine's stamp.
    var symbolName: String {
        switch self {
        case .sriLankan: "leaf.fill"
        case .indian: "flame.fill"
        case .chinese: "takeoutbag.and.cup.and.straw.fill"
        case .italian: "fork.knife"
        case .japanese: "fish.fill"
        case .thai: "carrot.fill"
        case .american: "star.fill"
        case .mexican: "sun.max.fill"
        case .korean: "frying.pan.fill"
        case .middleEastern: "moon.stars.fill"
        case .french: "cup.and.saucer.fill"
        case .vietnamese: "mug.fill"
        }
    }

    /// A small tilt for the stamp, so it looks hand-stamped. Each cuisine always gets the same tilt.
    var stampTilt: Double {
        let tilts: [Double] = [-8, 6, -4, 9, -6, 4, -10, 7, -3, 5, -7, 8]
        let index = Self.allCases.firstIndex(of: self) ?? 0
        return tilts[index % tilts.count]
    }

    /// Colours shown when there's no photo.
    var placeholderColors: [Color] {
        switch self {
        case .sriLankan: [Color(hex: 0xF9A65A), Color(hex: 0xC4511C)]
        case .indian: [Color(hex: 0xF7C55A), Color(hex: 0xD27A22)]
        case .chinese: [Color(hex: 0xF07C64), Color(hex: 0xB43A2C)]
        case .italian: [Color(hex: 0xA9CF73), Color(hex: 0x4F8B3B)]
        case .japanese: [Color(hex: 0x8EC5E8), Color(hex: 0x3C78A8)]
        case .thai: [Color(hex: 0xC9A2E0), Color(hex: 0x7A4BA3)]
        case .american: [Color(hex: 0xF4A3A3), Color(hex: 0xB8323B)]
        case .mexican: [Color(hex: 0xF5D76E), Color(hex: 0x3E8E4E)]
        case .korean: [Color(hex: 0xF29C9C), Color(hex: 0x2F4F8F)]
        case .middleEastern: [Color(hex: 0xE8C39E), Color(hex: 0x9A5B2E)]
        case .french: [Color(hex: 0xA7C4F2), Color(hex: 0x2B4C9B)]
        case .vietnamese: [Color(hex: 0xB5E3B0), Color(hex: 0x2E7D5B)]
        }
    }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground(cornerRadius: cornerRadius)
    }
}

extension View {
    /// A rounded card with padding and a soft shadow, used all over the app.
    func cardStyle(padding: CGFloat = 16, cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        modifier(CardStyle(padding: padding, cornerRadius: cornerRadius))
    }

    /// Just the card look (background, thin border and shadow), without padding.
    func cardBackground(cornerRadius: CGFloat = Theme.Radius.card, shadowStrength: Double = 1) -> some View {
        surfaceBackground(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), shadowStrength: shadowStrength)
    }

    /// The card look for any shape, e.g. a capsule for chips.
    func surfaceBackground<S: InsettableShape>(_ shape: S, shadowStrength: Double = 1) -> some View {
        self
            .background(Theme.surface, in: shape)
            .overlay { shape.strokeBorder(Theme.cardBorder, lineWidth: 1) }
            .shadow(color: Theme.shadow.opacity(0.04 * shadowStrength), radius: 1, y: 1)
            .shadow(color: Theme.shadow.opacity(0.07 * shadowStrength), radius: 14, y: 6)
    }
}

/// Makes a bottom sheet as tall as what's inside it, so nothing is cut off on small iPhones.
private struct FittedSheetHeight: ViewModifier {
    @State private var contentHeight: CGFloat = 420

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            // Measure the content, then use that height for the sheet.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                contentHeight = newHeight
            }
            .presentationDetents([.height(contentHeight)])
    }
}

extension View {
    /// The look shared by all bottom sheets.
    func brandSheetStyle() -> some View {
        self
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Theme.Radius.sheet)
            .presentationBackground(Theme.sheetBackground)
    }

    /// Sizes the sheet to fit its content.
    func fittedSheetHeight() -> some View {
        modifier(FittedSheetHeight())
    }
}

/// The peach background behind every screen.
struct AppBackground: View {
    var body: some View {
        Theme.backgroundGradient
            .ignoresSafeArea()
    }
}

extension View {
    func appBackground() -> some View {
        background { AppBackground() }
    }
}

/// Sets a screen's title without showing it (the title is still used for the back button).
private struct HiddenNavigationTitle: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(removing: .title)
        } else {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { Text("") }
                }
        }
    }
}

extension View {
    func navigationTitleHidden(_ title: String) -> some View {
        modifier(HiddenNavigationTitle(title: title))
    }
}

/// The big orange button for a screen's main action.
struct BrandPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.primaryGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .shadow(color: Theme.orange.opacity(isEnabled ? 0.3 : 0), radius: 12, y: 6)
            .opacity(isEnabled ? 1 : 0.5)
            .pressedEffect(configuration.isPressed)
    }
}

/// A grey button for other actions, e.g. "Get directions".
struct BrandSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.buttonGray, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .pressedEffect(configuration.isPressed)
    }
}

/// A light orange button, e.g. "Done" in pop-ups.
struct BrandTintedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.orangeDark)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.orangeTint, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .pressedEffect(configuration.isPressed)
    }
}

/// A button that's just text, e.g. "Continue".
struct BrandTextButtonStyle: ButtonStyle {
    var color: Color = Theme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// For tappable cards: the card shrinks a little when pressed.
struct PressableCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pressedEffect(configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableCardButtonStyle {
    static var pressableCard: PressableCardButtonStyle { PressableCardButtonStyle() }
}

extension ButtonStyle where Self == BrandPrimaryButtonStyle {
    static var brandPrimary: BrandPrimaryButtonStyle { BrandPrimaryButtonStyle() }
}

extension ButtonStyle where Self == BrandSecondaryButtonStyle {
    static var brandSecondary: BrandSecondaryButtonStyle { BrandSecondaryButtonStyle() }
}

extension ButtonStyle where Self == BrandTintedButtonStyle {
    static var brandTinted: BrandTintedButtonStyle { BrandTintedButtonStyle() }
}

extension ButtonStyle where Self == BrandTextButtonStyle {
    static var brandText: BrandTextButtonStyle { BrandTextButtonStyle() }
}

private extension View {
    func pressedEffect(_ isPressed: Bool) -> some View {
        self
            .scaleEffect(isPressed ? 0.98 : 1)
            .opacity(isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: isPressed)
    }
}

extension String {
    /// The text without spaces or new lines at the start and end.
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Int {
    /// Shows an amount in rupees: `3000.lkr` gives "LKR 3,000".
    var lkr: String {
        "LKR \(formatted(.number))"
    }
}

extension MKCoordinateRegion {
    /// A map area that fits all the points, with some space around them.
    static func fitting(
        _ coordinates: [CLLocationCoordinate2D],
        paddingFactor: Double = 1.8,
        minimumDelta: Double = 0.006
    ) -> MKCoordinateRegion {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else {
            return MKCoordinateRegion()
        }

        // Centre on the middle of the points, and zoom out a bit past the outermost ones.
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * paddingFactor, minimumDelta),
            longitudeDelta: max((maxLon - minLon) * paddingFactor, minimumDelta)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

extension View {
    /// Gives previews the app state and router that screens need.
    func previewEnvironment() -> some View {
        self
            .environment(AppState())
            .environment(AppRouter())
    }

    /// Puts a preview inside a navigation stack, so its links work.
    func previewInNavigationStack() -> some View {
        NavigationStack {
            self.navigationDestination(for: AppRoute.self) { route in
                AppRouteDestination(route: route)
            }
        }
        .previewEnvironment()
    }
}
