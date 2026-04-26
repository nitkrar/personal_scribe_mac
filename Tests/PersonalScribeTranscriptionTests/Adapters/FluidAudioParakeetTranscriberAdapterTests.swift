import Foundation
import FluidAudio
import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeTranscription

final class FluidAudioParakeetTranscriberAdapterTests: XCTestCase {
    func testCapabilitiesAdvertiseParakeetMetadataSupport() throws {
        let adapter = FluidAudioParakeetTranscriberAdapter(
            descriptor: BuiltInModelCatalog.parakeetTDTCTC110M,
            storageLocator: TestStorageLocator(baseDirectory: try temporaryRootDirectory()),
            manager: StubFluidAudioParakeetManager()
        )

        XCTAssertEqual(
            adapter.capabilities,
            TranscriberCapabilities(
                providesTokenTimings: true,
                providesConfidence: true,
                providesPerformanceMetrics: true,
                providesCustomVocabulary: true
            )
        )
    }

    func testAdapterLoadsModelAndExtractsBasicResultUsingStubManager() async throws {
        let descriptor = BuiltInModelCatalog.parakeetTDTCTC110M
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let expectedModelDirectory = storageLocator
            .url(for: .models)
            .appendingPathComponent(descriptor.repoFolderName, isDirectory: true)
            .standardizedFileURL

        let tokenTimings = [
            TokenTiming(
                token: "nini",
                start: .milliseconds(0),
                end: .milliseconds(180),
                confidence: 0.94
            ),
            TokenTiming(
                token: "mma",
                start: .milliseconds(180),
                end: .milliseconds(320),
                confidence: 0.88
            ),
        ]
        let performanceMetrics = TranscriberPerformanceMetrics(
            loadDuration: .milliseconds(420),
            encodeDuration: .milliseconds(28),
            decodeDuration: .milliseconds(34),
            totalDuration: .milliseconds(75)
        )
        let manager = StubFluidAudioParakeetManager(
            result: .init(
                text: "Ninimma",
                processingDuration: .milliseconds(75),
                confidence: 0.91,
                tokenTimings: tokenTimings,
                performanceMetrics: performanceMetrics,
                ctcDetectedTerms: ["Ninimma"],
                ctcAppliedTerms: ["Ninimma"]
            )
        )
        let adapter = FluidAudioParakeetTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )
        let audio = try PCMBuffer(
            samples: [0.2, -0.1, 0.4, -0.2],
            sampleRate: 2_000,
            channelCount: 1,
            timestamp: ContinuousClock.now
        )

        let result = try await adapter.transcribe(audio)

        XCTAssertEqual(await manager.loadCallCount(), 1)
        XCTAssertEqual(await manager.loadedVersions(), [.tdtCtc110m])
        XCTAssertEqual(await manager.loadedDirectories(), [expectedModelDirectory])
        XCTAssertEqual(await manager.transcribeCallCount(), 1)
        XCTAssertEqual(await manager.lastSamples(), audio.samples)

        XCTAssertEqual(result.text, "Ninimma")
        XCTAssertEqual(result.audioDuration, audio.duration)
        XCTAssertEqual(result.processingDuration, .milliseconds(75))
        XCTAssertEqual(result.confidence, 0.91)
        XCTAssertEqual(result.tokenTimings, tokenTimings)
        XCTAssertEqual(result.performanceMetrics, performanceMetrics)
        XCTAssertEqual(result.ctcDetectedTerms, ["Ninimma"])
        XCTAssertEqual(result.ctcAppliedTerms, ["Ninimma"])
    }

    private func temporaryRootDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }
}

private struct TestStorageLocator: StorageLocator {
    let baseDirectory: URL

    func url(for directory: ManagedDirectory) -> URL {
        baseDirectory
            .appendingPathComponent(directory.pathComponent, isDirectory: true)
            .standardizedFileURL
    }

    func ensureDirectoriesExist() throws {
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        for directory in ManagedDirectory.allCases {
            try FileManager.default.createDirectory(
                at: url(for: directory),
                withIntermediateDirectories: true
            )
        }
    }
}

private actor StubFluidAudioParakeetManager: FluidAudioParakeetManaging {
    private let result: FluidAudioParakeetManagerResult
    private var loadCallCountStorage = 0
    private var loadedVersionsStorage: [AsrModelVersion] = []
    private var loadedDirectoriesStorage: [URL] = []
    private var transcribeCallCountStorage = 0
    private var lastSamplesStorage: [Float] = []

    init(
        result: FluidAudioParakeetManagerResult = .init(
            text: "",
            processingDuration: .zero
        )
    ) {
        self.result = result
    }

    func loadModel(
        from directory: URL,
        version: AsrModelVersion,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws {
        _ = progressHandler
        loadCallCountStorage += 1
        loadedVersionsStorage.append(version)
        loadedDirectoriesStorage.append(directory)
    }

    func transcribe(samples: [Float]) async throws -> FluidAudioParakeetManagerResult {
        transcribeCallCountStorage += 1
        lastSamplesStorage = samples
        return result
    }

    func loadCallCount() -> Int {
        loadCallCountStorage
    }

    func loadedVersions() -> [AsrModelVersion] {
        loadedVersionsStorage
    }

    func loadedDirectories() -> [URL] {
        loadedDirectoriesStorage
    }

    func transcribeCallCount() -> Int {
        transcribeCallCountStorage
    }

    func lastSamples() -> [Float] {
        lastSamplesStorage
    }
}
