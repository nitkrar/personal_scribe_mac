import AVFoundation
import XCTest
@testable import PersonalScribeCore

final class FileSourceAudioStreamTests: XCTestCase {
    private let fileManager = FileManager.default

    func testStreamsWAVFileAsFloat32Mono16kHz() async throws {
        let directory = try makeTemporaryDirectory()
        defer { cleanup(directory) }

        let url = directory.appendingPathComponent("fixture.wav", isDirectory: false)
        let samples = makeSineSamples(frameCount: 16_000, sampleRate: 16_000, channelCount: 1)
        let buffer = try PCMBuffer(samples: samples, timestamp: ContinuousClock().now)
        try RecordingFileWriter().write([buffer], to: url)

        let buffers = try await collect(from: FileSourceAudioStream().stream(from: url))

        XCTAssertFalse(buffers.isEmpty)
        XCTAssertTrue(buffers.allSatisfy { $0.sampleRate == 16_000 })
        XCTAssertTrue(buffers.allSatisfy { $0.channelCount == 1 })
        XCTAssertTrue(buffers.allSatisfy { $0.frameCount <= 1_600 })
        XCTAssertEqual(buffers.reduce(0) { $0 + $1.frameCount }, 16_000, accuracy: 1)
    }

    func testStreamsM4AFileWithFormatConversion() async throws {
        let directory = try makeTemporaryDirectory()
        defer { cleanup(directory) }

        let url = directory.appendingPathComponent("fixture.m4a", isDirectory: false)
        try writeAACFixture(to: url)

        let buffers = try await collect(from: FileSourceAudioStream().stream(from: url))

        XCTAssertFalse(buffers.isEmpty)
        XCTAssertTrue(buffers.allSatisfy { $0.sampleRate == AppConfig.sampleRate })
        XCTAssertTrue(buffers.allSatisfy { $0.channelCount == AppConfig.channelCount })
        XCTAssertEqual(
            Double(buffers.reduce(0) { $0 + $1.frameCount }),
            AppConfig.sampleRate,
            accuracy: 512
        )
    }

    func testThrowsFileMissingForNonexistentURL() async throws {
        let directory = try makeTemporaryDirectory()
        defer { cleanup(directory) }

        let url = directory.appendingPathComponent("missing.wav", isDirectory: false)

        do {
            _ = try await collect(from: FileSourceAudioStream().stream(from: url))
            XCTFail("Expected missing file to throw")
        } catch let error as FileSourceAudioError {
            guard case .fileMissing(let missingURL) = error else {
                XCTFail("Expected .fileMissing, got \(error)")
                return
            }
            XCTAssertEqual(missingURL.standardizedFileURL, url.standardizedFileURL)
        }
    }

    func testCancellationStopsStreamPromptly() async throws {
        let directory = try makeTemporaryDirectory()
        defer { cleanup(directory) }

        let url = directory.appendingPathComponent("long.wav", isDirectory: false)
        let samples = makeSineSamples(frameCount: 16_000 * 30, sampleRate: 16_000, channelCount: 1)
        let buffer = try PCMBuffer(samples: samples, timestamp: ContinuousClock().now)
        try RecordingFileWriter().write([buffer], to: url)

        let firstChunkReceived = expectation(description: "first chunk received")
        let consumerFinished = expectation(description: "consumer finished")

        let consumer = Task { () -> Int in
            var received = 0
            do {
                for try await _ in FileSourceAudioStream().stream(from: url) {
                    received += 1
                    if received == 1 {
                        firstChunkReceived.fulfill()
                    }
                }
            } catch {
                XCTFail("Unexpected error: \(error)")
            }

            consumerFinished.fulfill()
            return received
        }

        await fulfillment(of: [firstChunkReceived], timeout: 1.0)

        let clock = ContinuousClock()
        let start = clock.now
        consumer.cancel()

        await fulfillment(of: [consumerFinished], timeout: 1.0)
        let elapsed = start.duration(to: clock.now)
        let received = await consumer.value

        XCTAssertLessThanOrEqual(elapsed, .milliseconds(100))
        XCTAssertLessThan(received, 300)
    }

    private func collect(from stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> [PCMBuffer] {
        var buffers: [PCMBuffer] = []
        for try await buffer in stream {
            buffers.append(buffer)
        }
        return buffers
    }

    private func writeAACFixture(to url: URL) throws {
        let sampleRate = 44_100.0
        let frameCount = AVAudioFrameCount(sampleRate)
        let channels = 2
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: AVAudioChannelCount(channels),
                interleaved: false
            )
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        buffer.frameLength = frameCount

        for channelIndex in 0..<channels {
            guard let channel = buffer.floatChannelData?[channelIndex] else {
                XCTFail("Missing channel data for \(channelIndex)")
                return
            }
            for frame in 0..<Int(frameCount) {
                let angle = 2 * Double.pi * 440 * Double(frame) / sampleRate
                channel[frame] = Float(sin(angle) * (channelIndex == 0 ? 1.0 : 0.5))
            }
        }

        let audioFile = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: 128_000,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        try audioFile.write(from: buffer)
    }

    private func makeSineSamples(
        frameCount: Int,
        sampleRate: Double,
        channelCount: Int
    ) -> [Float] {
        var samples: [Float] = []
        samples.reserveCapacity(frameCount * channelCount)

        for frame in 0..<frameCount {
            let angle = 2 * Double.pi * 440 * Double(frame) / sampleRate
            let sample = Float(sin(angle))
            for _ in 0..<channelCount {
                samples.append(sample)
            }
        }

        return samples
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
