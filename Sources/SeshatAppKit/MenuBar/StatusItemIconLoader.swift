import AppKit
import Foundation

/// Loads menu-bar status icons from the SeshatAppKit SwiftPM resource
/// bundle. Two variants are shipped — `idle` (the passive quill glyph
/// shown when not recording) and `listening` (a subtly different quill
/// pose shown while recording, to give a clearer visual cue than just
/// a color tint).
///
/// ## Why this helper exists
/// SwiftPM places `Sources/SeshatAppKit/Resources/` into a per-module
/// resource bundle accessed via `Bundle.module`, NOT into
/// `Bundle.main`. `NSImage(named:)` only searches `Bundle.main`, so it
/// returns `nil` for assets that live in a SwiftPM module bundle —
/// which was the origin of the earlier "S" fallback bug.
///
/// ## Why we don't use an `.xcassets` asset catalog
/// SwiftPM's `.process("Resources")` copies `.xcassets` directories
/// verbatim; it does NOT run `actool` to compile them into a `.car`
/// file, so `Bundle.module.image(forResource:)` returns nil for
/// catalog-based names. Loading the PNGs directly via their file URLs
/// is the workaround; `@2x` retina support is reconstructed manually
/// by merging the doubled-size PNG as an additional representation.
@MainActor
enum StatusItemIconLoader {
    /// Which icon pose to load.
    enum Pose: String {
        case idle = "StatusBarIcon"
        case listening = "StatusBarIconListening"
    }

    /// Load the template icon for the given pose. Returns `nil` only if
    /// the base `.png` is missing from the bundle (defensive fallback
    /// for a broken build).
    static func loadStatusBarIcon(pose: Pose = .idle) -> NSImage? {
        guard let url1x = Bundle.module.url(
            forResource: pose.rawValue,
            withExtension: "png"
        ) else {
            return nil
        }
        guard let image = NSImage(contentsOf: url1x) else {
            return nil
        }

        // Manually add the @2x representation — macOS doesn't
        // auto-discover `foo@2x.png` siblings when loading via
        // `NSImage(contentsOf:)`.
        if
            let url2x = Bundle.module.url(
                forResource: pose.rawValue + "@2x",
                withExtension: "png"
            ),
            let image2x = NSImage(contentsOf: url2x)
        {
            for rep in image2x.representations {
                image.addRepresentation(rep)
            }
        }

        image.isTemplate = true
        return image
    }
}
