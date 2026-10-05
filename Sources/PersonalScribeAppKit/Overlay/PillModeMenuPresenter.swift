import AppKit
import PersonalScribeCore

@MainActor
final class PillModeMenuPresenter: NSObject {
    private let modesProvider: @MainActor () -> [WorkflowMode]
    private let currentModeIDProvider: @MainActor () -> String?
    private let onSelect: @MainActor (WorkflowMode) async -> Void

    init(
        modesProvider: @escaping @MainActor () -> [WorkflowMode],
        currentModeIDProvider: @escaping @MainActor () -> String?,
        onSelect: @escaping @MainActor (WorkflowMode) async -> Void
    ) {
        self.modesProvider = modesProvider
        self.currentModeIDProvider = currentModeIDProvider
        self.onSelect = onSelect
    }

    func present() {
        makeMenu().popUp(
            positioning: nil,
            at: NSEvent.mouseLocation,
            in: nil
        )
    }

    func makeMenu() -> NSMenu {
        let currentModeID = currentModeIDProvider()
        let menu = NSMenu(title: "Mode")
        menu.autoenablesItems = false
        for mode in modesProvider() {
            let item = NSMenuItem(
                title: mode.name,
                action: #selector(handleSelection(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.id
            item.state = mode.id == currentModeID ? .on : .off
            item.isEnabled = true
            menu.addItem(item)
        }
        return menu
    }

    func selectMode(id: String) async {
        guard let mode = modesProvider().first(where: { $0.id == id }) else {
            return
        }
        await onSelect(mode)
    }

    @objc private func handleSelection(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Task { @MainActor in
            await selectMode(id: id)
        }
    }
}
