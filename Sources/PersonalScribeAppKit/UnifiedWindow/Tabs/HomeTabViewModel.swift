import Combine
import Foundation
import PersonalScribeCore

enum HomeChecklistItem: CaseIterable, Hashable, Sendable {
    case customizeShortcut
    case createMode

    var completionKey: String {
        switch self {
        case .customizeShortcut:
            "HomeChecklistCustomizeShortcutComplete"
        case .createMode:
            "HomeChecklistCreateModeComplete"
        }
    }

    var title: String {
        switch self {
        case .customizeShortcut:
            "Customize your shortcut"
        case .createMode:
            "Create a mode"
        }
    }

    var subtitle: String {
        switch self {
        case .customizeShortcut:
            "Pick a key combo that suits you · Settings → Shortcuts"
        case .createMode:
            "Different formatting per app, e.g. email vs. code · Modes"
        }
    }

    var navigationHint: String {
        switch self {
        case .customizeShortcut:
            "Opens Settings"
        case .createMode:
            "Opens Modes"
        }
    }
}

@MainActor
final class HomeChecklistState: ObservableObject {
    @Published private(set) var completedItems: Set<HomeChecklistItem>
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
        HomeChecklistItem.allCases.filter { !completedItems.contains($0) }
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

    private static func completionPreference(
        for item: HomeChecklistItem,
        defaults: UserDefaults
    ) -> Preference<Bool> {
        Preference(key: item.completionKey, default: false, defaults: defaults)
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
            openShortcuts: openShortcuts,
            openModes: openModes
        )
    }

    init(
        metrics: MetricsSnapshotStore,
        defaults: UserDefaults = .standard,
        checklist: HomeChecklistState? = nil,
        openShortcuts: @escaping @MainActor () -> Void = {},
        openModes: @escaping @MainActor () -> Void = {}
    ) {
        self.metrics = metrics
        self.openShortcuts = openShortcuts
        self.openModes = openModes
        self.checklist = checklist ?? HomeChecklistState(defaults: defaults)
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
        }
    }
}
