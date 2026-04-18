import Combine
import Foundation
import SeshatCore

@MainActor
public final class PillOverlayViewModel: ObservableObject {
    public enum Visibility: Equatable, Sendable {
        case hidden
        case recording
        case transcribing
    }

    @Published public private(set) var visibility: Visibility = .hidden

    public init() {}

    /// Update from a SessionState. Maps:
    ///   .idle / .error -> .hidden
    ///   .recording    -> .recording
    ///   .transcribing -> .transcribing
    public func apply(sessionState: SessionState) {
        visibility = .hidden
    }
}
