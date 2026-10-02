import AppKit

/// Edge-aware placement for the pill and the cards anchored to it.
/// Every overlay frame goes through here so nothing renders past the
/// screen's visible area: the pill is pulled back on-screen, and cards
/// stay centered on the pill where possible, slide sideways at the left
/// or right edge, and flip below the pill when there's no room above.
enum OverlayPlacement {
    static let screenMargin: CGFloat = 8

    /// Visible frame of the screen the overlay is on (falls back to the
    /// screen it overlaps most, then the main screen; unbounded when
    /// there is no screen at all).
    @MainActor
    static func visibleFrame(containing frame: NSRect) -> NSRect {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.max { $0.frame.intersection(frame).area < $1.frame.intersection(frame).area }
            ?? NSScreen.main
        return screen?.visibleFrame ?? frame.insetBy(dx: -100_000, dy: -100_000)
    }

    /// Shift `frame` (size unchanged) so it lies inside `bounds`.
    static func clamp(_ frame: NSRect, within bounds: NSRect) -> NSRect {
        let inset = bounds.insetBy(dx: screenMargin, dy: screenMargin)
        var origin = frame.origin
        origin.x = min(max(origin.x, inset.minX), inset.maxX - frame.width)
        origin.y = min(max(origin.y, inset.minY), inset.maxY - frame.height)
        return NSRect(origin: origin, size: frame.size)
    }

    /// Frame for a card of `size` attached to the pill: above it when it
    /// fits, below it otherwise; horizontally centered on the pill, then
    /// clamped to the screen. Width is capped to the screen width.
    static func cardFrame(
        size: NSSize,
        pillFrame: NSRect,
        within bounds: NSRect,
        gap: CGFloat
    ) -> NSRect {
        let inset = bounds.insetBy(dx: screenMargin, dy: screenMargin)
        let width = min(size.width, inset.width)
        let aboveY = pillFrame.maxY + gap
        let y = aboveY + size.height <= inset.maxY
            ? aboveY
            : pillFrame.minY - gap - size.height
        let x = min(max(pillFrame.midX - width / 2, inset.minX), inset.maxX - width)
        return NSRect(x: x, y: y, width: width, height: size.height)
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
