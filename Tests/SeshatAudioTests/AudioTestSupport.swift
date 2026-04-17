import AVFoundation
import Foundation
import OSLog
import SeshatCore
@testable import SeshatAudio

// Private test-only helpers — do NOT expose from SeshatAudioTests.

enum AudioTestSupport {
    /// Produce a non-interleaved Float32 AVAudioPCMBuffer suitable for feeding
    /// into the tap-simulation path.
    static func makeFloatBuffer(
        sampleRate: Double,
        channels: Int,
        frames: Int,
        fill: (_ channel: Int, _ frame: Int) -> Float
    ) -> AVAudioPCMBuffer {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: AVAudioChannelCount(channels),
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
        else {
            fatalError("AudioTestSupport.makeFloatBuffer: failed to allocate PCM buffer")
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        guard let channelData = buffer.floatChannelData else {
            fatalError("AudioTestSupport.makeFloatBuffer: missing channel data")
        }
        for c in 0..<channels {
            let ptr = channelData[c]
            for i in 0..<frames {
                ptr[i] = fill(c, i)
            }
        }
        return buffer
    }
}

/// Holds a tap callback + lifecycle counters behind an NSLock so test code
/// and the tap callback can safely interact across threads.
final class ThreadSafeEngineBox: @unchecked Sendable {
    // Safe in tests: NSLock protects all mutable state shared between the test thread and the tap callback.
    private let lock = NSLock()
    private var handler: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    private(set) var installCount = 0
    private(set) var removeCount = 0
    private(set) var stopCount = 0
    private(set) var resetCount = 0
    private(set) var prepareCount = 0
    private(set) var startCount = 0
    private(set) var startError: Error?

    init(startError: Error? = nil) {
        self.startError = startError
    }

    func setHandler(_ handler: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
        installCount += 1
    }

    func clearHandler() {
        lock.lock()
        defer { lock.unlock() }
        handler = nil
        removeCount += 1
    }

    func recordStop() {
        lock.lock()
        defer { lock.unlock() }
        stopCount += 1
    }

    func recordReset() {
        lock.lock()
        defer { lock.unlock() }
        resetCount += 1
    }

    func recordPrepare() {
        lock.lock()
        defer { lock.unlock() }
        prepareCount += 1
    }

    func recordStart() throws {
        lock.lock()
        let err = startError
        startCount += 1
        lock.unlock()
        if let err { throw err }
    }

    /// Invoke the installed tap handler with a buffer (used by tests to simulate audio input).
    func emit(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let h = handler
        lock.unlock()
        h?(buffer, AVAudioTime(hostTime: 0))
    }
}

extension AudioEngineDriver {
    /// Test-only driver that routes every lifecycle call into a
    /// `ThreadSafeEngineBox`. Allows tests to drive tap callbacks manually
    /// and to count removeTap/stop/reset.
    static func testStub(
        sampleRate: Double = 44_100,
        channels: Int = 1,
        box: ThreadSafeEngineBox = ThreadSafeEngineBox()
    ) -> AudioEngineDriver {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: AVAudioChannelCount(channels),
                interleaved: false
            )
        else {
            fatalError("testStub: failed to create AVAudioFormat")
        }
        return AudioEngineDriver(
            inputFormatProvider: { format },
            installTap: { handler in box.setHandler(handler) },
            removeTap: { box.clearHandler() },
            prepare: { box.recordPrepare() },
            start: { try box.recordStart() },
            stop: { box.recordStop() },
            reset: { box.recordReset() }
        )
    }
}

/// Reads SeshatLogger messages emitted in the current process via OSLogStore.
enum LogProbe {
    static func audioMessages(since windowSeconds: TimeInterval = 30) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let since = store.position(date: Date().addingTimeInterval(-windowSeconds))
        let predicate = NSPredicate(format: "subsystem == %@ AND category == %@",
                                    SeshatLogger.subsystem,
                                    SeshatLogCategory.audio)
        let entries = try store.getEntries(at: since, matching: predicate)
        return entries.compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
    }
}
