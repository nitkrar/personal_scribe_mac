import Combine
import Foundation
import SeshatCore

@MainActor
public final class PillOverlayViewModel: ObservableObject {
    public enum Visibility: Equatable, Sendable {
        case hidden
        case downloading(fractionCompleted: Double)
        case recording
        case transcribing
    }

    @Published public private(set) var visibility: Visibility = .hidden

    public init() {}

    /// Combined mapping from session state + download progress. Download state
    /// takes priority so the user sees a determinate download pill instead of a
    /// generic "Transcribing…" spinner when the model isn't ready yet.
    public func apply(
        sessionState: SessionState,
        downloadProgress: ModelDownloadProgress?
    ) {
        if let downloadProgress, downloadProgress.phase == .downloading {
            visibility = .downloading(fractionCompleted: downloadProgress.fractionCompleted)
            return
        }

        switch sessionState {
        case .idle:
            visibility = .hidden
        case .recording:
            visibility = .recording
        case .transcribing:
            visibility = .transcribing
        case .error:
            visibility = .hidden
        }
    }
}
