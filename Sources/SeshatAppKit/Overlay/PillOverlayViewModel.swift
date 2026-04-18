import Combine
import Foundation
import SeshatCore

@MainActor
public final class PillOverlayViewModel: ObservableObject {
    public enum Visibility: Equatable, Sendable {
        case hidden
        case idle
        case recording
        case transcribing
    }

    @Published public private(set) var visibility: Visibility = .idle

    public init() {}

    /// Update from a SessionState. Maps:
    ///   .idle          -> .idle (shows compact shortcut-hint pill)
    ///   .recording     -> .recording
    ///   .transcribing  -> .transcribing
    ///   .error         -> .hidden
    public func apply(sessionState: SessionState) {
        switch sessionState {
        case .idle:
            visibility = .idle
        case .recording:
            visibility = .recording
        case .transcribing:
            visibility = .transcribing
        case .error:
            visibility = .hidden
        }
    }
}
