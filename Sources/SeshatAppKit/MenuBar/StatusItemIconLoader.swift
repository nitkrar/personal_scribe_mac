import AppKit
import Foundation

/// Loads the menu-bar status icon from the SeshatAppKit SwiftPM
/// resource bundle.
///
/// ## Why this helper exists
/// SwiftPM places `Sources/SeshatAppKit/Resources/` into a per-module
/// resource bundle accessed via `Bundle.module`, NOT into
/// `Bundle.main`. `NSImage(named:)` only searches `Bundle.main`, so it
/// returns `nil` for assets that live in a SwiftPM module bundle —
/// which is exactly what happened with the "S" fallback being drawn in
/// the packaged `.app`.
///
/// ## Why we don't use an `.xcassets` asset catalog
/// SwiftPM's `.process("Resources")` copies `.xcassets` directories
/// verbatim; it does NOT run `actool` to compile them into a `.car`
/// file. Because of that, `Bundle.module.image(forResource:)` returns
/// nil for catalog-based names (there's no catalog to look up). The
/// workaround is to ship the PNGs as top-level resources and load them
/// directly via their file URLs.
///
/// `@2x` retina support is reconstructed manually by merging the
/// `StatusBarIcon@2x.png` representation into the base `NSImage`.
@MainActor
enum StatusItemIconLoader {
    /// Loads the menu-bar icon from `Bundle.module`. Returns `nil`
    /// only if the base `StatusBarIcon.png` is missing from the
    /// bundle (e.g. the resource copy was stripped from the build).
    static func loadStatusBarIcon() -> NSImage? {
        guard let url1x = Bundle.module.url(forResource: "StatusBarIcon", withExtension: "png") else {
            return nil
        }
        guard let image = NSImage(contentsOf: url1x) else {
            return nil
        }

        // Add the @2x representation so the status item renders sharp
        // on retina displays. macOS doesn't auto-discover @2x siblings
        // when loading via `NSImage(contentsOf:)` — we add the
        // representation manually.
        if let url2x = Bundle.module.url(forResource: "StatusBarIcon@2x", withExtension: "png"),
           let image2x = NSImage(contentsOf: url2x) {
            for rep in image2x.representations {
                image.addRepresentation(rep)
            }
        }

        image.isTemplate = true
        return image
    }
}
