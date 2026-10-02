import PersonalScribeCore
import SwiftUI

/// Colors for the pill's three recording-waveform strands
/// (Settings → General → Waveform colors).
///
/// Each palette defines its hues for a dark pill background; the
/// light-background shades are the same hues darkened so they keep
/// contrast on the cream pill.
public enum WaveformPalette: String, CaseIterable, Identifiable, Codable, Sendable {
    case siri
    case champagne
    case champagneAccents
    case aurora
    case sunset
    case ocean

    public struct RGB: Equatable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double
    }

    public static let userDefaultsKey = "WaveformPalette"
    public static let `default`: WaveformPalette = .siri

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .siri: return "Siri"
        case .champagne: return "Champagne"
        case .champagneAccents: return "Accents"
        case .aurora: return "Aurora"
        case .sunset: return "Sunset"
        case .ocean: return "Ocean"
        }
    }

    /// Mono palettes vary strand opacity instead of hue.
    public var strandOpacities: [Double] {
        switch self {
        case .champagne: return [1.0, 0.6, 0.35]
        default: return [0.95, 0.9, 0.9]
        }
    }

    public func strandRGB(onDarkBackground: Bool) -> [RGB] {
        let hexes: [UInt32]
        switch self {
        case .siri: hexes = [0x59D9FF, 0xFF61BD, 0x8F7DFF]
        case .champagne: hexes = [0xD4D0C8, 0xD4D0C8, 0xD4D0C8]
        case .champagneAccents: hexes = [0xD4D0C8, 0x5FB3A8, 0xD98C9A]
        case .aurora: hexes = [0x4ADE80, 0xA3E635, 0xC084FC]
        case .sunset: hexes = [0xFBBF24, 0xFB7185, 0xF472B6]
        case .ocean: hexes = [0x3B82F6, 0x38BDF8, 0x67E8F9]
        }
        let shade = onDarkBackground ? 1.0 : Self.lightBackgroundShade
        return hexes.map { hex in
            RGB(
                red: Double((hex >> 16) & 0xFF) / 255 * shade,
                green: Double((hex >> 8) & 0xFF) / 255 * shade,
                blue: Double(hex & 0xFF) / 255 * shade
            )
        }
    }

    public func strandColors(onDarkBackground: Bool) -> [Color] {
        zip(strandRGB(onDarkBackground: onDarkBackground), strandOpacities).map { rgb, opacity in
            Color(red: rgb.red, green: rgb.green, blue: rgb.blue).opacity(opacity)
        }
    }

    static let lightBackgroundShade = 0.55

    public static func preference(defaults: UserDefaults = .standard) -> Preference<Self> {
        Preference(key: userDefaultsKey, default: .default, defaults: defaults)
    }

    public static func resolve(from defaults: UserDefaults = .standard) -> WaveformPalette {
        preference(defaults: defaults).resolve()
    }

    public func persist(to defaults: UserDefaults = .standard) {
        Self.preference(defaults: defaults).persist(self)
    }
}
