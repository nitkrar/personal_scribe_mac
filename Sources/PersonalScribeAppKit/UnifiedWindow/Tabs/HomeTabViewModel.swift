import Combine
import Foundation
import PersonalScribeCore

enum HomeChecklistItem: CaseIterable, Hashable, Sendable {
    case customizeShortcut
    case createMode
    case grantPermissions
    case downloadModel
    case tryShortcut

    var completionKey: String {
        switch self {
        case .customizeShortcut:
            "HomeChecklistCustomizeShortcutComplete"
        case .createMode:
            "HomeChecklistCreateModeComplete"
        case .grantPermissions:
            "HomeChecklistGrantPermissionsComplete"
        case .downloadModel:
            "HomeChecklistDownloadModelComplete"
        case .tryShortcut:
            "HomeChecklistTryShortcutComplete"
        }
    }

    var applicationKey: String {
        "\(completionKey)Applies"
    }

    var appliesByDefault: Bool {
        switch self {
        case .customizeShortcut, .createMode:
            true
        case .grantPermissions, .downloadModel, .tryShortcut:
            false
        }
    }

    var title: String {
        switch self {
        case .customizeShortcut:
            "Customize your shortcut"
        case .createMode:
            "Create a mode"
        case .grantPermissions:
            "Grant permissions"
        case .downloadModel:
            "Download a voice model"
        case .tryShortcut:
            "Try your shortcut"
        }
    }

    var subtitle: String {
        switch self {
        case .customizeShortcut:
            "Pick a key combo that suits you · Settings → Shortcuts"
        case .createMode:
            "Different formatting per app, e.g. email vs. code · Modes"
        case .grantPermissions:
            "Allow microphone recording and automatic paste · Settings"
        case .downloadModel:
            "Download an on-device model before your first dictation · Settings"
        case .tryShortcut:
            "Make a practice dictation with your configured shortcut"
        }
    }

    var navigationHint: String {
        switch self {
        case .customizeShortcut:
            "Opens Settings"
        case .createMode:
            "Opens Modes"
        case .grantPermissions, .downloadModel:
            "Opens Settings"
        case .tryShortcut:
            "Opens shortcut settings"
        }
    }
}

@MainActor
final class HomeChecklistState: ObservableObject {
    @Published private(set) var completedItems: Set<HomeChecklistItem>
    @Published private(set) var applicableItems: Set<HomeChecklistItem>
    @Published private(set) var isDismissed: Bool
    @Published private(set) var recordingHotkey: HotkeyPreference

    private let defaults: UserDefaults
    private let dismissedPreference: Preference<Bool>
    private var hotkeyObservation: NSObjectProtocol?
    private var customModesTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dismissedPreference = Preference(
            key: "HomeChecklistDismissed",
            default: false,
            defaults: defaults
        )

        let recordingHotkey = HotkeyPreference.resolve(from: defaults)
        self.recordingHotkey = recordingHotkey
        var completedItems = Set(
            HomeChecklistItem.allCases.filter { item in
                Self.completionPreference(for: item, defaults: defaults).resolve()
            }
        )
        if recordingHotkey != .default {
            completedItems.insert(.customizeShortcut)
            Self.completionPreference(
                for: .customizeShortcut,
                defaults: defaults
            ).persist(true)
        }
        self.completedItems = completedItems
        self.applicableItems = Set(
            HomeChecklistItem.allCases.filter { item in
                item.appliesByDefault
                    || Self.applicationPreference(for: item, defaults: defaults).resolve()
            }
        )
        self.isDismissed = dismissedPreference.resolve()

