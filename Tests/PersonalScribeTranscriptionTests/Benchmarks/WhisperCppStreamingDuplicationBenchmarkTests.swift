import AVFoundation
import Foundation
import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeTranscription
import PersonalScribeVAD

/// Opt-in real-model probe for BACKLOG #104 (whisper.cpp streaming tracker
/// confirming the same phrase twice). Skipped unless
/// `NINIMMA_WHISPERCPP_BENCH_WAV` points at a 16 kHz mono file.
///
/// Optional env:
///   NINIMMA_WHISPERCPP_BENCH_TEXT   path to the spoken source text (for n-gram excess vs source)
///   NINIMMA_WHISPERCPP_BENCH_MODEL  descriptor id (default `whispercpp-tiny`; downloaded on first run)
///   NINIMMA_WHISPERCPP_BENCH_RUNS   runs per invocation (default 3)
///   NINIMMA_WHISPERCPP_BENCH_PACE   `realtime` (default, 100 ms chunk every 100 ms) or `fast` (no sleep)
///   NINIMMA_WHISPERCPP_BENCH_OUT    directory for per-run timelines (default /tmp)
///
/// Uses the same wiring as the app (live whisper.cpp manager, bundled Silero
/// VAD, default EoU silence threshold) with recording wrappers, then replays
/// the recorded decodes through a shadow tracker to show the stable prefix
/// at every step.
final class WhisperCppStreamingDuplicationBenchmarkTests: XCTestCase {
    func testWhisperCppStreamingDuplication() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let wavPath = env["NINIMMA_WHISPERCPP_BENCH_WAV"] else {
            throw XCTSkip("Set NINIMMA_WHISPERCPP_BENCH_WAV to run the whisper.cpp duplication probe")
        }
        let samples = try Self.loadMono16k(path: wavPath)
        let sourceText = try env["NINIMMA_WHISPERCPP_BENCH_TEXT"].map { try String(contentsOfFile: $0, encoding: .utf8) }
        let modelID = env["NINIMMA_WHISPERCPP_BENCH_MODEL"] ?? BuiltInModelCatalog.whisperCppTiny.id
        let descriptor = try XCTUnwrap(
            [BuiltInModelCatalog.whisperCppTiny, BuiltInModelCatalog.whisperCppSmallQ51, BuiltInModelCatalog.whisperCppLargeV3TurboQ50]
                .first { $0.id == modelID }
        )
        let runs = Int(env["NINIMMA_WHISPERCPP_BENCH_RUNS"] ?? "") ?? 3
        let fast = env["NINIMMA_WHISPERCPP_BENCH_PACE"] == "fast"
        let outDir = URL(fileURLWithPath: env["NINIMMA_WHISPERCPP_BENCH_OUT"] ?? "/tmp", isDirectory: true)
        let vadProvider = try FluidAudioVadProvider()
        let silenceSeconds = Double(PreferenceKeys.streamingEouSilenceThresholdMs.default) / 1000

