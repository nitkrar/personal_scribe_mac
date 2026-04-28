import FluidAudio
import Foundation
import PersonalScribeCore

/// Single source of truth for translating FluidAudio's
/// `DownloadUtils.DownloadProgress` into our chip-driving
/// `ModelDownloadProgress`. Adapters MUST emit through
/// `FluidAudioDownloadProgressBroadcaster.emit(_ raw:)` rather than
/// constructing `ModelDownloadProgress` themselves — consolidating the
/// mapping here means fixes (cache-hit detection, phase mapping,
/// fraction handling) propagate to every adapter without per-adapter
/// touch-up.
///
/// Today `fractionCompleted` is intentionally always 0 for downloading
/// and 1 for finished — the chip currently shows "Downloading…" /
/// "Loading…" / "Ready" labels only, no progress bar. FluidAudio's
/// per-chunk delegate emissions are too coarse to drive a smooth bar
/// for `URLSession.download(for:)` in practice; reviving the fraction
/// is a future change once the underlying delegate fires more often
/// (or we route through a custom delegate).
enum FluidAudioProgressMapper {
    static func map(_ raw: DownloadUtils.DownloadProgress) -> ModelDownloadProgress {
        switch raw.phase {
        case .listing:
            return ModelDownloadProgress(
                phase: .downloading,
                fractionCompleted: 0,
                receivedBytes: 0,
                expectedBytes: nil
            )
        case .downloading(_, let totalFiles) where totalFiles == 0:
            // `loadModelsOnce`'s cache-hit shortcut emits this signature
            // (DownloadUtils.swift:202-204) when files are already on
            // disk — `totalFiles == 0` is impossible during a real
            // download. Map to `.loading` so the chip says "Loading…"
            // instead of momentarily flashing "Downloading…" before the
            // compile phase begins.
            return ModelDownloadProgress(
                phase: .loading,
                fractionCompleted: 0,
                receivedBytes: 0,
                expectedBytes: nil
            )
        case .downloading:
            return ModelDownloadProgress(
                phase: .downloading,
                fractionCompleted: 0,
                receivedBytes: 0,
                expectedBytes: nil
            )
        case .compiling:
            return ModelDownloadProgress(
                phase: .loading,
                fractionCompleted: 0,
                receivedBytes: 0,
                expectedBytes: nil
            )
        }
    }
}

/// Shared broadcaster used by every FluidAudio-backed adapter. Replaces
/// the four near-identical per-adapter broadcaster classes that
/// diverged only in name. The `emit(_ raw:)` method is the sole
/// channel for FluidAudio progress, applying `FluidAudioProgressMapper`
/// before yielding — adapters can't route an unmapped or
/// custom-mapped snapshot through.
public final class FluidAudioDownloadProgressBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<ModelDownloadProgress>.Continuation] = [:]
    private var latched: ModelDownloadProgress

    public init(initial: ModelDownloadProgress = .idle) {
        self.latched = initial
    }

    public func stream() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            let identifier = UUID()
            let initial = lock.withLock { () -> ModelDownloadProgress in
                continuations[identifier] = continuation
                return latched
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                _ = self.lock.withLock {
                    self.continuations.removeValue(forKey: identifier)
                }
            }
            continuation.yield(initial)
        }
    }

    /// Emit a FluidAudio progress snapshot. The shared mapper applies
    /// before yielding — there is no path for an adapter to bypass it.
    func emit(_ raw: DownloadUtils.DownloadProgress) {
        emit(FluidAudioProgressMapper.map(raw))
    }

    /// Emit a synthetic snapshot — used for our own
    /// idle/loading/downloading/finished/error states that don't have
    /// FluidAudio counterparts. `emit(_ raw:)` is the only way to surface
    /// FluidAudio progress; this overload exists strictly for
    /// adapter-controlled lifecycle markers.
    public func emit(_ snapshot: ModelDownloadProgress) {
        let continuations = lock.withLock { () -> [AsyncStream<ModelDownloadProgress>.Continuation] in
            self.latched = snapshot
            return Array(self.continuations.values)
        }
        for continuation in continuations {
            continuation.yield(snapshot)
        }
    }

    /// Critical for adapter eviction: when the owning adapter dealloc's,
    /// any consumer Task suspended in `for await ... in stream` would
    /// otherwise stay parked forever — the continuation is held by the
    /// AsyncStream buffer that the Task captured, and without an
    /// explicit `finish()` the for-await never wakes. That keeps the
    /// Task alive, which keeps its captures alive (most importantly the
    /// AsyncStream's reference to the broadcaster and via that, the
    /// adapter — gigabytes of CoreML weights pinned).
    ///
    /// Calling `finish()` on every outstanding continuation in `deinit`
    /// makes consumer for-await loops exit, freeing their captures.
    /// Combined with extracting the AsyncStream out of the for-await
    /// closure capture (so the Task captures the stream value, not the
    /// adapter via `lifecycle.modelDownloadProgress()`), the eviction
    /// chain actually fires when `provider.evict(_:)` removes the last
    /// adapter reference.
    deinit {
        let outstanding = lock.withLock { () -> [AsyncStream<ModelDownloadProgress>.Continuation] in
            let copy = Array(continuations.values)
            continuations.removeAll()
            return copy
        }
        for continuation in outstanding {
            continuation.finish()
        }
    }
}

extension ModelDownloadProgress {
    /// Common synthetic snapshots emitted by FluidAudio adapters around
    /// FluidAudio's own progress events.
    public static let idle = ModelDownloadProgress(
        phase: .idle,
        fractionCompleted: 0,
        receivedBytes: 0,
        expectedBytes: nil
    )

    public static let loading = ModelDownloadProgress(
        phase: .loading,
        fractionCompleted: 0,
        receivedBytes: 0,
        expectedBytes: nil
    )

    public static let downloading = ModelDownloadProgress(
        phase: .downloading,
        fractionCompleted: 0,
        receivedBytes: 0,
        expectedBytes: nil
    )

    public static let finished = ModelDownloadProgress(
        phase: .finished,
        fractionCompleted: 1,
        receivedBytes: 0,
        expectedBytes: nil
    )
}
