import AVFoundation
import XCTest
import PersonalScribeCore
@testable import PersonalScribeSession

/// Opt-in end-to-end benchmark of the streaming models with the real
/// downloaded weights (no mic needed). Skipped unless
/// `NINIMMA_BENCH_WAV` points at a 16 kHz mono audio file, e.g. made with:
///   say -o /tmp/bench.aiff -f text.txt
///   afconvert -f WAVE -d LEF32@16000 -c 1 /tmp/bench.aiff /tmp/bench.wav
/// Optional `NINIMMA_BENCH_TEXT` = the spoken text, for a word-diff count.
/// `NINIMMA_BENCH_PACE=burst` feeds the whole file at once instead of in
/// real time.
///
/// Mirrors the app's second-pass rule (DECISIONS.md #24): WhisperKit
/// re-runs itself; streaming-only Parakeet EOU falls back to Parakeet TDT.
final class StreamingSecondPassBenchmarkTests: XCTestCase {
    func testWhisperKitSmallEnStreamingAndSecondPass() async throws {
        let report = try await benchmark(
            streaming: BuiltInModelCatalog.whisperKitSmallEn217MB,
            secondPass: BuiltInModelCatalog.whisperKitSmallEn217MB
        )
        print(report)
    }

    func testParakeetEOUStreamingWithParakeetTDTSecondPass() async throws {
        let report = try await benchmark(
            streaming: BuiltInModelCatalog.parakeetEou160ms,
            secondPass: BuiltInModelCatalog.parakeetTDT06Bv2
        )
        print(report)
    }

    private func benchmark(streaming: ModelDescriptor, secondPass: ModelDescriptor) async throws -> String {
        guard let path = ProcessInfo.processInfo.environment["NINIMMA_BENCH_WAV"] else {
            throw XCTSkip("Set NINIMMA_BENCH_WAV to run the real-model streaming benchmark")
        }
        let samples = try Self.loadMono16k(path: path)
        let audioSeconds = Double(samples.count) / 16_000
        let provider = ModelBoundProcessorProvider(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.transcription)
        )
        let clock = ContinuousClock()

        // Live (streaming) pass, 100 ms chunks like the mic path.
        let streamer = try provider.streamingTranscriber(for: streaming)
        benchLog("\(streaming.id): live prepare start")
        let livePrepare = try await clock.measure { try await streamer.prepare() }
        benchLog("\(streaming.id): live prepare done \(livePrepare)")
        let (input, continuation) = AsyncThrowingStream<PCMBuffer, Error>.makeStream()
        let liveStart = clock.now
        let events = streamer.transcribe(stream: input)
        let burst = ProcessInfo.processInfo.environment["NINIMMA_BENCH_PACE"] == "burst"
        let feeder = Task {
            var index = 0
            while index < samples.count {
                let end = min(index + 1_600, samples.count)
                continuation.yield(try PCMBuffer(samples: Array(samples[index..<end]), timestamp: clock.now))
                index = end
                if !burst {
                    try await Task.sleep(for: .milliseconds(100))
                }
            }
            continuation.finish()
        }
        var liveText = ""
        var firstPartial: Duration?
        benchLog("\(streaming.id): streaming \(samples.count) samples")
        for try await event in events {
            switch event {
            case .partial(let text):
                if firstPartial == nil { firstPartial = clock.now - liveStart }
                liveText = text
            case .endOfUtterance(let text):
                liveText += (liveText.isEmpty ? "" : " ") + text
            case .finalized(let result):
                liveText = result.text
            }
        }
        _ = try await feeder.value
        let liveDuration = clock.now - liveStart
        benchLog("\(streaming.id): stream done \(liveDuration)")

        // Second pass over the whole recording (what you wait for after stop).
        let transcriber = try provider.transcriber(for: secondPass)
        benchLog("\(secondPass.id): second prepare start")
        let secondPrepare = try await clock.measure { try await transcriber.prepare() }
        benchLog("\(secondPass.id): second prepare done \(secondPrepare)")
        let full = try PCMBuffer(samples: samples, timestamp: clock.now)
        var secondText = ""
        let secondDuration = try await clock.measure {
            secondText = try await transcriber.transcribe(full, languageHint: nil).text
        }

        let source = ProcessInfo.processInfo.environment["NINIMMA_BENCH_TEXT"]
        func diff(_ text: String) -> String {
            guard let source else { return "-" }
            return "\(Self.wordDiff(source, text)) words differ"
        }
        let msPerAudioSecond = Double(secondDuration.components.attoseconds / 1_000_000_000_000_000 + secondDuration.components.seconds * 1000) / audioSeconds
        return """

        === \(streaming.id) -> second pass \(secondPass.id) | audio \(String(format: "%.1f", audioSeconds)) s
          live:   prepare \(livePrepare) | \(burst ? "burst fed" : "real-time fed") | first partial \(firstPartial.map { "\($0)" } ?? "none") | full stream \(liveDuration) | \(diff(liveText))
          second: prepare \(secondPrepare) | transcribe \(secondDuration) (\(String(format: "%.0f", msPerAudioSecond)) ms per audio-second) | \(diff(secondText))
          live text:   \(liveText)
          second text: \(secondText)
        """
    }

    private static func loadMono16k(path: String) throws -> [Float] {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let format = file.processingFormat
        XCTAssertEqual(format.sampleRate, 16_000, "convert with afconvert -d LEF32@16000 -c 1")
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    /// Word-level Levenshtein distance on lowercased, punctuation-stripped words.
    private static func wordDiff(_ a: String, _ b: String) -> Int {
        func words(_ s: String) -> [String] {
            s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        }
        let x = words(a), y = words(b)
        var row = Array(0...y.count)
        for i in 1...max(x.count, 1) where !x.isEmpty {
            var prev = row[0]; row[0] = i
            for j in stride(from: 1, through: y.count, by: 1) {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (x[i - 1] == y[j - 1] ? 0 : 1))
                prev = current
            }
        }
        return row[y.count]
    }

    /// Unbuffered progress marker (survives the process being killed).
    private func benchLog(_ message: String) {
        FileHandle.standardError.write(Data("[bench] \(message)\n".utf8))
    }
}
