import Combine
import Foundation

@MainActor
public protocol ModelService: ObservableObject, Sendable {
    var registeredModels: [ModelDescriptor] { get }
    var activeDescriptor: ActiveModelDescriptor { get }

    func descriptor(for mode: ModeDescriptor) -> ActiveModelDescriptor
    func setActive(_ descriptor: ActiveModelDescriptor) async throws
    func setActiveVoiceModel(_ id: String) async throws
    func isDownloaded(_ descriptor: ModelDescriptor) -> Bool
    func download(
        _ descriptor: ModelDescriptor,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws
}
