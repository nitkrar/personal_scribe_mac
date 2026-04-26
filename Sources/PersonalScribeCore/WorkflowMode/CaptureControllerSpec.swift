import Foundation

/// Recipe-level declaration of a capture controller (#078 L20). A
/// capture controller signals "stop now" to the orchestrator —
/// examples are VAD's silence-end fire and the manual hotkey release.
///
/// Cases:
/// - `.vad(silenceThreshold:showWarning:showAutoStoppedNotification:)`
///   — voice-activity-detection auto-stop. Each parameter is a
///   `Parameter<Value>` (`.setting` references a global preference;
///   `.override` forces a per-mode value). Maps to today's
///   `VadAutoStopController` after Phase G cutover.
/// - `.manualHotkey` — the press-to-talk / hold-to-record hotkey path.
///   No parameters; the hotkey binding itself is a global preference
///   (`HotkeyPreference`) read independently by the AppKit layer.
public enum CaptureControllerSpec: Codable, Equatable, Sendable {
    case vad(
        silenceThreshold: Parameter<TimeInterval>,
        showWarning: Parameter<Bool>,
        showAutoStoppedNotification: Parameter<Bool>
    )
    case manualHotkey

    private enum Discriminator: String, Codable {
        case vad
        case manualHotkey
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case silenceThreshold
        case showWarning
        case showAutoStoppedNotification
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Discriminator.self, forKey: .type)
        switch type {
        case .vad:
            let silenceThreshold = try container.decode(
                Parameter<TimeInterval>.self,
                forKey: .silenceThreshold
            )
            let showWarning = try container.decode(
                Parameter<Bool>.self,
                forKey: .showWarning
            )
            let showAutoStoppedNotification = try container.decode(
                Parameter<Bool>.self,
                forKey: .showAutoStoppedNotification
            )
            self = .vad(
                silenceThreshold: silenceThreshold,
                showWarning: showWarning,
                showAutoStoppedNotification: showAutoStoppedNotification
            )
        case .manualHotkey:
            self = .manualHotkey
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .vad(let silenceThreshold, let showWarning, let showAutoStoppedNotification):
            try container.encode(Discriminator.vad, forKey: .type)
            try container.encode(silenceThreshold, forKey: .silenceThreshold)
            try container.encode(showWarning, forKey: .showWarning)
            try container.encode(
                showAutoStoppedNotification,
                forKey: .showAutoStoppedNotification
            )
        case .manualHotkey:
            try container.encode(Discriminator.manualHotkey, forKey: .type)
        }
    }
}
