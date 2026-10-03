/// Per-mode transcript cleanup level. `.off` delivers the transcriber's text untouched.
public enum TranscriptCleanup: String, Codable, CaseIterable, Sendable {
    case off
    case standard
}
