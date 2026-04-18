import SwiftUI

/// Seshat design-system tokens (palette, typography, spacing, radii).
///
/// This is the **single source of truth** for every colour, font, and
/// spacing value used anywhere in `SeshatAppKit`. Every Phase 2+ view
/// consumes it. No other file in the codebase is permitted to construct
/// a `Color` from a hex string; grepping for `Color(hex:` outside this
/// file MUST return zero hits.
///
/// Reference: `plans/seshat_agent_bundle/01_Foundations/assets/colour_system.png`
public enum SeshatTheme {
    // MARK: - Hex → Color bridge

    /// Parse a 6-digit hex string (no `#`, case-insensitive) into a
    /// sRGB `Color`. Returns `Color.clear` for malformed input so that
    /// a misspelled token doesn't crash production UI — the missing
    /// colour will be caught during visual review or by the theme
    /// snapshot tests.
    ///
    /// Only this helper is allowed to call the raw SwiftUI / NSColor
    /// hex-to-channel conversion. Other sites MUST use the semantic
    /// `SeshatTheme.Palette.*` tokens.
    public static func color(hex: String) -> Color {
        Color(hex: hex)
    }

    // MARK: - Palette

    public struct Palette: Sendable {
        public let scheme: ColorScheme

        // Backgrounds / surfaces
        public let appBackground: Color
        public let surface: Color
        public let elevatedSurface: Color
        public let hoverState: Color

        // Brand
        public let brandChampagne: Color

        // Pill overlay chrome (Sprint 2 dogfood redesign). The pill
        // keeps a dark navy fill in both schemes so it reads the same
        // way over any background — matches the WisprFlow-inspired
        // mockup.
        public let pillBackground: Color

        // Stop-button red for the pill recording state. Softer coral
        // than `statusRecording` (iOS system red) to avoid overpowering
        // the champagne accent — keeps the stop affordance visible
        // without screaming.
        public let pillStopRed: Color

        // Pill foreground text / glyph colour. Warm pale cream; keeps
        // legibility on the dark navy pill surface in both schemes.
        public let pillForegroundText: Color

        // Text (base + opacities; apply opacity at the callsite so the
        // opacity token stays visible to the design system).
        public let primaryTextBase: Color
        public let primaryTextOpacity: Double
        public let secondaryTextBase: Color
        public let secondaryTextOpacity: Double

        // Status
        public let statusReady: Color
        public let statusRecording: Color
        public let statusLink: Color

        /// Convenience — `primaryTextBase` with `primaryTextOpacity`
        /// already applied.
        public var primaryText: Color {
            primaryTextBase.opacity(primaryTextOpacity)
        }

        /// Convenience — `secondaryTextBase` with `secondaryTextOpacity`
        /// already applied.
        public var secondaryText: Color {
            secondaryTextBase.opacity(secondaryTextOpacity)
        }

        /// Dark palette — verbatim hex values from
        /// `01_Foundations/assets/colour_system.png`.
        public static let dark = Palette(
            scheme: .dark,
            appBackground: Color(hex: "0E0E14"),
            surface: Color(hex: "1C1C1E"),
            elevatedSurface: Color(hex: "252525"),
            hoverState: Color(hex: "2A2A2A"),
            brandChampagne: Color(hex: "D4D0C8"),
            pillBackground: Color(hex: "1A1B2E"),
            pillStopRed: Color(hex: "EF5350"),
            pillForegroundText: Color(hex: "E8E6E0"),
            primaryTextBase: Color(hex: "FFFFFF"),
            primaryTextOpacity: 0.60,
            secondaryTextBase: Color(hex: "FFFFFF"),
            secondaryTextOpacity: 0.35,
            statusReady: Color(hex: "30D158"),
            statusRecording: Color(hex: "FF453A"),
            statusLink: Color(hex: "0A84FF")
        )

        /// Light palette — verbatim hex values from
        /// `01_Foundations/assets/colour_system.png`. The "elevated
        /// surface" cell in the asset renders as `#F0EFE9`; we treat
        /// that as the canonical pale-cream value.
        public static let light = Palette(
            scheme: .light,
            appBackground: Color(hex: "F5F5F0"),
            surface: Color(hex: "FFFFFF"),
            elevatedSurface: Color(hex: "F0EFE9"),
            hoverState: Color(hex: "E8E7E0"),
            brandChampagne: Color(hex: "6B6760"),
            pillBackground: Color(hex: "1A1B2E"),
            pillStopRed: Color(hex: "EF5350"),
            pillForegroundText: Color(hex: "E8E6E0"),
            primaryTextBase: Color(hex: "1A1A1A"),
            primaryTextOpacity: 1.0,
            secondaryTextBase: Color(hex: "1A1A1A"),
            secondaryTextOpacity: 0.45,
            statusReady: Color(hex: "28A745"),
            statusRecording: Color(hex: "D93025"),
            statusLink: Color(hex: "0066CC")
        )

