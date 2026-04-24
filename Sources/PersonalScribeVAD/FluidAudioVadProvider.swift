import FluidAudio
import Foundation

/// Production `VadProviding` backed by a lazily-loaded Silero CoreML model.
/// The model URL points at the bundled `.mlmodelc` directory inside the
/// module resources. Load is deferred to the first `makeSession` call to
/// keep launch off the critical path — per codex review, composition-time
/// load would land on `AppComposition.sessionCoordinator`'s static path,
/// which is a known latency concern (see #012).
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

    private let modelDirectoryURL: URL
    private var loadState: LoadState = .notLoaded

    /// Convenience init that locates the bundled model inside the module
    /// resources. Throws if the resource is missing — that's a build-time
    /// invariant violation (Package.swift / resource-copy drift), NOT a
    /// user-facing failure mode. Debug builds also assert so a dev build
    /// with a mis-configured bundle crashes early rather than silently
    /// proceeding to the production fallback path.
    public init() throws {
        guard let url = Bundle.module.url(
            forResource: "silero-vad-unified-256ms-v6.0.0",
            withExtension: "mlmodelc"
        ) else {
            assertionFailure(
                "Bundled VAD model missing — Package.swift `resources:` out of sync with Sources/PersonalScribeVAD/Resources/"
            )
            throw BundledModelError.resourceNotFound
        }
        self.modelDirectoryURL = url
    }

    /// Explicit-URL init for tests and future callers that want to point at
    /// a non-bundled copy.
    public init(modelDirectoryURL: URL) {
        self.modelDirectoryURL = modelDirectoryURL
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
            let url = modelDirectoryURL
            let task = Task<VadManager?, Never> {
                do {
                    return try await VadManager(modelDirectory: url)
                } catch {
                    return nil
                }
            }
            loadState = .loading(task)
            let manager = await task.value
            loadState = manager.map(LoadState.loaded) ?? .failed
            return manager
        }
    }
}
