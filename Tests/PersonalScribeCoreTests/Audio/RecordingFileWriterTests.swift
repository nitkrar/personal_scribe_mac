import AVFoundation
import XCTest
@testable import PersonalScribeCore

final class RecordingFileWriterTests: XCTestCase {
    private let fileManager = FileManager.default

    func testFilenameUsesLocalTimeYYYYMMDD_HHMMSS() throws {
        let directory = try makeTemporaryDirectory()
        defer { cleanup(directory) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 5,
                day: 19,
                hour: 11,
                minute: 33,
                second: 45
            ))
        )

        let filename = RecordingFileWriter.filename(
            for: date,
            calendar: calendar,
            fileManager: fileManager,
            in: directory
        )

        XCTAssertEqual(filename, "20260519_113345.wav")
    }

    func testFilenameAppendsCollisionSuffix() throws {
        let directory = try makeTemporaryDirectory()
        defer { cleanup(directory) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 5,
                day: 19,
                hour: 11,
                minute: 33,
                second: 45
            ))
        )

        try Data().write(to: directory.appendingPathComponent("20260519_113345.wav", isDirectory: false))
        XCTAssertEqual(
            RecordingFileWriter.filename(
                for: date,
                calendar: calendar,
                fileManager: fileManager,
                in: directory
            ),
            "20260519_113345_2.wav"
        )

        try Data().write(to: directory.appendingPathComponent("20260519_113345_2.wav", isDirectory: false))
        XCTAssertEqual(
            RecordingFileWriter.filename(
                for: date,
                calendar: calendar,
                fileManager: fileManager,
                in: directory
            ),
            "20260519_113345_3.wav"
        )
    }

    func testWriteEmitsReadableWAV() throws {
        let directory = try makeTemporaryDirectory()
        defer { cleanup(directory) }

        let writer = RecordingFileWriter()
        let url = directory.appendingPathComponent("clip.wav", isDirectory: false)
        let buffer = try PCMBuffer(
            samples: [-0.8, -0.2, 0.0, 0.2, 0.8],
            timestamp: ContinuousClock().now
        )

        try writer.write([buffer], to: url)

        let audioFile = try AVAudioFile(forReading: url)
        XCTAssertEqual(audioFile.fileFormat.sampleRate, AppConfig.sampleRate, accuracy: 0.001)
        XCTAssertEqual(Int(audioFile.length), 5)

        let readFormat = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: AppConfig.sampleRate,
                channels: AVAudioChannelCount(AppConfig.channelCount),
                interleaved: false
            )
        )
        let readBuffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: readFormat,
                frameCapacity: AVAudioFrameCount(audioFile.length)
            )
        )
        try audioFile.read(into: readBuffer)

        XCTAssertEqual(Int(readBuffer.frameLength), 5)
        let samples = Array(
            UnsafeBufferPointer(
                start: readBuffer.floatChannelData?[0],
                count: Int(readBuffer.frameLength)
            )
        )
        XCTAssertEqual(samples.first ?? 0, -0.8, accuracy: 0.001)
        XCTAssertEqual(samples.last ?? 0, 0.8, accuracy: 0.001)
    }

    func testWriteSetsRestrictivePermissions() throws {
        let directory = try makeTemporaryDirectory()
        defer { cleanup(directory) }

        let writer = RecordingFileWriter()
        let url = directory.appendingPathComponent("clip.wav", isDirectory: false)
        let buffer = try PCMBuffer(samples: [0.1, -0.1], timestamp: ContinuousClock().now)

        try writer.write([buffer], to: url)

        let permissions = try fileManager
            .attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testWriteRejectsMixedSampleRates() throws {
        let directory = try makeTemporaryDirectory()
        defer { cleanup(directory) }

        let writer = RecordingFileWriter()
        let url = directory.appendingPathComponent("clip.wav", isDirectory: false)
        let first = try PCMBuffer(
            samples: [0.1, -0.1],
            sampleRate: 16_000,
            timestamp: ContinuousClock().now
        )
        let second = try PCMBuffer(
            samples: [0.2, -0.2],
            sampleRate: 8_000,
            timestamp: ContinuousClock().now
        )

        XCTAssertThrowsError(try writer.write([first, second], to: url)) { error in
            XCTAssertEqual(error as? PersonalScribeError, .resampleFailure)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("RecordingFileWriterTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }

    private func cleanup(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }
}
