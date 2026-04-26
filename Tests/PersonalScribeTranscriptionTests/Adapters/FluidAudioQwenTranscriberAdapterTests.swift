import Foundation
import XCTest
import PersonalScribeCore
@testable import PersonalScribeTranscription

final class FluidAudioQwenTranscriberAdapterTests: PersonalScribeTranscriptionFilesystemTestCase {
    func testAdapterLoadsModelAndExtractsBasicResultUsingStubManager() async throws {
        let descriptor = BuiltInModelCatalog.qwen3AsrF32
        let storageLocator = QwenAdapterTestStorageLocator(baseDirectory: testRoot)
        let manager = StubQwenManager(resultText: "hello from qwen")
        let adapter = FluidAudioQwenTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )
        let audio = try PCMBuffer(
            samples: [0.1, -0.2, 0.3, -0.4],
            timestamp: ContinuousClock().now
        )

        let progressStream = adapter.modelDownloadProgress()
        let snapshotsTask = Task {
            var snapshots: [ModelDownloadProgress] = []
            for await snapshot in progressStream {
                snapshots.append(snapshot)
                if snapshot.phase == .finished {
                    break
                }
            }
            return snapshots
        }

        try await adapter.prepare()
        let result = try await adapter.transcribe(audio)

        let expectedDirectory = storageLocator
            .url(for: .models)
            .appendingPathComponent(descriptor.repoFolderName, isDirectory: true)
            .standardizedFileURL

        XCTAssertEqual(adapter.capabilities, TranscriberCapabilities())
        let loadDirs = await manager.loadDirectories()
        XCTAssertEqual(loadDirs, [expectedDirectory])
        let loadCount = await manager.loadCallCount()
        XCTAssertEqual(loadCount, 1)
        let samples = await manager.transcribedSamples()
        XCTAssertEqual(samples, [audio.samples])

        XCTAssertEqual(result.text, "hello from qwen")
        XCTAssertEqual(result.audioDuration, audio.duration)
        XCTAssertEqual(result.segments, [])
        XCTAssertNil(result.confidence)
        XCTAssertNil(result.tokenTimings)
        XCTAssertNil(result.performanceMetrics)
        XCTAssertNil(result.ctcDetectedTerms)
        XCTAssertNil(result.ctcAppliedTerms)

        let snapshots = await snapshotsTask.value
        XCTAssertEqual(snapshots.first?.phase, .idle)
        XCTAssertTrue(snapshots.contains(where: { $0.phase == .loading }))
        XCTAssertEqual(snapshots.last?.phase, .finished)
    }
}

private struct QwenAdapterTestStorageLocator: StorageLocator {
    let baseDirectory: URL

    func url(for directory: ManagedDirectory) -> URL {
        baseDirectory
            .appendingPathComponent(directory.pathComponent, isDirectory: true)
            .standardizedFileURL
    }

    func ensureDirectoriesExist() throws {}
}

private actor StubQwenManager: FluidAudioQwenManaging {
    private let resultText: String
    private var loadDirectoriesStorage: [URL] = []
    private var transcribedSamplesStorage: [[Float]] = []

    init(resultText: String) {
        self.resultText = resultText
    }

    func loadModels(from directory: URL) async throws {
        loadDirectoriesStorage.append(directory)
    }

    func transcribe(audioSamples: [Float]) async throws -> String {
        transcribedSamplesStorage.append(audioSamples)
        return resultText
    }

    func loadDirectories() -> [URL] {
        loadDirectoriesStorage
    }

    func loadCallCount() -> Int {
        loadDirectoriesStorage.count
    }

    func transcribedSamples() -> [[Float]] {
        transcribedSamplesStorage
    }
}
