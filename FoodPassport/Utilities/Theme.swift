import SwiftUI
import Foundation
import MapKit

// MARK: - Theme

/// Colours, gradients and sizes taken from the Figma prototype.
enum Theme {

    // MARK: Brand

    static let orange = Color(hex: 0xF26B1D)
    static let orangeLight = Color(hex: 0xFF8A3D)
    static let orangeDark = Color(hex: 0xE5530E)
    static let orangeTint = Color(hex: 0xFFEDE2)

    // MARK: Neutrals

    static let ink = Color(hex: 0x1C1C1E)
    static let fieldGray = Color(hex: 0xEEEEF1)
    static let buttonGray = Color(hex: 0xE4E4E6)
    static let sheetBackground = Color(hex: 0xF8F5F2)

    // MARK: Status

    static let green = Color(hex: 0x1E9E57)
    static let greenTint = Color(hex: 0xE3F5EA)
    static let gold = Color(hex: 0xF5A524)
    static let yellowTint = Color(hex: 0xFFF4D6)
    static let destructive = Color(hex: 0xF0453A)

    // MARK: Gradients

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
        colors: [Color(hex: 0xFFD3B6), Color(hex: 0xFAF0EA), Color(hex: 0xFFD9C2)],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: Shape

    enum Radius {
        static let card: CGFloat = 22
        static let button: CGFloat = 18
        static let field: CGFloat = 16
    }
}

// MARK: - Color

extension Color {
    /// Creates a colour from a hex value such as `0xF26B1D`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Cuisine

extension Cuisine {
    /// SF Symbol used for this cuisine's passport stamp and image placeholders.
    var symbolName: String {
        switch self {
        case .sriLankan: "leaf.fill"
        case .indian: "flame.fill"
        case .chinese: "takeoutbag.and.cup.and.straw.fill"
        case .italian: "fork.knife"
        case .japanese: "fish.fill"
        case .thai: "carrot.fill"
        }
    }

    /// Warm gradient shown in place of a food photo until real images are added.
    var placeholderColors: [Color] {
        switch self {
        case .sriLankan: [Color(hex: 0xF9A65A), Color(hex: 0xC4511C)]
        case .indian: [Color(hex: 0xF7C55A), Color(hex: 0xD27A22)]
        case .chinese: [Color(hex: 0xF07C64), Color(hex: 0xB43A2C)]
        case .italian: [Color(hex: 0xA9CF73), Color(hex: 0x4F8B3B)]
        case .japanese: [Color(hex: 0x8EC5E8), Color(hex: 0x3C78A8)]
        case .thai: [Color(hex: 0xC9A2E0), Color(hex: 0x7A4BA3)]
        }
    }
}

// MARK: - CardStyle

struct CardStyle: ViewModifier {
    var padding: CGFloat
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
}

// MARK: - View

extension View {
    /// White rounded card with a soft shadow — the main surface used throughout the prototype.
    func cardStyle(padding: CGFloat = 16, cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        modifier(CardStyle(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - AppBackground

/// The soft peach gradient behind every screen.
struct AppBackground: View {
    var body: some View {
        Theme.backgroundGradient
            .ignoresSafeArea()
    }
}

// MARK: - View

extension View {
    func appBackground() -> some View {
        background { AppBackground() }
    }
}

// MARK: - HiddenNavigationTitle

/// Gives a screen a navigation title (used as the next screen's back-button label) without displaying it.
/// Matches prototype screens that show only a back button above their own content.
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

// MARK: - View

extension View {
    func navigationTitleHidden(_ title: String) -> some View {
        modifier(HiddenNavigationTitle(title: title))
    }
}

// MARK: - BrandPrimaryButtonStyle

/// Full-width orange gradient button for the main action on a screen.
struct BrandPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.primaryGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .shadow(color: Theme.orange.opacity(0.3), radius: 12, y: 6)
            .pressedEffect(configuration.isPressed)
    }
}

// MARK: - BrandSecondaryButtonStyle

/// Full-width grey button for secondary actions such as "Get directions".
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

// MARK: - BrandTintedButtonStyle

/// Full-width light-orange button, e.g. "Done" and "Adjust budget" in pop-ups.
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

// MARK: - BrandTextButtonStyle

/// Text-only button with a full-width tap area, e.g. "Continue" or "I'm here – Log visit".
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

// MARK: - ButtonStyle

extension ButtonStyle where Self == BrandPrimaryButtonStyle {
    static var brandPrimary: BrandPrimaryButtonStyle { BrandPrimaryButtonStyle() }
}

// MARK: - ButtonStyle

extension ButtonStyle where Self == BrandSecondaryButtonStyle {
    static var brandSecondary: BrandSecondaryButtonStyle { BrandSecondaryButtonStyle() }
}

// MARK: - ButtonStyle

extension ButtonStyle where Self == BrandTintedButtonStyle {
    static var brandTinted: BrandTintedButtonStyle { BrandTintedButtonStyle() }
}

// MARK: - ButtonStyle

extension ButtonStyle where Self == BrandTextButtonStyle {
    static var brandText: BrandTextButtonStyle { BrandTextButtonStyle() }
}

// MARK: - View

private extension View {
    func pressedEffect(_ isPressed: Bool) -> some View {
        self
            .scaleEffect(isPressed ? 0.98 : 1)
            .opacity(isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: isPressed)
    }
}

// MARK: - Int

extension Int {
    /// Formats an amount in Sri Lankan rupees, e.g. `3000.lkr` → "LKR 3,000".
    var lkr: String {
        "LKR \(formatted(.number))"
    }
}

// MARK: - MKCoordinateRegion

extension MKCoordinateRegion {
    /// A region that contains every coordinate, with some breathing room around the edges.
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

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * paddingFactor, minimumDelta),
            longitudeDelta: max((maxLon - minLon) * paddingFactor, minimumDelta)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

// MARK: - View

extension View {
    /// Injects the shared app state and router so previews can render views that read them from the environment.
    func previewEnvironment() -> some View {
        self
            .environment(AppState())
            .environment(AppRouter())
    }

    /// Wraps a screen in a navigation stack with all app routes registered, for previews of pushed screens.
    func previewInNavigationStack() -> some View {
        NavigationStack {
            self.navigationDestination(for: AppRoute.self) { route in
                AppRouteDestination(route: route)
            }
        }
        .previewEnvironment()
    }
}
