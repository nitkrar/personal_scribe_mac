import Foundation
import PersonalScribeCore

/// Content the persistent ResponseCard should display, plus an optional
/// link region the consumer can make tappable. Emitted by
/// `RecordingStatusCardDriver.statusContent(...)` as a single value type
/// so the `text` and `link` are always in lock-step (no accidental
/// link-range against a stale text).
public struct StatusCardContent: Sendable, Equatable {
    public let text: String
    public let link: StatusCardLink?

    public init(text: String, link: StatusCardLink? = nil) {
        self.text = text
        self.link = link
    }
}

/// A tappable substring inside a `StatusCardContent`. `range` is a
/// `String.Index` range into the owning content's `text` and must be
/// treated as immutable alongside the text.
public struct StatusCardLink: Sendable, Equatable {
    public let range: Range<String.Index>
    public let action: StatusCardLinkAction

    public init(range: Range<String.Index>, action: StatusCardLinkAction) {
        self.range = range
        self.action = action
    }
}

/// Actions a status-card link tap can trigger. The AppKit layer routes
/// these through caller-supplied closures; the driver stays pure.
public enum StatusCardLinkAction: Sendable, Equatable {
    case openVadSettings
}

/// Pure state machine that turns the current `SessionState` +
/// `ModelDownloadProgress` + VAD grace/fire-token state into the text
/// (and optional link) the persistent ResponseCard should show, or
/// `nil` if the card should be hidden.
///
/// Kept as a free-standing pure function so wiring in
/// `PillOverlayController` stays trivially testable and the UX strings
/// are pinned by tests.
enum RecordingStatusCardDriver {
    /// Stage B (#046) priority-ordered driver. First non-nil branch wins:
    ///
    /// 1. `.error` state — error description, no link.
    /// 2. VAD grace pending + pref on — "…stopping, speak to continue".
    /// 3. VAD fire-token present, not yet seen by consumer, + notify pref
    ///    on — "Auto stopped. Update settings to change." with a link on
    ///    the trailing substring.
    /// 4. Record-without-transcribe messaging (Stage A) — falls through
    ///    to `statusText(sessionState:progress:)` wrapped as plain text.
    /// 5. `nil` — hide the card.
    static func statusContent(
        sessionState: SessionState,
        progress: ModelDownloadProgress?,
        vadGracePending: Bool,
        vadFireToken: UUID?,
        vadLastSeenFireToken: UUID?,
        showStoppingWarning: Bool,
        showAutoStoppedNotification: Bool
    ) -> StatusCardContent? {
        // 1. Error overrides every VAD state.
        if case let .error(err) = sessionState {
            return StatusCardContent(
                text: err.errorDescription ?? String(describing: err),
                link: nil
            )
        }

        // 2. Grace-window warning, gated by pref.
        if vadGracePending && showStoppingWarning {
            return StatusCardContent(
                text: Self.warningText,
                link: nil
            )
        }

        // 3. Auto-stopped notification, gated by pref AND an unseen fire
        //    token. Consumer caches `lastSeenFireToken` locally and
        //    advances it after rendering, so a stable token only triggers
        //    the notification once.
        if let token = vadFireToken,
           token != vadLastSeenFireToken,
           showAutoStoppedNotification {
            let text = Self.notificationText
            let linkSubstring = Self.notificationLinkSubstring
            if let range = text.range(of: linkSubstring) {
                return StatusCardContent(
                    text: text,
                    link: StatusCardLink(range: range, action: .openVadSettings)
                )
            } else {
                // Defensive — text + substring are string literals in the
                // same file, so the range should always exist. If a
                // future edit desyncs them, fall back to a link-less
                // notification rather than crash.
                return StatusCardContent(text: text, link: nil)
            }
        }

        // 4. Existing record-without-transcribe messaging wins if there
        //    is any.
        if let text = statusText(sessionState: sessionState, progress: progress) {
            return StatusCardContent(text: text, link: nil)
        }

        // 5. Nothing to show.
        return nil
    }

    /// Legacy entry point preserved for callers that don't need VAD
    /// state. Returns just the record-without-transcribe text (Stage A
    /// behavior) or `nil`. Stage B callers should use `statusContent`.
    static func statusText(
        sessionState: SessionState,
        progress: ModelDownloadProgress?
    ) -> String? {
        guard let progress else {
            return nil
        }

        switch sessionState {
        case .recording, .holdRecording:
            return recordingMessage(for: progress)
        case .transcribing:
            return transcribingMessage(for: progress)
        case .idle, .completed, .error:
            return nil
        }
    }

    // MARK: - Fixed strings

    static let warningText = "…stopping, speak to continue"
    static let notificationText = "Auto stopped. Update settings to change."
    static let notificationLinkSubstring = "Update settings to change"

    // MARK: - Record-without-transcribe helpers (Stage A)

    private static func recordingMessage(for progress: ModelDownloadProgress) -> String? {
        switch progress.phase {
        case .downloading:
            let percent = Int((progress.fractionCompleted * 100).rounded())
            return "Recording — transcribing when model is ready (\(percent)%)"
        case .loading:
            return "Recording — model loading, transcription starts shortly"
        case .idle, .finished:
            return nil
        }
    }

    private static func transcribingMessage(for progress: ModelDownloadProgress) -> String? {
        switch progress.phase {
        case .downloading:
            let percent = Int((progress.fractionCompleted * 100).rounded())
            return "Waiting — finishing model download (\(percent)%)"
        case .loading:
            return "Waiting — model loading"
        case .idle, .finished:
            return nil
        }
    }
}
