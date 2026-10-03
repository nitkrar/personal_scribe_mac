import AVFoundation
import XCTest
import PersonalScribeCore
@testable import PersonalScribeSession

/// Opt-in: dump raw Parakeet transcripts of saved recordings, then post-process them, to diff cleanup changes.
final class RawTranscriptDumpTests: XCTestCase {
    func testDumpRawTranscripts() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["NINIMMA_DUMP_DIR"], let outPath = env["NINIMMA_RAW_FILE"] else {
            throw XCTSkip("Set NINIMMA_DUMP_DIR and NINIMMA_RAW_FILE")
        }
        let provider = ModelBoundProcessorProvider(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.transcription)
        )
        let transcriber = try provider.transcriber(for: BuiltInModelCatalog.parakeetTDT06Bv2)
        try await transcriber.prepare()
        let files = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".wav") }.sorted()
        var out = ""
        for name in files {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: dir).appendingPathComponent(name))
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
            try file.read(into: buffer)
            let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
            guard samples.count > 16_000 else { continue }
            let text = try await transcriber.transcribe(try PCMBuffer(samples: samples, timestamp: .now), languageHint: nil).text
            let line = try JSONSerialization.data(withJSONObject: ["file": name, "text": text])
            out += String(decoding: line, as: UTF8.self) + "\n"
        }
        try out.write(toFile: outPath, atomically: true, encoding: .utf8)
    }

    func testPostProcessRawTranscripts() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let rawPath = env["NINIMMA_RAW_FILE"], let outPath = env["NINIMMA_PP_OUT"] else {
            throw XCTSkip("Set NINIMMA_RAW_FILE and NINIMMA_PP_OUT")
        }
        let context = PostProcessingContext(recordingDuration: .seconds(1), activeMode: WorkflowMode.dictation)
        var out = ""
        for line in try String(contentsOfFile: rawPath, encoding: .utf8).split(separator: "\n") {
            var row = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: String]
            row["text"] = try await DefaultPostProcessingPipeline().run(row["text"]!, context: context)
            out += String(decoding: try JSONSerialization.data(withJSONObject: row), as: UTF8.self) + "\n"
        }
        try out.write(toFile: outPath, atomically: true, encoding: .utf8)
    }
}
