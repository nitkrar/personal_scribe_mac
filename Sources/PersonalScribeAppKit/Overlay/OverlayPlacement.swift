import AppKit
import SwiftUI

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

/// Which side of the pill stays fixed when it changes size, chosen from
/// where the pill was put: next to an edge, the edge-side stays put and
/// the pill grows away from it; elsewhere it grows from its center.
/// Horizontally "next to an edge" means the largest pill state would not
/// fit centered there; vertically the bottom stays fixed unless the
/// largest state would cross the top.
struct PillAnchor: Equatable {
    enum Horizontal: Equatable {
        case leading(CGFloat)
        case center(CGFloat)
        case trailing(CGFloat)
    }

    enum Vertical: Equatable {
        case bottom(CGFloat)
        case top(CGFloat)
    }

    let horizontal: Horizontal
    let vertical: Vertical

    init(home: NSRect, within bounds: NSRect, largestSize: NSSize) {
        let inset = bounds.insetBy(dx: OverlayPlacement.screenMargin, dy: OverlayPlacement.screenMargin)
        if home.midX - largestSize.width / 2 < inset.minX {
            horizontal = .leading(home.minX)
        } else if home.midX + largestSize.width / 2 > inset.maxX {
            horizontal = .trailing(home.maxX)
        } else {
            horizontal = .center(home.midX)
        }
        vertical = home.minY + largestSize.height > inset.maxY ? .top(home.maxY) : .bottom(home.minY)
    }

    /// Where the pill's content sits inside its panel, so it stays on the
    /// fixed side while the panel resizes around it.
    var contentAlignment: Alignment {
        switch (horizontal, vertical) {
        case (.leading, .bottom): .bottomLeading
        case (.center, .bottom): .bottom
        case (.trailing, .bottom): .bottomTrailing
        case (.leading, .top): .topLeading
        case (.center, .top): .top
        case (.trailing, .top): .topTrailing
        }
    }

    /// Frame for a pill of `size`, kept on-screen.
    func frame(for size: NSSize, within bounds: NSRect) -> NSRect {
        let x: CGFloat
        switch horizontal {
        case .leading(let minX): x = minX
        case .center(let midX): x = midX - size.width / 2
        case .trailing(let maxX): x = maxX - size.width
        }
        let y: CGFloat
        switch vertical {
        case .bottom(let minY): y = minY
        case .top(let maxY): y = maxY - size.height
        }
        return OverlayPlacement.clamp(NSRect(x: x, y: y, width: size.width, height: size.height), within: bounds)
    }
}
