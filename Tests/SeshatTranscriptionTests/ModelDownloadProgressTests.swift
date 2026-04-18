import XCTest
import SeshatCore
@testable import SeshatTranscription

final class ModelDownloadProgressTests: SeshatTranscriptionFilesystemTestCase {
    func testPrepareEmitsIdleDownloadingFinishedExactlyOnce() async throws {
        let downloader = StubModelDownloader(
            scriptedProgress: [
                .init(phase: .downloading, fractionCompleted: 0.25, receivedBytes: 25, expectedBytes: 100),
                .init(phase: .downloading, fractionCompleted: 0.75, receivedBytes: 75, expectedBytes: 100),
                .init(phase: .downloading, fractionCompleted: 1.0, receivedBytes: 100, expectedBytes: 100),
            ]
        )
        let transcriber = FluidAudioTranscriber(
            downloader: downloader,
            inference: StubInferenceClient()
        )

        let stream = transcriber.modelDownloadProgress()
        let task: Task<[ModelDownloadProgress], Never> = Task {
            var result: [ModelDownloadProgress] = []
            for await value in stream {
                result.append(value)
                if result.count == 5 { break }
            }
            return result
        }

        try await transcriber.prepare()
        let snapshots = await task.value

        XCTAssertEqual(
            snapshots.first,
            .init(phase: .idle, fractionCompleted: 0, receivedBytes: 0, expectedBytes: nil)
        )
        XCTAssertEqual(snapshots.last?.phase, .finished)
        XCTAssertEqual(snapshots.filter { $0.phase == .finished }.count, 1)
        XCTAssertEqual(snapshots.map(\.fractionCompleted), snapshots.map(\.fractionCompleted).sorted())
    }

    func testDownloadProgressAllowsNilExpectedBytesWhenContentLengthMissing() async throws {
        let downloader = StubModelDownloader(
            scriptedProgress: [
                .init(phase: .downloading, fractionCompleted: 0.10, receivedBytes: 1_024, expectedBytes: nil),
                .init(phase: .downloading, fractionCompleted: 0.40, receivedBytes: 4_096, expectedBytes: nil),
            ]
        )
        let transcriber = FluidAudioTranscriber(
            downloader: downloader,
            inference: StubInferenceClient()
        )

        let stream = transcriber.modelDownloadProgress()
        let task: Task<[ModelDownloadProgress], Never> = Task {
            var result: [ModelDownloadProgress] = []
            for await value in stream {
                result.append(value)
                if result.count == 4 { break }
            }
            return result
        }

        try await transcriber.prepare()
        let snapshots = await task.value

        XCTAssertTrue(
            snapshots.contains(where: {
                $0.phase == .downloading && $0.expectedBytes == nil
            })
        )
    }

    private static func collect(
        stream: AsyncStream<ModelDownloadProgress>,
        limit: Int
    ) async -> [ModelDownloadProgress] {
        var result: [ModelDownloadProgress] = []

        for await value in stream {
            result.append(value)
            if result.count == limit {
                break
            }
        }

        return result
    }
}
