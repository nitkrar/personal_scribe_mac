import Foundation
import SeshatCore

protocol FluidAudioInferencing: Sendable {
    func loadModel(from directory: URL) async throws
    func transcribe(samples: [Float]) async throws -> FluidAudioInferenceResult
}

struct FluidAudioInferenceResult: Sendable, Equatable {
    let text: String
    let processingDuration: Duration
}

private struct PrivateFluidAudioInferenceClient: FluidAudioInferencing {
    func loadModel(from directory: URL) async throws {
        _ = directory
        fatalError("step 7+")
    }

    func transcribe(samples: [Float]) async throws -> FluidAudioInferenceResult {
        _ = samples
        fatalError("step 11+")
    }
}
