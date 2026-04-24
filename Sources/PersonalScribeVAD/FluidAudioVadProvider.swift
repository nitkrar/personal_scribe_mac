@preconcurrency import CoreML
import FluidAudio
import Foundation

/// Production `VadProviding` backed by a lazily-loaded Silero CoreML model.
/// The `.mlmodelc` directory is bundled as `silero-vad.mlmodelc` inside the
/// module resources — the folder name is version-agnostic so future model
/// bumps only swap file contents, not identifiers in code or `Package.swift`.
///
/// Load path: we compile the bundled `.mlmodelc` into an `MLModel` ourselves
/// and hand it to `VadManager(config:vadModel:)`. We deliberately do NOT use
/// `VadManager(modelDirectory:)` — that API treats its URL as a parent cache
/// root and (on a miss) downloads the Silero model from HuggingFace under a
/// version-tied internal name, defeating the point of bundling.
///
/// Load is deferred to the first `makeSession` call to keep launch off the
/// critical path — per codex review, composition-time load would land on
/// `AppComposition.sessionCoordinator`'s static path, which is a known
/// latency concern (see #012).
///
/// Memoized decision: after the first load attempt, the outcome (loaded or
/// failed) is frozen for the process. No retry. A bundled-resource failure
/// means the feature is quietly unavailable until the next app launch —
/// `makeSession` returns `nil` and the orchestrator no-ops.
public actor FluidAudioVadProvider: VadProviding {
    public enum BundledModelError: Error {
        case resourceNotFound
    }

    private enum LoadState {
        case notLoaded
        case loading(Task<VadManager?, Never>)
        case loaded(VadManager)
        case failed
    }

    private let modelURL: URL
    private var loadState: LoadState = .notLoaded

    /// Convenience init that locates the bundled `.mlmodelc` inside the
    /// module resources. Throws if the resource is missing — that's a
    /// build-time invariant violation (Package.swift / resource-copy drift),
    /// NOT a user-facing failure mode. Debug builds also assert so a dev
    /// build with a mis-configured bundle crashes early rather than silently
    /// proceeding to the production fallback path.
    public init() throws {
        guard let url = Bundle.module.url(
            forResource: "silero-vad",
            withExtension: "mlmodelc"
        ) else {
            assertionFailure(
                "Bundled VAD model missing — Package.swift `resources:` out of sync with Sources/PersonalScribeVAD/Resources/"
            )
            throw BundledModelError.resourceNotFound
        }
        self.modelURL = url
    }

    /// Explicit-URL init for tests and future callers that want to point at
    /// a non-bundled copy of a compiled Silero `.mlmodelc`.
    public init(modelURL: URL) {
        self.modelURL = modelURL
    }

    public func makeSession(silenceThresholdSeconds: Double) async -> VadSessionHandle? {
        guard let manager = await ensureManagerLoaded() else { return nil }
        let config = VadSegmentationConfig(minSilenceDuration: silenceThresholdSeconds)
        let session = FluidAudioVadSession(
            inference: { chunk, state, config in
                try await manager.processStreamingChunk(chunk, state: state, config: config)
            },
            config: config
        )
        return VadSessionHandle { samples in
            await session.ingest(samples)
        }
    }

    private func ensureManagerLoaded() async -> VadManager? {
        switch loadState {
        case .loaded(let manager):
            return manager
        case .failed:
            return nil
        case .loading(let task):
            return await task.value
        case .notLoaded:
            let url = modelURL
            let task = Task<VadManager?, Never> {
                let vadConfig = VadConfig.default
                let mlConfig = MLModelConfiguration()
                mlConfig.computeUnits = vadConfig.computeUnits
                mlConfig.allowLowPrecisionAccumulationOnGPU = true
                guard let model = try? MLModel(contentsOf: url, configuration: mlConfig) else {
                    return nil
                }
                return VadManager(config: vadConfig, vadModel: model)
            }
            loadState = .loading(task)
            let manager = await task.value
            loadState = manager.map(LoadState.loaded) ?? .failed
            return manager
        }
    }
}
