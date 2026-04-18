import AppKit
import SwiftUI

/// SwiftUI-wrapped `NSVisualEffectView` for AppKit vibrancy /
/// background blur inside SwiftUI views.
///
/// Used by `ResponseCardView` to give the command-mode response card
/// the standard macOS HUD-material look (matches tooltips, Spotlight,
/// notification banners).
///
/// ## Why this isn't inside SwiftUI's `Material`
/// SwiftUI's `.regularMaterial` / `.hudWindow` require macOS 12+ and
/// always clip to the view's shape. The response card needs explicit
/// control over the clip shape (rounded rect with specific radius)
/// and the `.hudWindow` material specifically, not `.regularMaterial`.
/// Wrapping the AppKit primitive directly is the smallest solution.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}
