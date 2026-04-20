import AVFoundation
import Foundation

/// Internal seam around `AVAudioEngine`'s input tap lifecycle. Production uses
/// `.live()`; tests inject their own closures.
///
/// Kept as a class (not an actor) because AVFoundation's tap callbacks fire on
/// real-time threads and cannot be actor-isolated. Instances are held behind
/// `AVAudioCaptureService`'s actor, which serializes the only public entry
/// points that mutate driver state.
internal final class AudioEngineDriver: @unchecked Sendable {
    // Safe: lifecycle mutations are serialized by the owning AVAudioCaptureService
    // actor; the tap callback is the only concurrent caller and only reads the
    // installed handler (no mutation).

    internal init(
        inputFormatProvider: @escaping () -> AVAudioFormat,
        installTap: @escaping (
            @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
        ) throws -> Void,
        removeTap: @escaping () -> Void,
        prepare: @escaping () -> Void,
        start: @escaping () throws -> Void,
        stop: @escaping () -> Void,
        reset: @escaping () -> Void
    ) {
        self.inputFormatProvider = inputFormatProvider
        self.installTapImpl = installTap
        self.removeTapImpl = removeTap
        self.prepareImpl = prepare
        self.startImpl = start
        self.stopImpl = stop
        self.resetImpl = reset
    }

    internal static func live() -> AudioEngineDriver {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        return AudioEngineDriver(
            inputFormatProvider: { inputNode.outputFormat(forBus: 0) },
            installTap: { handler in
                inputNode.installTap(
                    onBus: 0,
                    bufferSize: 4_096,
                    format: inputNode.outputFormat(forBus: 0)
                ) { buffer, when in
                    handler(buffer, when)
                }
            },
            removeTap: {
                inputNode.removeTap(onBus: 0)
            },
            prepare: {
                engine.prepare()
            },
            start: {
                try engine.start()
            },
            stop: {
                engine.stop()
            },
            reset: {
                engine.reset()
            }
        )
    }

    internal func inputFormat() -> AVAudioFormat { inputFormatProvider() }
    internal func installTap(_ handler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        try installTapImpl(handler)
    }
    internal func removeTap() { removeTapImpl() }
    internal func prepare() { prepareImpl() }
    internal func start() throws { try startImpl() }
    internal func stop() { stopImpl() }
    internal func reset() { resetImpl() }

    private let inputFormatProvider: () -> AVAudioFormat
    private let installTapImpl: (@escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) throws -> Void
    private let removeTapImpl: () -> Void
    private let prepareImpl: () -> Void
    private let startImpl: () throws -> Void
    private let stopImpl: () -> Void
    private let resetImpl: () -> Void
}
