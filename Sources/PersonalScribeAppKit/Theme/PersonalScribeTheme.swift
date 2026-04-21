import SwiftUI

/// PersonalScribe design-system tokens (palette, typography, spacing, radii).
///
/// This is the **single source of truth** for every colour, font, and
/// spacing value used anywhere in `PersonalScribeAppKit`. Every Phase 2+ view
/// consumes it. No other file in the codebase is permitted to construct
/// a `Color` from a hex string; grepping for `Color(hex:` outside this
/// file MUST return zero hits.
///
/// Reference: `plans/seshat_agent_bundle/01_Foundations/assets/colour_system.png`
public enum PersonalScribeTheme {
    // MARK: - Hex → Color bridge

    /// Parse a 6-digit hex string (no `#`, case-insensitive) into a
    /// sRGB `Color`. Returns `Color.clear` for malformed input so that
    /// a misspelled token doesn't crash production UI — the missing
    /// colour will be caught during visual review or by the theme
    /// snapshot tests.
    ///
    /// Only this helper is allowed to call the raw SwiftUI / NSColor
    /// hex-to-channel conversion. Other sites MUST use the semantic
    /// `PersonalScribeTheme.Palette.*` tokens.
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
        ///     let palette = PersonalScribeTheme.Palette.for(scheme: scheme)
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

        /// WindowTint-aware palette accessor.
        ///
        /// * `.dark` tint forces the dark palette regardless of scheme —
        ///   the dark-tinted window must not render light content.
        /// * `.warm` tint always returns the light base with warm
        ///   overrides (brandChampagne, elevatedSurface, hoverState).
        ///   Warm windows render cream; a dark palette would clash.
        /// * `.neutral` and `nil` delegate to `for(scheme:)`.
        ///
        /// Pill tokens (`pillBackground`, `pillForegroundText`) are
        /// NOT affected — the pill is intentionally isolated from
        /// `WindowTint` per project contract.
        public static func `for`(scheme: ColorScheme, tint: WindowTint?) -> Palette {
            guard let tint else {
                return Self.for(scheme: scheme)
            }
            switch tint {
            case .dark:
                return .dark
            case .neutral:
                return Self.for(scheme: scheme)
            case .warm:
                return .warmLight
            }
        }

        /// Light palette with warm-tint overrides. Used when the user
        /// selects `WindowTint.warm`. Only three tokens differ from
        /// `.light`: `elevatedSurface`, `hoverState`, `brandChampagne`.
        /// Every other token (status colours, pill chrome, text,
        /// `appBackground` which is already `F5F5F0` on light,
        /// `surface` which is already `FFFFFF`) matches `.light`.
        static let warmLight = Palette(
            scheme: .light,
            appBackground: Color(hex: "F5F5F0"),
            surface: Color(hex: "FFFFFF"),
            elevatedSurface: Color(hex: "F0EDE8"),
            hoverState: Color(hex: "DCDCD7"),
            brandChampagne: Color(hex: "D4D0C8"),
            pillBackground: Color(hex: "1A1B2E"),
            pillForegroundText: Color(hex: "E8E6E0"),
            primaryTextBase: Color(hex: "1A1A1A"),
            primaryTextOpacity: 1.0,
            secondaryTextBase: Color(hex: "1A1A1A"),
            secondaryTextOpacity: 0.45,
            statusReady: Color(hex: "28A745"),
            statusRecording: Color(hex: "D93025"),
            statusLink: Color(hex: "0066CC")
        )
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

        // MARK: v2 additions — unified-window redesign
        // (App UI design bundle, 2026-04-19). These coexist with the
        // existing tokens above; consumers pick whichever name reads
        // best in context.

        /// 26pt bold — hero headers in the unified window.
        public static let largeTitle = FontToken(
            pointSize: 26,
            weight: .bold,
            design: .default
        )

        /// 20pt bold — section titles (Home, Transcriptions, Modes, Settings).
        /// Same point-size as `display`; kept as a distinct token so
        /// callsites match the Manus reference vocabulary.
        public static let title = FontToken(
            pointSize: 20,
            weight: .bold,
            design: .default
        )

        /// 15pt semibold — card titles, emphasised list rows.
        public static let headline = FontToken(
            pointSize: 15,
            weight: .semibold,
            design: .default
        )

        /// 11pt semibold — uppercase section labels ("TODAY", "YESTERDAY").
        public static let sectionLabel = FontToken(
            pointSize: 11,
            weight: .semibold,
            design: .default
        )

