import Foundation
import FluidAudio
import SeshatCore

protocol FluidAudioInferencing: Sendable {
    func loadModel(from directory: URL) async throws
    func transcribe(samples: [Float]) async throws -> FluidAudioInferenceResult
}

struct FluidAudioInferenceResult: Sendable, Equatable {
    let text: String
    let processingDuration: Duration
}

internal actor PrivateFluidAudioInferenceClient: FluidAudioInferencing {
    private let managerFactory: () -> AsrManager
    private var manager: AsrManager?

    init(
        managerFactory: @escaping () -> AsrManager = { AsrManager(config: .default) }
    ) {
        self.managerFactory = managerFactory
    }

    func loadModel(from directory: URL) async throws {
        let models = try await AsrModels.load(from: directory, version: .v2)
        try await resolvedManager().loadModels(models)
    }

    func transcribe(samples: [Float]) async throws -> FluidAudioInferenceResult {
        let result = try await resolvedManager().transcribe(samples, source: .microphone)
        return FluidAudioInferenceResult(
            text: result.text,
            processingDuration: .seconds(result.processingTime)
        )
    }

    private func resolvedManager() -> AsrManager {
        if let manager {
            return manager
        }

        let manager = managerFactory()
        self.manager = manager
        return manager
    }
}
