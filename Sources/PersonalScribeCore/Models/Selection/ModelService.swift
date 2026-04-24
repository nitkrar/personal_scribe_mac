import Combine
import Foundation

@MainActor
public protocol ModelService: ObservableObject, Sendable {
    var registeredModels: [ModelDescriptor] { get }
    var activeDescriptor: ActiveModelDescriptor { get }

    /// UI-facing per-descriptor readiness/download snapshot.
    ///
    /// Keyed by `ModelDescriptor.id`. Conformers publish updates
    /// (`@Published`) so SwiftUI observers refresh when a descriptor moves
    /// through `.notDownloaded → .downloading → .loading → .ready` or
    /// transitions to `.failed`.
    ///
    /// Defaults to an empty dictionary so existing conformers continue to
    /// compile without behavioral change; they can opt in when they need
    /// to surface state.
    var downloadStates: [String: ModelDownloadState] { get }

    func descriptor(for mode: ModeDescriptor) -> ActiveModelDescriptor
    func setActive(_ descriptor: ActiveModelDescriptor) async throws
    func setActiveVoiceModel(_ id: String) async throws
    func isDownloaded(_ descriptor: ModelDescriptor) -> Bool
    func download(_ descriptor: ModelDescriptor) async throws
}

extension ModelService {
    public var downloadStates: [String: ModelDownloadState] { [:] }
}
