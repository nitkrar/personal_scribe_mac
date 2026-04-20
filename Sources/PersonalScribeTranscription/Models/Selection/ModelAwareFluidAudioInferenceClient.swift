import FluidAudio
import Foundation
import PersonalScribeCore

protocol ModelAwareFluidAudioInferencing: Sendable {
    func loadModel(
        from directory: URL,
        runtimeVariant: FluidAudioRuntimeVariant,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws

    func transcribe(samples: [Float]) async throws -> FluidAudioInferenceResult
}

extension ModelAwareFluidAudioInferencing {
    func loadModel(
        from directory: URL,
        runtimeVariant: FluidAudioRuntimeVariant
    ) async throws {
        try await loadModel(from: directory, runtimeVariant: runtimeVariant, progressHandler: nil)
    }
}

internal actor PrivateModelAwareFluidAudioInferenceClient: ModelAwareFluidAudioInferencing {
    private let managerFactory: () -> AsrManager
    private var manager: AsrManager?

    init(
        managerFactory: @escaping () -> AsrManager = { AsrManager(config: .default) }
    ) {
        self.managerFactory = managerFactory
    }

    func loadModel(
        from directory: URL,
        runtimeVariant: FluidAudioRuntimeVariant,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws {
        let models = try await AsrModels.load(
            from: directory,
            version: runtimeVariant.asrModelVersion,
            progressHandler: progressHandler
        )
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
