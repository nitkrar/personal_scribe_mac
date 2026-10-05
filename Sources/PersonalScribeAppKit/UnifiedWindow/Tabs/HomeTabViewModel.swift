import Combine
import Foundation
import PersonalScribeCore

enum HomeChecklistItem: CaseIterable, Hashable, Sendable {
    case startRecording
    case customizeShortcut
    case createMode
}

@MainActor
final class HomeChecklistState: ObservableObject {
    @Published private(set) var completedItems: Set<HomeChecklistItem>
    @Published private(set) var isDismissed: Bool
    @Published private(set) var recordingHotkey: HotkeyPreference

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let startRecordingPreference: Preference<Bool>
    private let customizeShortcutPreference: Preference<Bool>
    private let createModePreference: Preference<Bool>
    private let dismissedPreference: Preference<Bool>
    private var hotkeyObservation: NSObjectProtocol?
    private var metricsObservation: AnyCancellable?
    private var customModesTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        startRecordingPreference = Preference(
            key: "HomeChecklistStartRecordingComplete",
            default: false,
            defaults: defaults
        )
        customizeShortcutPreference = Preference(
            key: "HomeChecklistCustomizeShortcutComplete",
            default: false,
            defaults: defaults
        )
        createModePreference = Preference(
            key: "HomeChecklistCreateModeComplete",
            default: false,
            defaults: defaults
        )
        dismissedPreference = Preference(
            key: "HomeChecklistDismissed",
            default: false,
            defaults: defaults
        )

        let recordingHotkey = HotkeyPreference.resolve(from: defaults)
        self.recordingHotkey = recordingHotkey
        var completedItems: Set<HomeChecklistItem> = []
        if startRecordingPreference.resolve() {
            completedItems.insert(.startRecording)
        }
        if customizeShortcutPreference.resolve() {
            completedItems.insert(.customizeShortcut)
        }
        if createModePreference.resolve() {
            completedItems.insert(.createMode)
        }
        if recordingHotkey != .default {
            completedItems.insert(.customizeShortcut)
            customizeShortcutPreference.persist(true)
        }
        self.completedItems = completedItems
        self.isDismissed = dismissedPreference.resolve()

        hotkeyObservation = notificationCenter.addObserver(
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

    var completedCount: Int { completedItems.count }
    var isComplete: Bool { completedCount == HomeChecklistItem.allCases.count }
    var isVisible: Bool { !isDismissed }

    func startObserving(
        metrics: MetricsSnapshotStore,
        customModes: AsyncStream<[WorkflowMode]>
    ) {
        metricsObservation = metrics.$recentTranscriptions.sink { [weak self] entries in
            guard let self, !entries.isEmpty else {
                return
            }
            self.earn(.startRecording, preference: self.startRecordingPreference)
        }
        customModesTask?.cancel()
        customModesTask = Task { @MainActor [weak self] in
            for await modes in customModes where !modes.isEmpty {
                guard let self else {
                    return
                }
                self.earn(.createMode, preference: self.createModePreference)
            }
        }
    }

    func refreshHotkey() {
        applyHotkey(HotkeyPreference.resolve(from: defaults))
    }

    private func applyHotkey(_ hotkey: HotkeyPreference) {
        recordingHotkey = hotkey
        if hotkey != .default {
            earn(.customizeShortcut, preference: customizeShortcutPreference)
        }
    }

    func update(
        hasTranscript: Bool,
        hasCustomHotkey: Bool,
        hasCustomMode: Bool
    ) {
        if hasTranscript {
            earn(.startRecording, preference: startRecordingPreference)
        }
        if hasCustomHotkey {
            earn(.customizeShortcut, preference: customizeShortcutPreference)
        }
        if hasCustomMode {
            earn(.createMode, preference: createModePreference)
        }
    }

    func dismiss() {
        guard isComplete else {
            return
        }
        isDismissed = true
        dismissedPreference.persist(true)
    }

    private func earn(_ item: HomeChecklistItem, preference: Preference<Bool>) {
        guard completedItems.insert(item).inserted else {
            return
        }
        preference.persist(true)
    }

    isolated deinit {
        if let hotkeyObservation {
            notificationCenter.removeObserver(hotkeyObservation)
        }
        customModesTask?.cancel()
    }
}

/// Presents Home metrics, checklist progress, hotkey hints, and navigation actions.
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
        case .startRecording:
            break
        case .customizeShortcut:
            openShortcuts()
        case .createMode:
            openModes()
        }
    }
}
