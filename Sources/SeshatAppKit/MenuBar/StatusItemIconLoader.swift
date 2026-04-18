import AppKit
import Foundation

/// Loads the menu-bar status icon from the SeshatAppKit SwiftPM
/// resource bundle.
///
/// ## Why this helper exists
/// SwiftPM places `Sources/SeshatAppKit/Resources/Assets.xcassets`
/// into a per-module resource bundle accessed via `Bundle.module`,
/// NOT into `Bundle.main`. `NSImage(named:)` only searches
/// `Bundle.main` (and the calling class's bundle in AppKit's legacy
/// search order), so it returns `nil` for assets that live in a
/// SwiftPM module bundle — which is exactly what happened with the
/// "S" fallback being drawn in the packaged `.app`.
///
/// `Bundle.image(forResource:)` is the documented AppKit API for
/// loading an image from a specific bundle, and it preserves asset
/// catalog semantics (`@2x` auto-selection, template-rendering-intent
/// from `Contents.json`).
///
/// Kept as a free function (not a type) so it stays trivial to call
/// from `StatusItemController` and trivial to test by invoking it
/// directly from `SeshatAppKitTests`.
@MainActor
enum StatusItemIconLoader {
    /// The asset-catalog name for the menu-bar icon.
    static let assetName = NSImage.Name("StatusBarIcon")

    /// Loads the menu-bar icon from `Bundle.module`. Returns `nil`
    /// only if the asset is genuinely missing (e.g. the resource
    /// bundle was stripped from the build) — callers should keep
    /// their text fallback for that case.
    static func loadStatusBarIcon() -> NSImage? {
        guard let image = Bundle.module.image(forResource: assetName) else {
            return nil
        }
        image.isTemplate = true
        return image
    }
}
