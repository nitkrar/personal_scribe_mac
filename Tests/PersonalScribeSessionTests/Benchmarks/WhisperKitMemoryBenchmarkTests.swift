import Darwin
import XCTest
import PersonalScribeCore
@testable import PersonalScribeSession

/// Opt-in: does WhisperKit's memory grow over many transcriptions in one
/// process (#109)? Skipped unless `NINIMMA_BENCH_WAV` points at a 16 kHz mono
/// file. `NINIMMA_BENCH_ITERATIONS` (default 30) runs per mode.
final class WhisperKitMemoryBenchmarkTests: XCTestCase {
    func testWhisperKitMemoryAcrossRepeatedTranscriptions() async throws {
        guard let path = ProcessInfo.processInfo.environment["NINIMMA_BENCH_WAV"] else {
            throw XCTSkip("Set NINIMMA_BENCH_WAV to run the WhisperKit memory benchmark")
        }
        let iterations = Int(ProcessInfo.processInfo.environment["NINIMMA_BENCH_ITERATIONS"] ?? "") ?? 30
        let samples = try StreamingSecondPassBenchmarkTests.loadMono16k(path: path)
        let descriptor = BuiltInModelCatalog.whisperKitSmallEn217MB
        let provider = ModelBoundProcessorProvider(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.transcription)
        )
        var rows = ["before load: \(Self.footprintMB()) MB"]

        let transcriber = try provider.transcriber(for: descriptor)
        try await transcriber.prepare()
        rows.append("batch prepared: \(Self.footprintMB()) MB")
        for index in 1...iterations {
            _ = try await transcriber.transcribe(PCMBuffer(samples: samples, timestamp: ContinuousClock.now), languageHint: nil)
            if index % 5 == 0 || index == 1 { rows.append("batch \(index): \(Self.footprintMB()) MB") }
        }

        let streamer = try provider.streamingTranscriber(for: descriptor)
        try await streamer.prepare()
        rows.append("streaming prepared: \(Self.footprintMB()) MB")
        for index in 1...iterations {
            let (input, continuation) = AsyncThrowingStream<PCMBuffer, Error>.makeStream()
            let events = streamer.transcribe(stream: input)
            var offset = 0
            while offset < samples.count {
                let end = min(offset + 1_600, samples.count)
                continuation.yield(try PCMBuffer(samples: Array(samples[offset..<end]), timestamp: ContinuousClock.now))
                offset = end
            }
            continuation.finish()
            for try await _ in events {}
            if index % 5 == 0 || index == 1 { rows.append("streaming \(index): \(Self.footprintMB()) MB") }
        }

        // The app releases idle models after 30 s, so spaced-out dictations reload each time.
        for index in 1...iterations {
            await transcriber.releaseIdleResources()
            try await transcriber.prepare()
            _ = try await transcriber.transcribe(PCMBuffer(samples: samples, timestamp: ContinuousClock.now), languageHint: nil)
            if index % 5 == 0 || index == 1 { rows.append("release+reload \(index): \(Self.footprintMB()) MB") }
        }

        let audioMinutes = Double(samples.count) / 16_000 / 60 * Double(iterations)
        print("\n=== WhisperKit \(descriptor.id) memory, \(iterations) runs per mode (~\(Int(audioMinutes)) min audio each)\n  "
            + rows.joined(separator: "\n  "))
    }

    /// Physical footprint, the figure Activity Monitor reports as Memory.
    private static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }
}