        hotkeyObservation = NotificationCenter.default.addObserver(
            forName: HotkeyPreference.didPersistNotification,
            object: defaults,
            queue: .main
        ) { [weak self] notification in
            guard let hotkey = notification.userInfo?[
                HotkeyPreference.notificationPreferenceKey
            ] as? HotkeyPreference else {
                return
            }
            MainActor.assumeIsolated {
                self?.applyHotkey(hotkey)
            }
        }
    }

    var pendingItems: [HomeChecklistItem] {
        HomeChecklistItem.allCases.filter {
            applicableItems.contains($0) && !completedItems.contains($0)
        }
    }

    var isVisible: Bool { !isDismissed && !pendingItems.isEmpty }

    func startObserving(customModes: AsyncStream<[WorkflowMode]>) {
        customModesTask?.cancel()
        customModesTask = Task { @MainActor [weak self] in
            for await modes in customModes where !modes.isEmpty {
                guard let self else {
                    return
                }
                self.complete(.createMode)
            }
        }
    }

    func refreshHotkey() {
        applyHotkey(HotkeyPreference.resolve(from: defaults))
    }

    private func applyHotkey(_ hotkey: HotkeyPreference) {
        recordingHotkey = hotkey
        if hotkey != .default {
            complete(.customizeShortcut)
        }
    }

    func dismiss() {
        isDismissed = true
        dismissedPreference.persist(true)
    }

    func complete(_ item: HomeChecklistItem) {
        guard completedItems.insert(item).inserted else {
            return
        }
        Self.completionPreference(for: item, defaults: defaults).persist(true)
    }

    func markApplicable(_ item: HomeChecklistItem) {
        guard applicableItems.insert(item).inserted else {
            return
        }
        Self.applicationPreference(for: item, defaults: defaults).persist(true)
    }

    func refreshSetupSatisfaction(
        permissionsGranted: Bool,
        modelDownloaded: Bool,
        shortcutTried: Bool
    ) {
        if permissionsGranted {
            complete(.grantPermissions)
        }
        if modelDownloaded {
            complete(.downloadModel)
        }
        if shortcutTried {
            complete(.tryShortcut)
        }
    }

    private static func completionPreference(
        for item: HomeChecklistItem,
        defaults: UserDefaults
    ) -> Preference<Bool> {
        Preference(key: item.completionKey, default: false, defaults: defaults)
    }

    private static func applicationPreference(
        for item: HomeChecklistItem,
        defaults: UserDefaults
    ) -> Preference<Bool> {
        Preference(key: item.applicationKey, default: false, defaults: defaults)
    }

    isolated deinit {
        if let hotkeyObservation {
            NotificationCenter.default.removeObserver(hotkeyObservation)
        }
        customModesTask?.cancel()
    }
}

/// Presents Home metrics, pending setup items, hotkey hints, and navigation actions.
@MainActor
public final class HomeTabViewModel: ObservableObject {
    public let metrics: MetricsSnapshotStore
    let checklist: HomeChecklistState

    private let openShortcuts: @MainActor () -> Void
    private let openModes: @MainActor () -> Void
    private let openPermissions: @MainActor () -> Void
    private let openModels: @MainActor () -> Void
    private let openTryShortcut: @MainActor () -> Void
    private let setupFlow: SetupFlowState?
    private var setupFlowObservation: AnyCancellable?

    public convenience init(
        metrics: MetricsSnapshotStore,
        defaults: UserDefaults = .standard,
        openShortcuts: @escaping @MainActor () -> Void = {},
        openModes: @escaping @MainActor () -> Void = {}
    ) {
        self.init(
            metrics: metrics,
            defaults: defaults,
            checklist: nil,
            setupFlow: nil,
            openShortcuts: openShortcuts,
            openModes: openModes,
            openPermissions: openShortcuts,
            openModels: openShortcuts,
            openTryShortcut: openShortcuts
        )
    }

    init(
        metrics: MetricsSnapshotStore,
        defaults: UserDefaults = .standard,
        checklist: HomeChecklistState? = nil,
        setupFlow: SetupFlowState? = nil,
        openShortcuts: @escaping @MainActor () -> Void = {},
        openModes: @escaping @MainActor () -> Void = {},
        openPermissions: @escaping @MainActor () -> Void = {},
        openModels: @escaping @MainActor () -> Void = {},
        openTryShortcut: @escaping @MainActor () -> Void = {}
    ) {
        self.metrics = metrics
        self.openShortcuts = openShortcuts
        self.openModes = openModes
        self.openPermissions = openPermissions
        self.openModels = openModels
        self.openTryShortcut = openTryShortcut
        self.checklist = checklist ?? HomeChecklistState(defaults: defaults)
        self.setupFlow = setupFlow
        setupFlowObservation = setupFlow?.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var isCompletionBannerVisible: Bool {
        setupFlow?.isCompletionBannerVisible == true
    }

    func dismissCompletionBanner() {
        setupFlow?.dismissCompletionBanner()
    }

    public var emptyStateHotkeyHint: String {
        HotkeyShortcutFormatter.displayString(for: checklist.recordingHotkey)
    }

    public func refreshHotkey() {
        checklist.refreshHotkey()
    }

    func performChecklistAction(for item: HomeChecklistItem) {
        switch item {
        case .customizeShortcut:
            openShortcuts()
        case .createMode:
            openModes()
        case .grantPermissions:
            openPermissions()
        case .downloadModel:
            openModels()
        case .tryShortcut:
            openTryShortcut()
        }
    }
}
