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
    private let manager = AsrManager(config: .default)

    func loadModel(from directory: URL) async throws {
        let models = try await AsrModels.load(from: directory, version: .v2)
        try await manager.loadModels(models)
    }

    func transcribe(samples: [Float]) async throws -> FluidAudioInferenceResult {
        let result = try await manager.transcribe(samples, source: .microphone)
        return FluidAudioInferenceResult(
            text: result.text,
            processingDuration: .seconds(result.processingTime)
        )
    }
}