        var summary = "\n=== #104 probe | \(descriptor.id) | \(URL(fileURLWithPath: wavPath).lastPathComponent) | \(String(format: "%.1f", Double(samples.count) / 16_000)) s | pace=\(fast ? "fast" : "realtime")"
        for run in 1...runs {
            let log = ProbeLog()
            let manager = RecordingManager(inner: LiveWhisperCppManager(), log: log)
            let adapter = WhisperCppAdapter(
                descriptor: descriptor,
                storageLocator: AppConfig.liveStorageLocator(),
                manager: manager,
                downloader: LiveWhisperCppDownloader(),
                vadSessionFactory: { threshold in
                    guard let session = await vadProvider.makeSession(silenceThresholdSeconds: threshold) else {
                        return nil
                    }
                    return WhisperCppStreamingVadSessionHandle { chunk in
                        let event: WhisperCppStreamingVadEvent?
                        switch await session.ingest(chunk) {
                        case .speechEnded: event = .speechEnded
                        case .speechResumed: event = .speechResumed
                        case nil: event = nil
                        }
                        log.recordBuffer(sampleCount: chunk.count, vad: event)
                        return event
                    }
                },
                eouSilenceThresholdMsResolver: { Int(silenceSeconds * 1000) }
            )
            try await adapter.prepare()

            let (input, continuation) = AsyncThrowingStream<PCMBuffer, Error>.makeStream()
            let events = adapter.transcribe(stream: input)
            let feeder = Task {
                var index = 0
                while index < samples.count {
                    let end = min(index + 1_600, samples.count)
                    continuation.yield(try PCMBuffer(samples: Array(samples[index..<end]), timestamp: ContinuousClock.now))
                    index = end
                    if !fast { try await Task.sleep(for: .milliseconds(100)) }
                }
                continuation.finish()
            }
            var card = LiveCard()
            for try await raw in events {
                let event = raw.removingNonSpeechMarkers()
                card.apply(event)
                log.recordEvent(event, cardText: card.text)
            }
            _ = try await feeder.value
            await adapter.cleanup()

            let report = Self.analyse(log: log.entries, sourceText: sourceText)
            let timelineURL = outDir.appendingPathComponent("ws104-\(descriptor.id)-\(URL(fileURLWithPath: wavPath).deletingPathExtension().lastPathComponent)-\(fast ? "fast" : "rt")-run\(run).txt")
            try report.timeline.write(to: timelineURL, atomically: true, encoding: .utf8)
            summary += "\n--- run \(run): \(report.summary)\n    timeline: \(timelineURL.path)"
        }
        print(summary)
    }

    // MARK: - Analysis

    private struct Report {
        var summary: String
        var timeline: String
    }

    private static func analyse(log: [ProbeEntry], sourceText: String?) -> Report {
        var shadow = WhisperCppStableSegmentTracker()
        var timeline = ""
        var totalSamples = 0
        var pendingFlush = false
        var shadowEoUs: [String] = []
        var actualEoUs: [String] = []
        var cardSnapshots: [String] = []
        var finalText = ""

        func line(_ ms: Int, _ text: String) {
            timeline += String(format: "[%6.2fs] ", Double(ms) / 1000) + text + "\n"
        }
        func flushIfPending(_ ms: Int) {
            guard pendingFlush else { return }
            pendingFlush = false
            if let text = shadow.flushStablePrefix() {
                shadowEoUs.append(text)
                line(ms, "SHADOW FLUSH -> \(text)")
            }
        }

        for entry in log {
            let audioMs = totalSamples / 16
            switch entry {
            case .buffer(let count, let vad):
                flushIfPending(audioMs)
                totalSamples += count
                if let vad {
                    line(totalSamples / 16, "VAD \(vad)")
                    if vad == .speechEnded { pendingFlush = true }
                }
            case .decode(let windowCount, let segments):
                let offsetMs = Int64((Double(totalSamples - windowCount) / 16_000) * 1_000)
                let absolute = segments.map {
                    WhisperCppDecodedSegment(text: $0.text, startMs: $0.startMs + offsetMs, endMs: $0.endMs + offsetMs)
                }
                shadow.ingest(absolute)
                let partial = shadow.partialText
                let current = shadow.currentUtteranceText
                let stable = String(current.dropLast(partial.count)).trimmingCharacters(in: .whitespaces)
                let segs = absolute.map { "{\($0.startMs)-\($0.endMs) \($0.text.trimmingCharacters(in: .whitespaces))}" }.joined(separator: " ")
                line(totalSamples / 16, "DECODE win@\(offsetMs)ms segs=\(segs)\n           stable=[\(stable)] partial=[\(partial)]")
            case .event(let kind, let text, let card):
                switch kind {
                case "eou": actualEoUs.append(text)
                case "final": finalText = text
                default: break
                }
                if kind != "final" { cardSnapshots.append(card) }
                line(totalSamples / 16, "EVENT \(kind): \(text)\n           card=[\(card)]")
            }
        }
        pendingFlush = true
        flushIfPending(totalSamples / 16)

        let eouJoined = actualEoUs.joined(separator: " ")
        var parts: [String] = []
        parts.append("eouCount=\(actualEoUs.count) shadowMatches=\(shadowEoUs == actualEoUs)")
        let sourceCounts = sourceText.map { trigramCounts($0) } ?? [:]
        func excess(_ text: String) -> [(String, Int)] {
            trigramCounts(text)
                .compactMap { gram, count in
                    // Misrecognized trigrams are absent from the source; allow them once.
                    let allowed = max(sourceCounts[gram] ?? 0, 1)
                    return count > allowed ? (gram, count - allowed) : nil
                }
                .sorted { $0.0 < $1.0 }
        }
        let eouExcess = excess(eouJoined)
        let finalExcess = excess(finalText)
        var cardExcess: [String: Int] = [:]
        for snap in cardSnapshots {
            for (gram, extra) in excess(snap) { cardExcess[gram] = max(cardExcess[gram] ?? 0, extra) }
        }
        let fmt: ([(String, Int)]) -> String = { $0.isEmpty ? "none" : $0.map { "\"\($0.0)\"+\($0.1)" }.joined(separator: ", ") }
        parts.append("EoU-stream trigram excess: \(fmt(eouExcess))")
        parts.append("finalized-text trigram excess: \(fmt(finalExcess))")
        parts.append("live-card max trigram excess: \(fmt(cardExcess.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }))")
        timeline += "\n=== EoU chunks ===\n" + actualEoUs.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        timeline += "\n=== finalized ===\n\(finalText)\n"
        return Report(summary: parts.joined(separator: "\n    "), timeline: timeline)
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func trigramCounts(_ text: String) -> [String: Int] {
        let w = words(text)
        guard w.count >= 3 else { return [:] }
        var counts: [String: Int] = [:]
        for i in 0...(w.count - 3) {
            counts[w[i..<(i + 3)].joined(separator: " "), default: 0] += 1
        }
        return counts
    }

    private static func loadMono16k(path: String) throws -> [Float] {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let format = file.processingFormat
        XCTAssertEqual(format.sampleRate, 16_000)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }
}