        /// Accessor used by every view — pick the palette matching the
        /// current environment `ColorScheme`.
        ///
        /// Usage:
        /// ```swift
        /// @Environment(\.colorScheme) private var scheme
        /// var body: some View {
        ///     let palette = SeshatTheme.Palette.for(scheme: scheme)
        ///     Text("Hi").foregroundStyle(palette.primaryText)
        /// }
        /// ```
        public static func `for`(scheme: ColorScheme) -> Palette {
            switch scheme {
            case .dark: return .dark
            case .light: return .light
            @unknown default: return .dark
            }
        }
    }

    // MARK: - Typography

    /// A typography token bundles a platform `Font` with the numeric
    /// point size used to construct it, so components that need to
    /// reason about size (icons aligned to cap-height, for instance)
    /// can read it without re-hardcoding the value.
    public struct FontToken: Sendable {
        public let pointSize: CGFloat
        public let weight: Font.Weight
        public let design: Font.Design
        private let resolvedFont: Font

        public init(
            pointSize: CGFloat,
            weight: Font.Weight,
            design: Font.Design
        ) {
            self.pointSize = pointSize
            self.weight = weight
            self.design = design
            self.resolvedFont = Font.system(
                size: pointSize,
                weight: weight,
                design: design
            )
        }

        public var font: Font { resolvedFont }
    }

    public enum Typography {
        /// SF Pro Display Bold 20pt — window titles.
        public static let display = FontToken(
            pointSize: 20,
            weight: .bold,
            design: .default
        )

        /// SF Pro Text Regular 13pt — body content.
        public static let body = FontToken(
            pointSize: 13,
            weight: .regular,
            design: .default
        )

        /// SF Pro Text Regular 11pt — timestamps, labels, captions.
        public static let caption = FontToken(
            pointSize: 11,
            weight: .regular,
            design: .default
        )
    }

    // MARK: - Radius & spacing

    public enum Radius {
        /// Pill-overlay capsule radius — 12pt.
        public static let pill: CGFloat = 12
        /// Main window corner radius — 14pt.
        public static let window: CGFloat = 14
        /// List-row / card radius — 8pt.
        public static let row: CGFloat = 8
    }

    public enum Spacing {
        /// Outer window padding — 16pt.
        public static let windowPadding: CGFloat = 16
        /// Row padding — 12pt.
        public static let rowPadding: CGFloat = 12
        /// Icon padding — 8pt.
        public static let iconPadding: CGFloat = 8
    }

    // MARK: - Component metrics

    enum Components {
        enum StatusPill {
            static let itemSpacing: CGFloat = 6
            static let dotSize: CGFloat = 8
            static let horizontalPadding: CGFloat = 10
            static let verticalPadding: CGFloat = 4
            static let borderWidth: CGFloat = 0.5
            static let borderOpacity: Double = 0.15
        }

        enum TagChip {
            static let horizontalPadding: CGFloat = 8
            static let verticalPadding: CGFloat = 3
            static let cornerRadius: CGFloat = 6
            static let borderWidth: CGFloat = 0.5
            static let accentFillOpacity: Double = 0.18
            static let neutralBorderOpacity: Double = 0.15
            static let accentBorderOpacity: Double = 0.35
        }

        enum ActionButton {
            static let horizontalPadding: CGFloat = 16
            static let verticalPadding: CGFloat = 8
            static let minimumWidth: CGFloat = 92
            static let borderWidth: CGFloat = 0.5
            static let primaryBorderOpacity: Double = 0.60
            static let secondaryBorderOpacity: Double = 0.20
            static let disabledOpacity: Double = 0.45
        }

        enum Preview {
            static let compactRowSpacing: CGFloat = 8
            static let stackSpacing: CGFloat = 10
            static let waveformStackSpacing: CGFloat = 20
            static let logoRowSpacing: CGFloat = 24
            static let canvasPadding: CGFloat = 24
        }
    }
}

private extension Color {
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 6,
              trimmed.allSatisfy({ $0.isHexDigit })
        else {
            self = .clear
            return
        }
        var value: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
