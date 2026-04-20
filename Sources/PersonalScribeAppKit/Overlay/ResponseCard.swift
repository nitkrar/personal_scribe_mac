import AppKit
import SwiftUI

@MainActor
protocol ResponseCardPresenting: AnyObject {
    func show(text: String, above pillWindow: NSWindow, autoDismissAfter: TimeInterval)
    func hide()
}

@MainActor
protocol ResponseCardBuilding {
    func makeResponseCard() -> any ResponseCardPresenting
}

struct LiveResponseCardBuilder: ResponseCardBuilding {
    func makeResponseCard() -> any ResponseCardPresenting {
        ResponseCard()
    }
}

/// Floating `NSPanel` that hosts the Command-Mode response card
/// above the pill overlay. The pill itself never shows response
/// text; the card is a separate panel per the Sprint 2 dogfood
/// design spec so the pill stays visually clean.
///
/// ## Lifecycle
/// * Constructed once by the app composition layer (owned by the
///   same stateful host as `PillOverlayController`).
/// * `show(text:above:autoDismissAfter:)` places the panel 8pt above
///   a given pill window, fades it in over 200ms, and schedules an
///   auto-dismiss timer for the caller-supplied delay.
/// * `hide()` cancels the timer and fades the panel out over 150ms.
///
/// ## Why NSPanel (not another SwiftUI scene)
/// The response card needs precise screen-space positioning above
/// another panel, plus a blur material that doesn't work cleanly as
/// a `MenuBarExtra` sibling. An explicit `NSPanel` keeps the
/// positioning + dismiss semantics simple.
@MainActor
public final class ResponseCard: NSPanel, ResponseCardPresenting {
    private let hostingView: NSHostingView<ResponseCardView>
    private var dismissTimer: Timer?

    /// Horizontal padding (each side) that the owning SwiftUI view
    /// applies. Used to estimate layout height.
    private static let horizontalTextPadding: CGFloat = 12
    /// Vertical padding (top + bottom combined) + small buffer so
    /// descenders + bottom shadow don't clip.
    private static let verticalTextPaddingTotal: CGFloat = 24
    /// Minimum card width — matches the wispr reference card so it
    /// doesn't squash when the anchor pill is very narrow.
    private static let minimumCardWidth: CGFloat = 320
    /// Gap between the top of the pill window and the bottom of the
    /// card.
    private static let gapAbovePill: CGFloat = 8
    /// Default auto-dismiss used by the future command-mode consumer.
    private static let defaultAutoDismissAfter: TimeInterval = 6.0

    public init() {
        let content = ResponseCardView(text: "", onDismiss: {})
        hostingView = NSHostingView(rootView: content)
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        // System shadow off — ResponseCardView applies a SwiftUI shadow
        // AFTER its rounded-rect clipShape, producing a clean edge. The
        // system NSPanel shadow was causing the fuzzy fringe artefact
        // seen on the pill before the 2026-04-18 fix; applying the same
        // correction here preemptively so the card doesn't ship with
        // the same bug when Command Mode (Phase 4) consumes it.
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        contentView = hostingView
    }

    /// Present the card anchored above the given pill window.
    public func show(text: String, above pillWindow: NSWindow) {
        show(
            text: text,
            above: pillWindow,
            autoDismissAfter: Self.defaultAutoDismissAfter
        )
    }

    func show(
        text: String,
        above pillWindow: NSWindow,
        autoDismissAfter: TimeInterval
    ) {
        dismissTimer?.invalidate()

        let pillFrame = pillWindow.frame
        let cardWidth = max(pillFrame.width, Self.minimumCardWidth)
        let cardHeight = Self.estimatedHeight(for: text, width: cardWidth)

        let x = pillFrame.midX - cardWidth / 2
        let y = pillFrame.maxY + Self.gapAbovePill

        setFrame(
            NSRect(x: x, y: y, width: cardWidth, height: cardHeight),
            display: false
        )

        hostingView.rootView = ResponseCardView(text: text) { [weak self] in
            self?.hide()
        }

        if !isVisible {
            alphaValue = 0
            orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
            }
        }

        dismissTimer = Timer.scheduledTimer(
            withTimeInterval: autoDismissAfter,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hide()
            }
        }
    }

    /// Dismiss the card with a 150ms fade-out.
    public func hide() {
        dismissTimer?.invalidate()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.orderOut(nil)
            }
        })
    }

    /// Measure the body text to decide the card's height. Exposed
    /// internally so unit tests can pin the layout math without
    /// needing a live panel.
    static func estimatedHeight(for text: String, width: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
        let boundingWidth = width - (2 * horizontalTextPadding)
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: boundingWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        return ceil(rect.height) + verticalTextPaddingTotal
    }

    // Required to make the panel key-eligible if the dismiss button
    // is clicked; kept identical to the existing DraggablePanel
    // convention.
    public override var canBecomeKey: Bool { true }
}
