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

    private let startRecordingPreference: Preference<Bool>
    private let customizeShortcutPreference: Preference<Bool>
    private let createModePreference: Preference<Bool>
    private let dismissedPreference: Preference<Bool>

    init(defaults: UserDefaults = .standard) {
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
        self.completedItems = completedItems
        self.isDismissed = dismissedPreference.resolve()
    }

    var completedCount: Int { completedItems.count }
    var isComplete: Bool { completedCount == HomeChecklistItem.allCases.count }
    var isVisible: Bool { !isDismissed }

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
}

/// View model for the unified-window Home tab. Stats and recents come from
/// the shared `MetricsSnapshotStore`; this adds the empty-state hotkey hint.
@MainActor
public final class HomeTabViewModel: ObservableObject {
    public let metrics: MetricsSnapshotStore
    let checklist: HomeChecklistState

    @Published public private(set) var recordingHotkey: HotkeyPreference

    private let defaults: UserDefaults
    private let hasCustomModes: @MainActor () -> Bool
    private let openShortcuts: @MainActor () -> Void
    private let openModes: @MainActor () -> Void

    public init(
        metrics: MetricsSnapshotStore,
        defaults: UserDefaults = .standard,
        hasCustomModes: @escaping @MainActor () -> Bool = { false },
        openShortcuts: @escaping @MainActor () -> Void = {},
        openModes: @escaping @MainActor () -> Void = {}
    ) {
        self.metrics = metrics
        self.defaults = defaults
        self.hasCustomModes = hasCustomModes
        self.openShortcuts = openShortcuts
        self.openModes = openModes
        self.checklist = HomeChecklistState(defaults: defaults)
        self.recordingHotkey = HotkeyPreference.resolve(from: defaults)
    }

    public var emptyStateHotkeyHint: String {
        HotkeyShortcutFormatter.displayString(for: recordingHotkey)
    }

    public func refreshHotkey() {
        recordingHotkey = HotkeyPreference.resolve(from: defaults)
    }

    func refreshChecklist() {
        checklist.update(
            hasTranscript: !metrics.recentTranscriptions.isEmpty,
            hasCustomHotkey: recordingHotkey != .default,
            hasCustomMode: hasCustomModes()
        )
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
