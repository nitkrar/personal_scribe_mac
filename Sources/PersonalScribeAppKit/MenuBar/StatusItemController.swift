import AppKit
import Combine
import Foundation
import PersonalScribeCore

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let sceneModel: MenuBarSceneModel
    private let appStore: AppStore
    private let openHome: @MainActor () -> Void
    private let openTranscriptions: @MainActor () -> Void
    private let openSettings: @MainActor () -> Void
    private let openCopyLastTranscript: @MainActor () -> Void
    private let isOnboardingCompleteProvider: @MainActor () -> Bool
    private let openURL: @MainActor (URL) -> Void
    private let inputDeviceProvider: any AudioInputDeviceProviding
    private let modes: [ModeDescriptor]
    private let setActiveMode: @MainActor (ModeDescriptor) async -> Void
    private let prequitHandler: @MainActor () async -> Void
    private let logger: PersonalScribeLogger

    private var snapshotCancellable: AnyCancellable?
    private var lastSnapshot: AppStoreSnapshot?

    convenience init(
        sceneModel: MenuBarSceneModel,
        defaults: UserDefaults = .standard,
        openHome: @escaping @MainActor () -> Void = StatusItemController.defaultPhase3Placeholder(name: "Home"),
        openTranscriptions: @escaping @MainActor () -> Void = {},
        openSettings: @escaping @MainActor () -> Void = {},
        openCopyLastTranscript: @escaping @MainActor () -> Void = {},
        isOnboardingCompleteProvider: (@MainActor () -> Bool)? = nil,
        openURL: (@MainActor (URL) -> Void)? = nil,
        openMicrophoneSystemSettings: @escaping @MainActor () -> Void = StatusItemController.defaultOpenMicrophoneSettings,
        openInputMonitoringSystemSettings: @escaping @MainActor () -> Void = StatusItemController.defaultOpenInputMonitoringSettings,
        inputDeviceProvider: (any AudioInputDeviceProviding)? = nil,
        modes: [ModeDescriptor] = ModeRegistry.all,
        setActiveMode: @escaping @MainActor (ModeDescriptor) async -> Void = { _ in },
        prequitHandler: @escaping @MainActor () async -> Void = {},
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.ui)
    ) {
        self.init(
            sceneModel: sceneModel,
            appStore: sceneModel.appStore,
            defaults: defaults,
            openHome: openHome,
            openTranscriptions: openTranscriptions,
            openSettings: openSettings,
            openCopyLastTranscript: openCopyLastTranscript,
            isOnboardingCompleteProvider: isOnboardingCompleteProvider,
            openURL: openURL,
            openMicrophoneSystemSettings: openMicrophoneSystemSettings,
            openInputMonitoringSystemSettings: openInputMonitoringSystemSettings,
            inputDeviceProvider: inputDeviceProvider,
            modes: modes,
            setActiveMode: setActiveMode,
            prequitHandler: prequitHandler,
            logger: logger
        )
    }

    init(
        sceneModel: MenuBarSceneModel,
        appStore: AppStore,
        defaults: UserDefaults = .standard,
        openHome: @escaping @MainActor () -> Void = StatusItemController.defaultPhase3Placeholder(name: "Home"),
        openTranscriptions: @escaping @MainActor () -> Void = {},
        openSettings: @escaping @MainActor () -> Void = {},
        openCopyLastTranscript: @escaping @MainActor () -> Void = {},
        isOnboardingCompleteProvider: (@MainActor () -> Bool)? = nil,
        openURL: (@MainActor (URL) -> Void)? = nil,
        openMicrophoneSystemSettings: @escaping @MainActor () -> Void = StatusItemController.defaultOpenMicrophoneSettings,
        openInputMonitoringSystemSettings: @escaping @MainActor () -> Void = StatusItemController.defaultOpenInputMonitoringSettings,
        inputDeviceProvider: (any AudioInputDeviceProviding)? = nil,
        modes: [ModeDescriptor] = ModeRegistry.all,
        setActiveMode: @escaping @MainActor (ModeDescriptor) async -> Void = { _ in },
        prequitHandler: @escaping @MainActor () async -> Void = {},
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.ui)
    ) {
        let onboardingCompletionPreference = Self.onboardingCompletionPreference(defaults: defaults)
        self.sceneModel = sceneModel
        self.appStore = appStore
        self.openHome = openHome
        self.openTranscriptions = openTranscriptions
        self.openSettings = openSettings
        self.openCopyLastTranscript = openCopyLastTranscript
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
        self.inputDeviceProvider = inputDeviceProvider ?? EmptyAudioInputDeviceProvider()
        self.modes = modes
        self.setActiveMode = setActiveMode
        self.prequitHandler = prequitHandler
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
        case .openHome:
            openHome()
        case .openTranscriptions:
            openTranscriptions()
        case .openSettings:
            openSettings()
        case .copyLastTranscript:
            openCopyLastTranscript()
        case .openMicrophoneSystemSettings:
            openURL(PermissionServiceAdapter.defaultSystemSettingsDeepLink(for: .microphone))
        case .openInputMonitoringSystemSettings:
            openURL(PermissionServiceAdapter.defaultSystemSettingsDeepLink(for: .inputMonitoring))
        case .quit:
            // Route through the prequit handler first so an in-flight
            // recording can tear down cleanly (e.g. restoring the system
            // mute state set by `SystemAudioMuter`) before the process
            // exits. Force-quit / crash / SIGKILL still leak — accepted
            // scope.
            Task { @MainActor in
                await prequitHandler()
                NSApplication.shared.terminate(nil)
            }
        case .selectAudioInputDevice:
            // Device rows route through `handleDeviceSelection(_:)`
            // directly — the deviceID payload is on the NSMenuItem,
            // not on the ActionID enum, so this switch case is
            // unreachable in normal use. Logging it instead of
            // silently ignoring catches future refactors that
            // mistakenly route here.
            logger.error("performMenuAction called for .selectAudioInputDevice; expected direct handleDeviceSelection path")
        case .selectMode:
            // Mode rows route through `handleModeSelection(_:)`
            // directly (same pattern as `.selectAudioInputDevice`).
            logger.error("performMenuAction called for .selectMode; expected direct handleModeSelection path")
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
            case .recording, .holdRecording, .transcribing:
                return .listening
            case .idle, .completed, .shortExit, .error:
                return .idle
            }
        }()

        if let image = StatusItemIconLoader.loadStatusBarIcon(pose: pose) {
            button.image = image
        }

        switch sessionState {
        case .recording, .holdRecording:
            button.contentTintColor = .systemRed
        case .transcribing:
            button.contentTintColor = .systemOrange
        case .idle, .completed, .shortExit, .error:
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
        // Re-query the provider on every rebuild so the submenu
        // reflects hotplug changes (USB mic plugged / unplugged)
        // without any observer plumbing.
        let inputDevices = inputDeviceProvider.availableDevices()
        let currentInputDeviceID = inputDeviceProvider.selectedDeviceID
        let model = StatusItemMenuModel.makeUnified(
            sessionState: snapshot.sessionState,
            micPermission: permissions[.microphone] ?? .pending,
            inputMonitoringPermission: permissions[.inputMonitoring] ?? .pending,
            activeModeName: snapshot.activeMode?.name,
            isOnboardingComplete: isOnboardingCompleteProvider(),
            inputDevices: inputDevices,
            currentInputDeviceID: currentInputDeviceID,
            modes: modes,
            currentModeID: snapshot.activeMode?.id
        )

        menu.removeAllItems()

        for item in model.items {
            switch item {
            case .separator:
                menu.addItem(.separator())
            case .header(let title, let iconName):
                let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                menuItem.isEnabled = false
                if let iconName {
                    menuItem.image = NSImage(
                        systemSymbolName: iconName,
                        accessibilityDescription: nil
                    )
                }
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
                if let iconName = action.iconName {
                    menuItem.image = NSImage(
                        systemSymbolName: iconName,
                        accessibilityDescription: nil
                    )
                }
                menu.addItem(menuItem)
            case .submenu(let title, let iconName, let children):
                let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                parent.isEnabled = true
                if let iconName {
                    parent.image = NSImage(
                        systemSymbolName: iconName,
                        accessibilityDescription: nil
                    )
                }
                let submenu = NSMenu(title: title)
                submenu.autoenablesItems = false
                for child in children {
                    let childItem = NSMenuItem()
                    childItem.title = child.title
                    childItem.state = child.isActive ? .on : .off
                    childItem.isEnabled = true
                    childItem.target = self
                    childItem.action = #selector(handleDeviceSelection(_:))
                    childItem.representedObject = child.deviceID
                    submenu.addItem(childItem)
                }
                parent.submenu = submenu
                menu.addItem(parent)
            case .modeSubmenu(let title, let iconName, let children):
                let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                parent.isEnabled = true
                if let iconName {
                    parent.image = NSImage(
                        systemSymbolName: iconName,
                        accessibilityDescription: nil
                    )
                }
                let submenu = NSMenu(title: title)
                submenu.autoenablesItems = false
                for child in children {
                    let childItem = NSMenuItem()
                    childItem.title = child.title
                    childItem.state = child.isActive ? .on : .off
                    childItem.isEnabled = true
                    childItem.target = self
                    childItem.action = #selector(handleModeSelection(_:))
                    childItem.representedObject = child.modeID
                    submenu.addItem(childItem)
                }
                parent.submenu = submenu
                menu.addItem(parent)
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

    /// Microphone-submenu device row handler. `representedObject`
    /// carries the `AudioInputDevice.id` string that we persist via
    /// `inputDeviceProvider.selectDevice(id:)`. We then rebuild the
    /// menu so the checkmark + parent title reflect the new selection
    /// on the next open (AppKit closes the menu after a click anyway,
    /// but rebuilding keeps the programmatic state in sync for
    /// whatever opens the menu next).
    @objc private func handleDeviceSelection(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? String else {
            logger.error("Device selection fired with unknown representedObject")
            return
        }
        inputDeviceProvider.selectDevice(id: deviceID)
        rebuildMenu()
    }

    /// Mode-submenu row handler (#068). `representedObject` carries the
    /// `ModeDescriptor.id` string; we resolve it back to the matching
    /// `ModeDescriptor` from `modes` and hand it to `setActiveMode`.
    /// The AppStore snapshot's `activeMode` flip then triggers
    /// `handleSnapshotChange` → `rebuildMenu`, which refreshes the
    /// checkmark and parent title.
    @objc private func handleModeSelection(_ sender: NSMenuItem) {
        guard let modeID = sender.representedObject as? String else {
            logger.error("Mode selection fired with unknown representedObject")
            return
        }
        guard let mode = modes.first(where: { $0.id == modeID }) else {
            logger.error("Mode selection fired for unknown modeID=\(modeID)")
            return
        }
        Task { @MainActor in
            await setActiveMode(mode)
        }
    }

    private func statusItemLabel(for sessionState: SessionState) -> String {
        switch sessionState {
        case .recording, .holdRecording:
            return "\(AppBrand.displayName) — recording"
        case .transcribing:
            return "\(AppBrand.displayName) — transcribing"
        case .idle, .completed, .shortExit, .error:
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
            key: "OnboardingCompleted",
            default: false,
            defaults: defaults
        )
    }
}

/// Default `AudioInputDeviceProviding` used when the controller is
/// constructed without an explicit provider — returns no devices so
/// the Microphone submenu is omitted entirely, matching the M5.2
/// layout. Production wiring in `PersonalScribeAppMain` injects the
/// live `AVFoundationInputDeviceProvider` from `PersonalScribeAudio`
/// instead. Tests that don't care about the submenu can rely on this
/// fallback without pulling AVFoundation into the test harness.
final class EmptyAudioInputDeviceProvider: AudioInputDeviceProviding, @unchecked Sendable {
    func availableDevices() -> [AudioInputDevice] { [] }
    var selectedDeviceID: String? { nil }
    func selectDevice(id: String?) {}
}
