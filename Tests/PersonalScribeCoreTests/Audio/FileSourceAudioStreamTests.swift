import AVFoundation
import Foundation
import XCTest
@testable import PersonalScribeCore

final class FileSourceAudioStreamTests: XCTestCase {
    private let fileManager = FileManager.default

    func testStreamsWAVFileAsFloat32Mono16kHz() async throws {
        let directory = try makeTemporaryDirectory()
        defer { cleanup(directory) }

        let samples = makeSineWave(sampleRate: AppConfig.sampleRate, frameCount: 4_000)
        let writer = RecordingFileWriter()
        let sourceURL = directory.appendingPathComponent("fixture.wav", isDirectory: false)
        try writer.write(
            [PCMBuffer(samples: samples, timestamp: ContinuousClock().now)],
            to: sourceURL
        )

        let buffers = try await collectBuffers(
            from: FileSourceAudioStream().stream(from: sourceURL)
        )
        let combined = buffers.flatMap(\.samples)

        XCTAssertEqual(buffers.count, 3)
        XCTAssertEqual(buffers.map(\.frameCount), [1_600, 1_600, 800])
        XCTAssertTrue(buffers.allSatisfy { $0.sampleRate == AppConfig.sampleRate })
        XCTAssertTrue(buffers.allSatisfy { $0.channelCount == AppConfig.channelCount })
        XCTAssertEqual(combined.count, samples.count)
        XCTAssertEqual(combined.first ?? 0, samples.first ?? 0, accuracy: 0.01)
        XCTAssertEqual(combined.last ?? 0, samples.last ?? 0, accuracy: 0.01)
        XCTAssertTrue(buffers[1].timestamp > buffers[0].timestamp)
        XCTAssertTrue(buffers[2].timestamp > buffers[1].timestamp)
    }

    func testStreamsM4AFileWithFormatConversion() async throws {
        let directory = try makeTemporaryDirectory()
        defer { cleanup(directory) }

        let sourceURL = directory.appendingPathComponent("fixture.m4a", isDirectory: false)
        try writeAACFile(
            samples: makeSineWave(sampleRate: 44_100, frameCount: 22_050),
            sampleRate: 44_100,
            to: sourceURL
        )

        let buffers = try await collectBuffers(
            from: FileSourceAudioStream().stream(from: sourceURL)
        )
        let totalFrameCount = buffers.reduce(0) { $0 + $1.frameCount }

        XCTAssertFalse(buffers.isEmpty)
        XCTAssertTrue(buffers.allSatisfy { $0.sampleRate == AppConfig.sampleRate })
        XCTAssertTrue(buffers.allSatisfy { $0.channelCount == AppConfig.channelCount })
        XCTAssertGreaterThan(totalFrameCount, 7_900)
        XCTAssertLessThan(totalFrameCount, 8_100)
        XCTAssertEqual(buffers.first?.frameCount, 1_600)
    }

    func testThrowsFileMissingForNonexistentURL() async throws {
        let missingURL = fileManager.temporaryDirectory
            .appendingPathComponent("FileSourceAudioStreamTests-\(UUID().uuidString).wav", isDirectory: false)
            .standardizedFileURL
        var iterator = FileSourceAudioStream().stream(from: missingURL).makeAsyncIterator()

        do {
            _ = try await iterator.next()
            XCTFail("Expected missing-file stream to throw")
        } catch let error as FileSourceAudioError {
            XCTAssertEqual(error, .fileMissing(missingURL))
        } catch {
            XCTFail("Expected FileSourceAudioError.fileMissing, got \(error)")
        }
    }

    func testCancellationStopsStreamPromptly() async throws {
        let directory = try makeTemporaryDirectory()
        defer { cleanup(directory) }

        let sourceURL = directory.appendingPathComponent("long.wav", isDirectory: false)
        try RecordingFileWriter().write(
            [
                PCMBuffer(
                    samples: makeSineWave(sampleRate: AppConfig.sampleRate, frameCount: 320_000),
                    timestamp: ContinuousClock().now
                ),
            ],
            to: sourceURL
        )

        let firstBufferExpectation = expectation(description: "first buffer received")
        let recorder = BufferCountRecorder()
        let task = Task {
            do {
                for try await buffer in FileSourceAudioStream().stream(from: sourceURL) {
                    let newCount = await recorder.record(buffer)
                    if newCount == 1 {
                        firstBufferExpectation.fulfill()
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                XCTFail("Unexpected stream failure: \(error)")
            }
        }

        await fulfillment(of: [firstBufferExpectation], timeout: 2.0)
        task.cancel()
        _ = await task.result

        let count = await recorder.currentCount()
        XCTAssertLessThanOrEqual(count, 8)
    }

    private func collectBuffers(
        from stream: AsyncThrowingStream<PCMBuffer, Error>
    ) async throws -> [PCMBuffer] {
        var buffers: [PCMBuffer] = []
        for try await buffer in stream {
            buffers.append(buffer)
        }
        return buffers
    }

    private func writeAACFile(
        samples: [Float],
        sampleRate: Double,
        to url: URL
    ) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
        ]
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            )
        )
        let audioFile = try AVAudioFile(forWriting: url, settings: settings)
        let chunkSize = 1_024
        var offset = 0
        while offset < samples.count {
            let frameCount = min(chunkSize, samples.count - offset)
            let buffer = try XCTUnwrap(
                AVAudioPCMBuffer(
                    pcmFormat: format,
                    frameCapacity: AVAudioFrameCount(frameCount)
                )
            )
            buffer.frameLength = AVAudioFrameCount(frameCount)
            let channelData = try XCTUnwrap(buffer.floatChannelData?[0])
            samples[offset..<(offset + frameCount)].withUnsafeBufferPointer { source in
                guard let baseAddress = source.baseAddress else {
                    return
                }
                channelData.update(from: baseAddress, count: frameCount)
            }
            try audioFile.write(from: buffer)
            offset += frameCount
        }
    }

    private func makeSineWave(sampleRate: Double, frameCount: Int) -> [Float] {
        let angularStep = (2.0 * Double.pi * 440.0) / sampleRate
        return (0..<frameCount).map { index in
            Float(sin(Double(index) * angularStep))
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("FileSourceAudioStreamTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }

    private func cleanup(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }
}

private actor BufferCountRecorder {
    private var count = 0

    func record(_ buffer: PCMBuffer) -> Int {
        _ = buffer
        count += 1
        return count
    }

    func currentCount() -> Int {
        count
    }
}
