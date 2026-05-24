import Foundation

enum PasteFailureReason: String, Sendable {
    case noTargetCursor
    case pidProbeRejected
    case pasteboardWriteFailed
    case eventPostFailed
    case accessibilityNotTrusted
    case other
}

struct PasteSessionAccumulator: Sendable {
    enum SinkKind: String, Sendable {
        case live
        case batch
    }

    private let now: @Sendable () -> Date

    private(set) var livePasteAttempts = 0
    private(set) var livePasteSucceeded = 0
    private(set) var livePasteFailed = 0
    private(set) var livePasteSkipped = 0
    private(set) var livePasteCumulativeCharsWritten = 0
    private(set) var finalPasteAttempted = false
    private(set) var finalPasteSucceeded = false
    private(set) var finalPasteCharsWritten = 0
    private(set) var finalPasteFailureReason: PasteFailureReason?
    private(set) var finalPasteSkipped = false
    private(set) var targetAppPID: pid_t?
    private(set) var targetAppBundleID: String?
    private(set) var lastFailureReason: PasteFailureReason?
    private(set) var startedAt: Date?

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    mutating func startedSession() {
        startedAt = now()
    }

    mutating func recordLiveAttempt(chars: Int) {
        guard chars > 0 else { return }
        livePasteAttempts += 1
    }

    mutating func recordLiveClipboardWrite(chars: Int) {
        guard chars > 0 else { return }
        livePasteCumulativeCharsWritten += chars
    }

    mutating func recordLiveSucceeded(chars: Int) {
        guard chars > 0 else { return }
        livePasteSucceeded += 1
        livePasteCumulativeCharsWritten += chars
    }

    mutating func recordLiveFailed(reason: PasteFailureReason) {
        livePasteFailed += 1
        lastFailureReason = reason
    }

    mutating func recordLiveSkipped() {
        livePasteSkipped += 1
    }

    mutating func recordFinalAttempted(chars _: Int) {
        finalPasteAttempted = true
    }

    mutating func recordFinalClipboardWrite(chars: Int) {
        guard chars > 0 else { return }
        finalPasteCharsWritten = chars
    }

    mutating func recordFinalClipboardOnlyDelivery(chars: Int) {
        finalPasteAttempted = true
        finalPasteSucceeded = false
        finalPasteSkipped = true
        finalPasteFailureReason = nil
        lastFailureReason = nil
        if chars > 0 {
            finalPasteCharsWritten = chars
        }
    }

    mutating func recordFinalSucceeded(chars: Int) {
        finalPasteSkipped = false
        finalPasteSucceeded = true
        finalPasteFailureReason = nil
        lastFailureReason = nil
        if chars > 0 {
            finalPasteCharsWritten = chars
        }
    }

    mutating func recordFinalFailed(reason: PasteFailureReason) {
        finalPasteSkipped = false
        finalPasteSucceeded = false
        finalPasteFailureReason = reason
        lastFailureReason = reason
    }

    mutating func recordTarget(pid: pid_t?, bundleID: String?) {
        targetAppPID = pid
        targetAppBundleID = bundleID
    }

    func summary(sink: SinkKind, sessionID: String) -> PasteSessionSummary {
        PasteSessionSummary(
            sink: sink,
            sessionID: sessionID,
            livePasteAttempts: livePasteAttempts,
            livePasteSucceeded: livePasteSucceeded,
            livePasteFailed: livePasteFailed,
            livePasteSkipped: livePasteSkipped,
            livePasteCumulativeCharsWritten: livePasteCumulativeCharsWritten,
            finalPasteAttempted: finalPasteAttempted,
            finalPasteSucceeded: finalPasteSucceeded,
            finalPasteCharsWritten: finalPasteCharsWritten,
            finalPasteFailureReason: finalPasteFailureReason,
            finalPasteSkipped: finalPasteSkipped,
            targetAppPID: targetAppPID,
            targetAppBundleID: targetAppBundleID,
            totalDurationMs: totalDurationMs()
        )
    }

    private func totalDurationMs() -> Int {
        guard let startedAt else {
            return 0
        }

        let durationMs = now().timeIntervalSince(startedAt) * 1_000
        return max(0, Int(durationMs.rounded()))
    }
}

struct PasteSessionSummary: Sendable, Equatable {
    let sink: PasteSessionAccumulator.SinkKind
    let sessionID: String
    let livePasteAttempts: Int
    let livePasteSucceeded: Int
    let livePasteFailed: Int
    let livePasteSkipped: Int
    let livePasteCumulativeCharsWritten: Int
    let finalPasteAttempted: Bool
    let finalPasteSucceeded: Bool
    let finalPasteCharsWritten: Int
    let finalPasteFailureReason: PasteFailureReason?
    let finalPasteSkipped: Bool
    let targetAppPID: pid_t?
    let targetAppBundleID: String?
    let totalDurationMs: Int

    func formatLogLine() -> String {
        let failureReason = finalPasteFailureReason?.rawValue ?? "nil"
        let targetAppPID = targetAppPID.map(String.init) ?? "nil"
        let targetAppBundleID = targetAppBundleID ?? "nil"

        return "paste_session_summary — sink=\(sink.rawValue) sessionID=\(sessionID) livePasteAttempts=\(livePasteAttempts) livePasteSucceeded=\(livePasteSucceeded) livePasteFailed=\(livePasteFailed) livePasteSkipped=\(livePasteSkipped) livePasteCumulativeCharsWritten=\(livePasteCumulativeCharsWritten) finalPasteAttempted=\(finalPasteAttempted) finalPasteSucceeded=\(finalPasteSucceeded) finalPasteCharsWritten=\(finalPasteCharsWritten) finalPasteFailureReason=\(failureReason) finalPasteSkipped=\(finalPasteSkipped) targetAppPID=\(targetAppPID) targetAppBundleID=\(targetAppBundleID) totalDurationMs=\(totalDurationMs)"
    }
}
