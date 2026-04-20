import AppKit
import SwiftUI
import PersonalScribeCore

@MainActor
final class NotesWindowController: NSWindowController {
    private let viewModel: NotesViewModel

    init(viewModel: NotesViewModel) {
        self.viewModel = viewModel

        let rootView = NotesView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(
            NSSize(
                width: NotesLayout.windowWidth,
                height: NotesLayout.windowHeight
            )
        )
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.title = "\(AppBrand.displayName) History"

        super.init(window: window)
    }

    convenience init(transcriptReader: any TranscriptReading) {
        self.init(viewModel: NotesViewModel(transcriptReader: transcriptReader))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        guard let window else { return }

        if !window.isVisible {
            window.center()
        }

        Task {
            await viewModel.loadRecent()
        }

        super.showWindow(sender)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class NotesWindowControllerHost: ObservableObject {
    private let controllerFactory: @MainActor () -> NotesWindowController
    private var controller: NotesWindowController?

    init(
        controllerFactory: @escaping @MainActor () -> NotesWindowController
    ) {
        self.controllerFactory = controllerFactory
    }

    func showWindow(_ sender: Any? = nil) {
        if controller == nil {
            controller = controllerFactory()
        }

        controller?.showWindow(sender)
    }
}

private extension NotesWindowController {
    enum NotesLayout {
        static let windowWidth: CGFloat = 1_180
        static let windowHeight: CGFloat = 720
    }
}
