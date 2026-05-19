@preconcurrency import CoreML
import FluidAudio
import Foundation
import PersonalScribeCore

typealias VadSessionFactory = @Sendable (Double) -> VadSessionHandle

typealias VadSessionFactoryLoader = @Sendable (URL) -> VadSessionFactory?
typealias VadProviderSleep = @Sendable (Duration) async throws -> Void

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
        case loading(Task<VadSessionFactory?, Never>)
        case loaded(VadSessionFactory)
        case failed
    }

    private let modelURL: URL
    private let idleUnloadDelay: Duration
    private let sleep: VadProviderSleep
    private let sessionFactoryLoader: VadSessionFactoryLoader
    private var loadState: LoadState = .notLoaded
    private var idleReleaseTask: Task<Void, Never>?
    private var idleReleaseGeneration: UInt64 = 0

    /// Convenience init that locates the bundled `.mlmodelc` inside the
    /// module resources. Throws if the resource is missing — that's a
    /// build-time invariant violation (Package.swift / resource-copy drift),
    /// NOT a user-facing failure mode. Debug builds also assert so a dev
    /// build with a mis-configured bundle crashes early rather than silently
    /// proceeding to the production fallback path.
    public init(diagnosticsLogger: PersonalScribeLogger? = nil) throws {
        guard let url = Bundle.module.url(
            forResource: "silero-vad",
            withExtension: "mlmodelc"
        ) else {
            assertionFailure(
                "Bundled VAD model missing — Package.swift `resources:` out of sync with Sources/PersonalScribeVAD/Resources/"
            )
            throw BundledModelError.resourceNotFound
        }
        self.init(modelURL: url, diagnosticsLogger: diagnosticsLogger)
    }

    /// Explicit-URL init for tests and future callers that want to point at
    /// a non-bundled copy of a compiled Silero `.mlmodelc`.
    public init(modelURL: URL, diagnosticsLogger: PersonalScribeLogger? = nil) {
        self.init(
            modelURL: modelURL,
            idleUnloadDelay: .seconds(30),
            sleep: { try await Task.sleep(for: $0) },
            sessionFactoryLoader: Self.makeLiveSessionFactoryLoader(
                diagnosticsLogger: diagnosticsLogger
            )
        )
    }

    init(
        modelURL: URL,
        idleUnloadDelay: Duration = .seconds(30),
        sleep: @escaping VadProviderSleep = { try await Task.sleep(for: $0) },
        sessionFactoryLoader: @escaping VadSessionFactoryLoader = FluidAudioVadProvider.liveSessionFactoryLoader
    ) {
        self.modelURL = modelURL
        self.idleUnloadDelay = idleUnloadDelay
        self.sleep = sleep
        self.sessionFactoryLoader = sessionFactoryLoader
    }

    public func makeSession(silenceThresholdSeconds: Double) async -> VadSessionHandle? {
        invalidateIdleRelease()
        guard let sessionFactory = await ensureManagerLoaded() else { return nil }
        return sessionFactory(silenceThresholdSeconds)
    }

    public func releaseIdleResources() async {
        guard case .loaded = loadState else {
            return
        }

        invalidateIdleRelease()
        let generation = idleReleaseGeneration
        let delay = idleUnloadDelay
        let sleep = sleep
        idleReleaseTask = Task {
            do {
                try await sleep(delay)
            } catch {
                return
            }

            if Task.isCancelled {
                return
            }

            await self.finishIdleRelease(generation: generation)
        }
    }

    private func ensureManagerLoaded() async -> VadSessionFactory? {
        switch loadState {
        case .loaded(let sessionFactory):
            return sessionFactory
        case .failed:
            return nil
        case .loading(let task):
            return await task.value
        case .notLoaded:
            let url = modelURL
            let loader = sessionFactoryLoader
            let task = Task<VadSessionFactory?, Never> {
                loader(url)
            }
            loadState = .loading(task)
            let sessionFactory = await task.value
            loadState = sessionFactory.map(LoadState.loaded) ?? .failed
            return sessionFactory
        }
    }

    private func invalidateIdleRelease() {
        idleReleaseGeneration &+= 1
        idleReleaseTask?.cancel()
        idleReleaseTask = nil
    }

    private func finishIdleRelease(generation: UInt64) async {
        guard generation == idleReleaseGeneration else {
            return
        }

        idleReleaseTask = nil
        if case .loaded = loadState {
            loadState = .notLoaded
        }
    }
}

private extension FluidAudioVadProvider {
    static func liveSessionFactoryLoader(modelURL: URL) -> VadSessionFactory? {
        makeLiveSessionFactoryLoader(diagnosticsLogger: nil)(modelURL)
    }

    static func makeLiveSessionFactoryLoader(
        diagnosticsLogger: PersonalScribeLogger?
    ) -> VadSessionFactoryLoader {
        { modelURL in
            let vadConfig = VadConfig.default
            let mlConfig = MLModelConfiguration()
            mlConfig.computeUnits = vadConfig.computeUnits
            mlConfig.allowLowPrecisionAccumulationOnGPU = true
            guard let model = try? MLModel(contentsOf: modelURL, configuration: mlConfig) else {
                diagnosticsLogger?.error(
                    "vad_model_load_failed modelURL=\(modelURL.path)",
                    error: NSError(domain: "FluidAudioVadProvider", code: -1)
                )
                return nil
            }
            let runtime = LiveVadRuntime(
                manager: VadManager(config: vadConfig, vadModel: model),
                diagnosticsLogger: diagnosticsLogger
            )
            return { silenceThresholdSeconds in
                runtime.makeSession(silenceThresholdSeconds: silenceThresholdSeconds)
            }
        }
    }
}

private final class LiveVadRuntime: @unchecked Sendable {
    private let manager: VadManager
    private let diagnosticsLogger: PersonalScribeLogger?

    init(manager: VadManager, diagnosticsLogger: PersonalScribeLogger? = nil) {
        self.manager = manager
        self.diagnosticsLogger = diagnosticsLogger
    }

    func makeSession(silenceThresholdSeconds: Double) -> VadSessionHandle {
        let config = VadSegmentationConfig(minSilenceDuration: silenceThresholdSeconds)
        // TEMP-DIAG #056-vad-bug: hand the per-runtime diagnostics logger
        // to the session so per-chunk Silero events are observable in
        // the diagnostics log. Remove when the bug closes.
        let session = FluidAudioVadSession(
            inference: { [manager] chunk, state, config in
                try await manager.processStreamingChunk(chunk, state: state, config: config)
            },
            config: config,
            logger: diagnosticsLogger
        )
        return VadSessionHandle { samples in
            await session.ingest(samples)
        }
    }
}
