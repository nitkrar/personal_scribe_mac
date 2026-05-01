import AppKit
import SwiftUI

@MainActor
protocol StreamCardPresenting: AnyObject {
    func show(text: String, above pillWindow: NSWindow)
    func update(text: String)
    func reanchor(abovePillFrame pillFrame: NSRect)
    func hide()
}

@MainActor
protocol StreamCardBuilding {
    func makeStreamCard() -> any StreamCardPresenting
}

struct LiveStreamCardBuilder: StreamCardBuilding {
    func makeStreamCard() -> any StreamCardPresenting {
        StreamCard()
    }
}

@MainActor
public final class StreamCard: NSPanel, StreamCardPresenting {
    private let hostingView: NSHostingView<StreamCardView>
    private var currentText: String = ""
    private var lastPillFrame: NSRect = .zero

    private static let minimumCardWidth: CGFloat = 320
    private static let maximumCardWidth: CGFloat = 560
    private static let height: CGFloat = 42
    private static let gapAbovePill: CGFloat = 8
    private static let contentPaddingWidth: CGFloat = 74

    public init() {
        hostingView = NSHostingView(rootView: StreamCardView(text: ""))
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        contentView = hostingView
    }

    public override var canBecomeKey: Bool { false }

    public override var canBecomeMain: Bool { false }

    func show(text: String, above pillWindow: NSWindow) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            hide()
            return
        }

        currentText = trimmedText
        lastPillFrame = pillWindow.frame
        applyLayout(text: trimmedText, pillFrame: pillWindow.frame, display: false)

        if !isVisible {
            alphaValue = 0
            orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
            }
        }
    }

    func update(text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            hide()
            return
        }

        currentText = trimmedText
        let pillFrame = lastPillFrame == .zero ? frame : lastPillFrame
        applyLayout(text: trimmedText, pillFrame: pillFrame, display: true)
    }

    func reanchor(abovePillFrame pillFrame: NSRect) {
        lastPillFrame = pillFrame
        guard isVisible else {
            return
        }

        applyLayout(text: currentText, pillFrame: pillFrame, display: true)
    }

    public func hide() {
        guard isVisible else {
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.orderOut(nil)
            }
        })
    }

    private func applyLayout(
        text: String,
        pillFrame: NSRect,
        display: Bool
    ) {
        hostingView.rootView = StreamCardView(text: text)

        let cardWidth = Self.estimatedWidth(for: text, pillWidth: pillFrame.width)
        let x = pillFrame.midX - cardWidth / 2
        let y = pillFrame.maxY + Self.gapAbovePill

        setFrame(
            NSRect(
                x: x,
                y: y,
                width: cardWidth,
                height: Self.height
            ),
            display: display
        )
    }

    private static func estimatedWidth(for text: String, pillWidth: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let measuredWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        let desiredWidth = max(
            measuredWidth + contentPaddingWidth,
            pillWidth + 72,
            minimumCardWidth
        )
        return min(desiredWidth, maximumCardWidth)
    }
}