        /// 11pt semibold — bold caption variant for stat-card values.
        public static let captionBold = FontToken(
            pointSize: 11,
            weight: .semibold,
            design: .default
        )
    }

    // MARK: - Radius & spacing

    public enum Radius {
        /// Main window corner radius — 14pt.
        public static let window: CGFloat = 14
        /// List-row / card radius — 8pt.
        public static let row: CGFloat = 8

        // MARK: v2 additions — unified-window redesign
        /// 6pt — tight chips, badges.
        public static let sm: CGFloat = 6
        /// 10pt — medium rounded surfaces.
        public static let md: CGFloat = 10
        /// 14pt — large rounded surfaces (alias of `window`).
        public static let lg: CGFloat = 14
        /// 100pt — full capsule for the 180×34 floating pill.
        /// Any value ≥ half the view's height produces a capsule; 100
        /// is a comfortable margin.
        public static let capsule: CGFloat = 100
    }

    public enum Spacing {
        /// Outer window padding — 16pt.
        public static let windowPadding: CGFloat = 16
        /// Row padding — 12pt.
        public static let rowPadding: CGFloat = 12
        /// Icon padding — 8pt.
        public static let iconPadding: CGFloat = 8

        // MARK: v2 additions — unified-window redesign
        /// 4pt — very tight gaps (icon-to-label inside a chip).
        public static let xs: CGFloat = 4
        /// 8pt — default tight stack spacing.
        public static let sm: CGFloat = 8
        /// 12pt — default row spacing.
        public static let md: CGFloat = 12
        /// 16pt — section-internal spacing.
        public static let lg: CGFloat = 16
        /// 24pt — inter-section spacing.
        public static let xl: CGFloat = 24
        /// 32pt — top-level page spacing.
        public static let xxl: CGFloat = 32
    }

    // MARK: - Accent (v2 — unified-window redesign)

    /// Champagne-family accent tokens, same in both light and dark mode.
    /// Reference: `plans/App UI design/SeshatTheme.swift` (adopted verbatim;
    /// type name adjusted to PersonalScribe naming per project rule).
    public enum Accent {
        /// #CCB990 — primary champagne accent.
        public static let champagne = color(hex: "CCB990")
        /// #B89961 — deeper gold for hover / active variants.
        public static let gold = color(hex: "B89961")
    }

    // MARK: - Status semantic colours (v2)

    public enum Status {
        /// #32C756 — success / connected / ready.
        public static let success = color(hex: "32C756")
        /// #FF9E0A — warning / attention.
        public static let warning = color(hex: "FF9E0A")
        /// #FF453A — destructive / stop / error.
        public static let error = color(hex: "FF453A")
        /// #007AFF — system blue for actionable links / CTA.
        public static let link = color(hex: "007AFF")
    }

    // MARK: - Separator (v2)

    public enum Separator {
        /// #D1D1D6 — standard row divider.
        public static let primary = color(hex: "D1D1D6")
        /// #E5E5EA — subtle background-level divider.
        public static let subtle = color(hex: "E5E5EA")
    }

    // MARK: - Pill explicit palette (v2)
    //
    // The floating pill uses an EXPLICIT appearance regardless of the
    // main window's light/dark mode — it must read consistently over
    // any background. Selection is driven by the `PillAppearance` enum
    // (lands in a later sub-commit).

    public enum Pill {
        public enum Dark {
            /// #1A1B2E — dark-navy pill surface.
            public static let background = color(hex: "1A1B2E")
            /// #D4D0C8 — champagne waveform trace on dark pill.
            public static let waveform = color(hex: "D4D0C8")
            /// #F75138 — stop-button red on dark pill.
            public static let stop = color(hex: "F75138")
            /// #99999E — cancel / secondary glyph on dark pill.
            public static let cancel = color(hex: "99999E")
        }

        public enum Light {
            /// #F0EDE8 — pale-cream pill surface.
            public static let background = color(hex: "F0EDE8")
            /// #333338 — dark waveform trace on light pill.
            public static let waveform = color(hex: "333338")
            /// #F75138 — same stop-red regardless of pill mode.
            public static let stop = color(hex: "F75138")
            /// #808082 — cancel / secondary glyph on light pill.
            public static let cancel = color(hex: "808082")
        }

        /// State-dependent border styling (pill UX spec §2 + §4). Each
        /// visibility state paints a specific rounded-rect stroke over
        /// the pill's rounded-rect surface. Widths in points, colours
        /// from the shared theme palette.
        public enum Border {
            /// 1px white 8% opacity — idle specular rim, matches
            /// the pre-spec chrome so the rest state looks unchanged.
            public static let idleColor = Color.white.opacity(0.08)
            public static let idleWidth: CGFloat = 1.0

            /// 1.5px Clay #C9A96E — used for `.holdToRecord` and
            /// `.recording`. Warm, distinct from the red stop glyph.
            public static let clayColor = color(hex: "C9A96E")
            public static let activeWidth: CGFloat = 1.5

            /// 1px Champagne at 40% opacity — transcribing.
            public static let transcribingColor = color(hex: "D4D0C8").opacity(0.4)
            public static let transcribingWidth: CGFloat = 1.0

            /// 1px Green #50C878 — done (brief checkmark state).
            public static let doneColor = color(hex: "50C878")
            public static let doneWidth: CGFloat = 1.0

            /// 1.5px Red #F75138 — cancel card only (not a pill).
            public static let cancelColor = color(hex: "F75138")
            public static let cancelWidth: CGFloat = 1.5
        }

        /// Cancel-card-specific tokens (pill UX spec §2f). The card is
        /// rendered by a separate view, not by `PillChrome`.
        public enum CancelCard {
            /// #1E2032 — cancel card background (slightly cooler than
            /// the pill's #1A1B2E — lets the card read as a sibling,
            /// not a continuation of the same surface).
            public static let background = color(hex: "1E2032")
            /// #C9A96E on #281E0F — Undo button, matches the clay
            /// border family.
            public static let undoText = color(hex: "C9A96E")
            public static let undoFill = color(hex: "281E0F")
        }
    }

    // MARK: - Row heights (v2)

    public enum RowHeight {
        /// 36pt — compact settings toggle row.
        public static let compact: CGFloat = 36
        /// 52pt — mode / permission card row.
        public static let standard: CGFloat = 52
        /// 56pt — transcript list row (two-line body + timestamp).
        public static let tall: CGFloat = 56
    }

    // MARK: - Layout constants (v2)

    public enum Layout {
        /// 200pt — fixed sidebar width in the unified window.
        public static let sidebarWidth: CGFloat = 200
        /// 760pt — minimum window width.
        public static let windowMinWidth: CGFloat = 760
        /// 520pt — minimum window height.
        public static let windowMinHeight: CGFloat = 520
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
