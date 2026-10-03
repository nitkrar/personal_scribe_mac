import Foundation
import PersonalScribeCore

/// View model for the unified-window Home tab. Stats and recents come from
/// the shared `MetricsSnapshotStore`; this adds the empty-state hotkey hint.
@MainActor
public final class HomeTabViewModel: ObservableObject {
    public let metrics: MetricsSnapshotStore

    @Published public private(set) var recordingHotkey: HotkeyPreference

    private let defaults: UserDefaults

    public init(metrics: MetricsSnapshotStore, defaults: UserDefaults = .standard) {
        self.metrics = metrics
        self.defaults = defaults
        self.recordingHotkey = HotkeyPreference.resolve(from: defaults)
    }

    public var emptyStateHotkeyHint: String {
        HotkeyShortcutFormatter.displayString(for: recordingHotkey)
    }

    public func refreshHotkey() {
        recordingHotkey = HotkeyPreference.resolve(from: defaults)
    }
}
