import SwiftUI

/// 1Buck Apps visual language, same values as 1Cleaner for iPhone: Antosha orange, white surfaces and near-black
/// type. `accent` is for fills, icons and large text; `accentDeep` keeps small text readable on white.
enum Theme {
    static let background = Color(hex: 0xF6F4F1)
    static let sidebar = Color(hex: 0xEFECE8)
    static let surface = Color.white
    static let text = Color(hex: 0x141210)
    static let secondaryText = Color(hex: 0x6B645E)
    static let accent = Color(hex: 0xFF6A13)
    static let accentDeep = Color(hex: 0xC2410C)
    static let accentSoft = Color(hex: 0xFF6A13).opacity(0.12)
    static let success = Color(hex: 0x12B76A)
    static let danger = Color(hex: 0xD92D20)
    static let warning = Color(hex: 0xF5A524)
    static let hairline = Color.black.opacity(0.07)

    static let accentGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension Font {
    static func app(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Large numbers such as sizes and freed bytes.
    static func appNumber(_ size: CGFloat, weight: Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, destructive: destructive)
    }

    private struct PrimaryButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let destructive: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.app(14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(
                    destructive ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(Theme.accentGradient),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .shadow(color: (destructive ? Theme.danger : Theme.accent).opacity(isEnabled ? 0.25 : 0), radius: 10, y: 4)
                .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.app(14, weight: .semibold))
            .foregroundStyle(Theme.accentDeep)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct Panel<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
    }
}

/// The 1Cleaner logo, same artwork as the iPhone app icon.
struct BrandMark: View {
    var size: CGFloat = 56

    var body: some View {
        Image("BrandLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            .shadow(color: Theme.accent.opacity(0.3), radius: size * 0.15, y: size * 0.06)
            .accessibilityHidden(true)
    }
}

/// A short colored note above a list: a warning, a permanent-removal reminder or a scan limitation.
struct NoteBanner: View {
    enum Tone { case info, warning, danger }

    let text: String
    var tone: Tone = .info

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.app(12.5))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var icon: String {
        switch tone {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "exclamationmark.octagon.fill"
        }
    }

    private var color: Color {
        switch tone {
        case .info: Theme.accentDeep
        case .warning: Theme.warning
        case .danger: Theme.danger
        }
    }
}
