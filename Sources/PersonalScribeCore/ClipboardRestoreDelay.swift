import Foundation

/// Delay between `ClipboardBatchOutput` writing the transcript to the
/// pasteboard and the scheduled restore of the user's pre-transcript
/// clipboard contents. Only consulted when
/// `ClipboardRestoreEnabledPreference` resolves to `true`.
///
/// UserDefaults key is intentionally `PasteRestoreDelaySeconds` (its
/// pre-#072 name) so existing persisted values migrate without a data
/// loss. Users who never touched the slider inherit the new 3.0s default.
///
/// Range 0.1–10.0s. Default bumped from 0.5s (pre-#072) to 3.0s — short
/// enough that restore still happens during a typical paste flow, long
/// enough that manually pressing `Cmd+V` in a second text field after a
/// cursorless first paste still gets the transcript instead of the
/// restored clipboard.
public struct ClipboardRestoreDelay: Sendable, Equatable {
    public let seconds: TimeInterval

    public static let `default`: ClipboardRestoreDelay = .init(seconds: 3.0)
    public static let userDefaultsKey = "PasteRestoreDelaySeconds"

    public static let minimumSeconds: TimeInterval = 0.1
    public static let maximumSeconds: TimeInterval = 10.0

    public init(seconds: TimeInterval) {
        self.seconds = seconds
    }

    public static func storedSeconds(
        defaults: UserDefaults = .standard
    ) -> Preference<TimeInterval> {
        Preference(key: userDefaultsKey, default: Self.default.seconds, defaults: defaults)
    }

    public static func resolve(from defaults: UserDefaults = .standard) -> ClipboardRestoreDelay {
        ClipboardRestoreDelay(seconds: sanitizedSeconds(storedSeconds(defaults: defaults).resolve()))
    }

    public static func persist(
        to defaults: UserDefaults = .standard,
        _ delay: ClipboardRestoreDelay
    ) {
        storedSeconds(defaults: defaults).persist(sanitizedSeconds(delay.seconds))
    }

    private static func sanitizedSeconds(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else {
            return `default`.seconds
        }
        return clamp(seconds)
    }

    private static func clamp(_ seconds: TimeInterval) -> TimeInterval {
        max(minimumSeconds, min(seconds, maximumSeconds))
    }
}