/// Mirrors `StreamingTranscriptAccumulator.cumulativeText` (what the live card renders).
private struct LiveCard {
    var committed: [String] = []
    var inProgress: String?

    mutating func apply(_ event: StreamingTranscriptionEvent) {
        switch event {
        case .partial(let text):
            let n = Self.normalize(text)
            inProgress = n.isEmpty ? nil : n
        case .endOfUtterance(let text):
            let n = Self.normalize(text)
            if !n.isEmpty { committed.append(n) }
            inProgress = nil
        case .finalized:
            break
        }
    }

    var text: String {
        (committed + (inProgress.map { [$0] } ?? [])).joined(separator: " ")
    }

    private static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

private enum ProbeEntry {
    case buffer(sampleCount: Int, vad: WhisperCppStreamingVadEvent?)
    case decode(windowSampleCount: Int, segments: [WhisperCppDecodedSegment])
    case event(kind: String, text: String, card: String)
}

private final class ProbeLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ProbeEntry] = []

    var entries: [ProbeEntry] { lock.withLock { storage } }

    func recordBuffer(sampleCount: Int, vad: WhisperCppStreamingVadEvent?) {
        lock.withLock { storage.append(.buffer(sampleCount: sampleCount, vad: vad)) }
    }

    func recordDecode(windowSampleCount: Int, segments: [WhisperCppDecodedSegment]) {
        lock.withLock { storage.append(.decode(windowSampleCount: windowSampleCount, segments: segments)) }
    }

    func recordEvent(_ event: StreamingTranscriptionEvent, cardText: String) {
        let entry: ProbeEntry
        switch event {
        case .partial(let text): entry = .event(kind: "partial", text: text, card: cardText)
        case .endOfUtterance(let text): entry = .event(kind: "eou", text: text, card: cardText)
        case .finalized(let result): entry = .event(kind: "final", text: result.text, card: cardText)
        }
        lock.withLock { storage.append(entry) }
    }
}

private final class RecordingManager: WhisperCppManaging, @unchecked Sendable {
    private let inner: any WhisperCppManaging
    private let log: ProbeLog

    init(inner: any WhisperCppManaging, log: ProbeLog) {
        self.inner = inner
        self.log = log
    }

    func loadModel(from modelFileURL: URL) async throws {
        try await inner.loadModel(from: modelFileURL)
    }

    func transcribe(audioSamples: [Float], languageHint: String?) async throws -> WhisperCppManagerResult {
        try await inner.transcribe(audioSamples: audioSamples, languageHint: languageHint)
    }

    func decodeSegments(audioSamples: [Float], languageHint: String?) async throws -> [WhisperCppDecodedSegment] {
        let segments = try await inner.decodeSegments(audioSamples: audioSamples, languageHint: languageHint)
        log.recordDecode(windowSampleCount: audioSamples.count, segments: segments)
        return segments
    }

    func cleanup() async {
        await inner.cleanup()
    }
}
