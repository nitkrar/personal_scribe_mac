import Foundation

/// Mutes the Mac's system audio output at recording start and restores it
/// at recording stop. Prevents speaker → mic bleed from polluting the
/// transcript without adding AEC or per-device CoreAudio management.
///
/// Production closures drive the same flag the F10 mute key writes via
/// `NSAppleScript` (`set volume output muted ...`) — a system-level flag
/// that is route-independent and covers media, alerts, and notifications
/// in one call. Tests inject fake closures to assert call sequences
/// without invoking AppleScript.
///
/// Failure policy:
/// - `read` returning `nil` (couldn't determine prior state) skips mute
///   entirely. Safer than caching `false` and unmuting a pre-muted
///   machine at stop.
/// - `write` failures are silent. The user's ears are the feedback
///   channel — if mute didn't land, they hear audio continuing.
public struct SystemAudioMuter: Sendable {
    public typealias ReadMuted = @Sendable () -> Bool?
    public typealias WriteMuted = @Sendable (Bool) -> Void

    private var priorMuted: Bool?
    private let read: ReadMuted
    private let write: WriteMuted

    public init(
        read: @escaping ReadMuted = Self.defaultRead,
        write: @escaping WriteMuted = Self.defaultWrite
    ) {
        self.read = read
        self.write = write
    }

    public mutating func muteIfNeeded() {
        guard priorMuted == nil else { return }
        guard let prior = read() else { return }
        priorMuted = prior
        write(true)
    }

    public mutating func restoreIfNeeded() {
        guard let prior = priorMuted else { return }
        write(prior)
        priorMuted = nil
    }

    public static let defaultRead: ReadMuted = {
        guard let script = NSAppleScript(source: "output muted of (get volume settings)") else {
            return nil
        }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        return error == nil ? descriptor.booleanValue : nil
    }

    public static let defaultWrite: WriteMuted = { muted in
        guard let script = NSAppleScript(source: "set volume output muted \(muted)") else {
            return
        }
        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
    }
}
