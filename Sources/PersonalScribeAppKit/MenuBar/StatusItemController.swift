import AppKit
import Combine
import Foundation
import PersonalScribeCore

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let sceneModel: MenuBarSceneModel
    private let appStore: AppStore
    private let openHistory: @MainActor () -> Void
    private let openSettings: @MainActor () -> Void
    private let isOnboardingCompleteProvider: @MainActor () -> Bool
    private let openURL: @MainActor (URL) -> Void
    private let logger: PersonalScribeLogger

    private var snapshotCancellable: AnyCancellable?
    private var lastSnapshot: AppStoreSnapshot?

    convenience init(
        sceneModel: MenuBarSceneModel,
        defaults: UserDefaults = .standard,
        openHistory: @escaping @MainActor () -> Void = StatusItemController.defaultPhase3Placeholder(name: "History"),
        openSettings: @escaping @MainActor () -> Void = {},
        isOnboardingCompleteProvider: (@MainActor () -> Bool)? = nil,
        openURL: (@MainActor (URL) -> Void)? = nil,
        openMicrophoneSystemSettings: @escaping @MainActor () -> Void = StatusItemController.defaultOpenMicrophoneSettings,
        openInputMonitoringSystemSettings: @escaping @MainActor () -> Void = StatusItemController.defaultOpenInputMonitoringSettings,
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.ui)
    ) {
        self.init(
            sceneModel: sceneModel,
            appStore: sceneModel.appStore,
            defaults: defaults,
            openHistory: openHistory,
            openSettings: openSettings,
            isOnboardingCompleteProvider: isOnboardingCompleteProvider,
            openURL: openURL,
            openMicrophoneSystemSettings: openMicrophoneSystemSettings,
            openInputMonitoringSystemSettings: openInputMonitoringSystemSettings,
            logger: logger
        )
    }

    init(
        sceneModel: MenuBarSceneModel,
        appStore: AppStore,
        defaults: UserDefaults = .standard,
        openHistory: @escaping @MainActor () -> Void = StatusItemController.defaultPhase3Placeholder(name: "History"),
        openSettings: @escaping @MainActor () -> Void = {},
        isOnboardingCompleteProvider: (@MainActor () -> Bool)? = nil,
        openURL: (@MainActor (URL) -> Void)? = nil,
        openMicrophoneSystemSettings: @escaping @MainActor () -> Void = StatusItemController.defaultOpenMicrophoneSettings,
        openInputMonitoringSystemSettings: @escaping @MainActor () -> Void = StatusItemController.defaultOpenInputMonitoringSettings,
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.ui)
    ) {
        let onboardingCompletionPreference = Self.onboardingCompletionPreference(defaults: defaults)
        self.sceneModel = sceneModel
        self.appStore = appStore
        self.openHistory = openHistory
        self.openSettings = openSettings
        self.isOnboardingCompleteProvider = isOnboardingCompleteProvider ?? {
            onboardingCompletionPreference.resolve()
        }
        self.openURL = openURL ?? { url in
            switch url {
            case PermissionServiceAdapter.defaultSystemSettingsDeepLink(for: .microphone):
                openMicrophoneSystemSettings()
            case PermissionServiceAdapter.defaultSystemSettingsDeepLink(for: .inputMonitoring):
                openInputMonitoringSystemSettings()
            default:
                _ = NSWorkspace.shared.open(url)
            }
        }
        self.logger = logger
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        super.init()

        configureStatusItemButton()

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        lastSnapshot = appStore.snapshot

        snapshotCancellable = appStore.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.handleSnapshotChange(self.appStore.snapshot)
                }
            }
        }

        updateStatusItemAppearance(for: appStore.snapshot.sessionState)
    }

    isolated deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    var isStatusItemVisible: Bool {
        statusItem.isVisible
    }

    func setStatusItemVisible(_ isVisible: Bool) {
        statusItem.isVisible = isVisible
    }

    func performMenuAction(_ id: StatusItemMenuModel.ActionID) {
        switch id {
        case .startStopRecording:
            Task { @MainActor in
                await sceneModel.handleRecordButtonTap()
            }
        case .openHistory:
            openHistory()
        case .openSettings:
            openSettings()
        case .openMicrophoneSystemSettings:
            openURL(PermissionServiceAdapter.defaultSystemSettingsDeepLink(for: .microphone))
        case .openInputMonitoringSystemSettings:
            openURL(PermissionServiceAdapter.defaultSystemSettingsDeepLink(for: .inputMonitoring))
        case .quit:
            NSApplication.shared.terminate(nil)
        }
    }

    private func handleSnapshotChange(_ snapshot: AppStoreSnapshot) {
        let previousSnapshot = lastSnapshot
        lastSnapshot = snapshot

        if previousSnapshot?.sessionState != snapshot.sessionState {
            updateStatusItemAppearance(for: snapshot.sessionState)
        }

        guard statusItem.menu?.numberOfItems ?? 0 > 0 else {
            return
        }

        if
            previousSnapshot?.permissions != snapshot.permissions ||
            previousSnapshot?.activeMode != snapshot.activeMode
        {
            rebuildMenu()
        }
    }

    private func configureStatusItemButton() {
        guard let button = statusItem.button else { return }

        if let image = StatusItemIconLoader.loadStatusBarIcon() {
            button.image = image
        } else {
            button.title = "S"
            logger.error("StatusBarIcon asset missing from Bundle.module — falling back to text glyph")
        }

        let label = statusItemLabel(for: .idle)
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    private func updateStatusItemAppearance(for sessionState: SessionState) {
        guard let button = statusItem.button else { return }

        let pose: StatusItemIconLoader.Pose = {
            switch sessionState {
            case .recording, .transcribing:
                return .listening
            case .idle, .error:
                return .idle
            }
        }()

        if let image = StatusItemIconLoader.loadStatusBarIcon(pose: pose) {
            button.image = image
        }

        switch sessionState {
        case .recording:
            button.contentTintColor = .systemRed
        case .transcribing:
            button.contentTintColor = .systemOrange
        case .idle, .error:
            button.contentTintColor = nil
        }

        let label = statusItemLabel(for: sessionState)
        button.toolTip = label
        button.setAccessibilityLabel(label)

        if statusItem.menu?.numberOfItems ?? 0 > 0 {
            rebuildMenu()
        }
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }

        let snapshot = appStore.snapshot
        let permissions = snapshot.permissions
        let model = StatusItemMenuModel.makeUnified(
            sessionState: snapshot.sessionState,
            micPermission: permissions[.microphone] ?? .pending,
            inputMonitoringPermission: permissions[.inputMonitoring] ?? .pending,
            activeModeName: snapshot.activeMode?.name,
            isOnboardingComplete: isOnboardingCompleteProvider()
        )

        menu.removeAllItems()

        for item in model.items {
            switch item {
            case .separator:
                menu.addItem(.separator())
            case .header(let title):
                let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                menuItem.isEnabled = false
                menu.addItem(menuItem)
            case .action(let action):
                let menuItem = NSMenuItem()
                menuItem.title = action.title
                menuItem.keyEquivalent = action.keyEquivalent
                if !action.keyEquivalent.isEmpty {
                    menuItem.keyEquivalentModifierMask =
                        action.id == .startStopRecording ? [.command, .option] : [.command]
                }
                menuItem.isEnabled = action.isEnabled
                menuItem.target = self
                menuItem.action = #selector(handleMenuAction(_:))
                menuItem.representedObject = action.id.rawValue
                menu.addItem(menuItem)
            }
        }
    }

    @objc private func handleMenuAction(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = StatusItemMenuModel.ActionID(rawValue: idString) else {
            logger.error("Menu action fired with unknown representedObject")
            return
        }

        performMenuAction(id)
    }

    private func statusItemLabel(for sessionState: SessionState) -> String {
        switch sessionState {
        case .recording:
            return "\(AppBrand.displayName) — recording"
        case .transcribing:
            return "\(AppBrand.displayName) — transcribing"
        case .idle, .error:
            return AppBrand.displayName
        }
    }

    private static func defaultPhase3Placeholder(name: String) -> @MainActor () -> Void {
        {
            let alert = NSAlert()
            alert.messageText = "\(name) — Coming in Phase 3"
            alert.informativeText = "This window lands alongside NotesWindow / SettingsWindow in Phase 3."
            alert.alertStyle = .informational
            alert.runModal()
        }
    }

    private static let defaultOpenMicrophoneSettings: @MainActor () -> Void = {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private static let defaultOpenInputMonitoringSettings: @MainActor () -> Void = {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func onboardingCompletionPreference(defaults: UserDefaults) -> Preference<Bool> {
        Preference(
            key: "SeshatOnboardingCompleted",
            default: false,
            defaults: defaults
        )
    }
}
