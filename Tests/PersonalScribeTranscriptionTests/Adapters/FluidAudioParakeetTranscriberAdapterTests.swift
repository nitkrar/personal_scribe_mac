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

        let loadCount = await manager.loadCallCount()
        XCTAssertEqual(loadCount, 1)
        let loadedVersions = await manager.loadedVersions()
        XCTAssertEqual(loadedVersions, [.tdtCtc110m])
        let loadedDirs = await manager.loadedDirectories()
        XCTAssertEqual(loadedDirs, [expectedModelDirectory])
        let transcribeCount = await manager.transcribeCallCount()
        XCTAssertEqual(transcribeCount, 1)
        let lastSamples = await manager.lastSamples()
        XCTAssertEqual(lastSamples, audio.samples)

        XCTAssertEqual(result.text, "Ninimma")
        XCTAssertEqual(result.audioDuration, audio.duration)
        XCTAssertEqual(result.processingDuration, .milliseconds(75))
        XCTAssertEqual(result.confidence, 0.91)
        XCTAssertEqual(result.tokenTimings, tokenTimings)
        XCTAssertEqual(result.performanceMetrics, performanceMetrics)
        XCTAssertEqual(result.ctcDetectedTerms, ["Ninimma"])
        XCTAssertEqual(result.ctcAppliedTerms, ["Ninimma"])
    }

    func testDownloadIfNeededCallsManagerDownloadButNotLoad() async throws {
        let descriptor = BuiltInModelCatalog.parakeetTDTCTC110M
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let expectedParentDirectory = storageLocator
            .url(for: .models)
            .appendingPathComponent(descriptor.repoFolderName, isDirectory: true)
            .standardizedFileURL
            .deletingLastPathComponent()

        let manager = StubFluidAudioParakeetManager()
        let adapter = FluidAudioParakeetTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )

        try await adapter.downloadIfNeeded()

        // After downloadIfNeeded runs, subscribing to the progress stream
        // yields the latched snapshot — which should now be .finished.
        var collected: [ModelDownloadProgress] = []
        let stream = adapter.modelDownloadProgress()
        for await snapshot in stream {
            collected.append(snapshot)
            break
        }

        let downloadCount = await manager.downloadIfNeededCallCount()
        XCTAssertEqual(downloadCount, 1)
        let loadCount = await manager.loadCallCount()
        XCTAssertEqual(loadCount, 0)
        let transcribeCount = await manager.transcribeCallCount()
        XCTAssertEqual(transcribeCount, 0)

        let downloadDirs = await manager.downloadIfNeededDirectories()
        XCTAssertEqual(downloadDirs, [expectedParentDirectory])

        // Hybrid 110m must also pull the CTC head auxiliary so the
        // Download UI accounts for all bytes the model needs.
        let auxCalls = await manager.auxiliaryDownloadCalls()
        XCTAssertEqual(auxCalls.count, 1)
        XCTAssertEqual(auxCalls.first?.aux, .ctc110m)
        XCTAssertEqual(auxCalls.first?.directory, expectedParentDirectory)

        XCTAssertEqual(collected.last?.phase, .finished)
    }

    func testPrepareCallsDownloadIfNeededAndLoadModel() async throws {
        let descriptor = BuiltInModelCatalog.parakeetTDTCTC110M
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let expectedLeafDirectory = storageLocator
            .url(for: .models)
            .appendingPathComponent(descriptor.repoFolderName, isDirectory: true)
            .standardizedFileURL
        let expectedParentDirectory = expectedLeafDirectory.deletingLastPathComponent()

        let manager = StubFluidAudioParakeetManager()
        let adapter = FluidAudioParakeetTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )

        try await adapter.prepare()

        let downloadCount = await manager.downloadIfNeededCallCount()
        XCTAssertEqual(downloadCount, 1)
        let loadCount = await manager.loadCallCount()
        XCTAssertEqual(loadCount, 1)

        let downloadDirs = await manager.downloadIfNeededDirectories()
        XCTAssertEqual(downloadDirs, [expectedParentDirectory])
        let loadedDirs = await manager.loadedDirectories()
        XCTAssertEqual(loadedDirs, [expectedLeafDirectory])
        // Prepare path also pulls the hybrid's CTC head — same fix as
        // Download, just via the Activate-time chain.
        let auxCalls = await manager.auxiliaryDownloadCalls()
        XCTAssertEqual(auxCalls.count, 1)
        XCTAssertEqual(auxCalls.first?.aux, .ctc110m)
    }

    func testCleanupForwardsToManagerAndAllowsPrepareToReload() async throws {
        let descriptor = BuiltInModelCatalog.parakeetTDT06Bv3
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubFluidAudioParakeetManager()
        let adapter = FluidAudioParakeetTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )

        try await adapter.prepare()
        await adapter.cleanup()
        try await adapter.prepare()

        let cleanupCount = await manager.cleanupCallCount()
        let loadCount = await manager.loadCallCount()
        XCTAssertEqual(cleanupCount, 1)
        XCTAssertEqual(
            loadCount,
            2,
            "cleanup must clear the prepared latch so a later prepare reloads the model"
        )
    }

    func testReleaseIdleResourcesEvictsParakeetManagerAfterDelay() async throws {
        let descriptor = BuiltInModelCatalog.parakeetTDT06Bv3
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let diagnosticsSink = InMemoryTestSink()
        let manager = StubFluidAudioParakeetManager()
        let adapter = FluidAudioParakeetTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            logger: makeTranscriptionLogger(sink: diagnosticsSink),
            idleUnloadDelay: .milliseconds(20)
        )

        try await adapter.prepare()
        await adapter.releaseIdleResources()
        try? await Task.sleep(for: .milliseconds(60))
        try await adapter.prepare()

        let cleanupCount = await manager.cleanupCallCount()
        let loadCount = await manager.loadCallCount()
        XCTAssertEqual(cleanupCount, 1)
        XCTAssertEqual(loadCount, 2)

        let releaseLog = try await waitForTranscriptionLogMessage(
            in: diagnosticsSink,
            containing: "adapter_idle_release"
        )
        XCTAssertTrue(releaseLog.message.contains("descriptorID=\(descriptor.id)"))
        XCTAssertTrue(releaseLog.message.contains("adapter=FluidAudioParakeetTranscriberAdapter"))
        XCTAssertTrue(releaseLog.message.contains("releasedAfterMs=20"))
        XCTAssertTrue(releaseLog.message.contains("hadPrepared=true"))
        XCTAssertTrue(releaseLog.message.contains("hadInFlightPrepare=false"))
    }

    func testReleaseIdleResourcesCancelsIfNewSessionStartsBeforeDelay() async throws {
        let descriptor = BuiltInModelCatalog.parakeetTDT06Bv3
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let diagnosticsSink = InMemoryTestSink()
        let manager = StubFluidAudioParakeetManager()
        let adapter = FluidAudioParakeetTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            logger: makeTranscriptionLogger(sink: diagnosticsSink),
            idleUnloadDelay: .milliseconds(20)
        )

        try await adapter.prepare()
        await adapter.releaseIdleResources()
        try? await Task.sleep(for: .milliseconds(5))
        try await adapter.prepare()
        try? await Task.sleep(for: .milliseconds(60))
        try await adapter.prepare()

        let cleanupCount = await manager.cleanupCallCount()
        let loadCount = await manager.loadCallCount()
        XCTAssertEqual(cleanupCount, 0)
        XCTAssertEqual(loadCount, 1)
        let releaseLogs = await diagnosticsSink.snapshot().filter {
            $0.message.contains("adapter_idle_release")
        }
        XCTAssertTrue(releaseLogs.isEmpty)
    }

    func testReleaseIdleResourcesIsNoOpWhenNothingPrepared() async throws {
        let descriptor = BuiltInModelCatalog.parakeetTDT06Bv3
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let diagnosticsSink = InMemoryTestSink()
        let manager = StubFluidAudioParakeetManager()
        let adapter = FluidAudioParakeetTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager,
            logger: makeTranscriptionLogger(sink: diagnosticsSink),
            idleUnloadDelay: .milliseconds(20)
        )

        await adapter.releaseIdleResources()
        try? await Task.sleep(for: .milliseconds(60))

        let cleanupCount = await manager.cleanupCallCount()
        let loadCount = await manager.loadCallCount()
        XCTAssertEqual(cleanupCount, 0)
        XCTAssertEqual(loadCount, 0)
        let releaseLogs = await diagnosticsSink.snapshot().filter {
            $0.message.contains("adapter_idle_release")
        }
        XCTAssertTrue(releaseLogs.isEmpty)
    }

    func testNonHybridParakeetDownloadIfNeededDoesNotPullAuxiliary() async throws {
        // v3 (and v2) are single-repo Parakeet variants — no CTC head.
        let descriptor = BuiltInModelCatalog.parakeetTDT06Bv3
        let storageLocator = TestStorageLocator(baseDirectory: try temporaryRootDirectory())
        let manager = StubFluidAudioParakeetManager()
        let adapter = FluidAudioParakeetTranscriberAdapter(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: manager
        )

        try await adapter.downloadIfNeeded()

        let auxCalls = await manager.auxiliaryDownloadCalls()
        XCTAssertTrue(
            auxCalls.isEmpty,
            "Only the 110m hybrid descriptor should trigger the auxiliary download"
        )
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
    private var downloadIfNeededCallCountStorage = 0
    private var downloadIfNeededDirectoriesStorage: [URL] = []
    private var auxiliaryDownloadCallsStorage: [(aux: ParakeetAuxiliaryRepo, directory: URL)] = []
    private var loadCallCountStorage = 0
    private var loadedVersionsStorage: [AsrModelVersion] = []
    private var loadedDirectoriesStorage: [URL] = []
    private var transcribeCallCountStorage = 0
    private var lastSamplesStorage: [Float] = []
    private var cleanupCallCountStorage = 0

    init(
        result: FluidAudioParakeetManagerResult = .init(
            text: "",
            processingDuration: .zero
        )
    ) {
        self.result = result
    }

    func downloadIfNeeded(
        to directory: URL,
        version: AsrModelVersion,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws {
        _ = progressHandler
        downloadIfNeededCallCountStorage += 1
        downloadIfNeededDirectoriesStorage.append(directory)
    }

    func downloadAuxiliary(
        _ aux: ParakeetAuxiliaryRepo,
        to directory: URL,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws {
        _ = progressHandler
        auxiliaryDownloadCallsStorage.append((aux: aux, directory: directory))
    }

    func auxiliaryDownloadCalls() -> [(aux: ParakeetAuxiliaryRepo, directory: URL)] {
        auxiliaryDownloadCallsStorage
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

    func cleanup() async {
        cleanupCallCountStorage += 1
    }

    func downloadIfNeededCallCount() -> Int {
        downloadIfNeededCallCountStorage
    }

    func downloadIfNeededDirectories() -> [URL] {
        downloadIfNeededDirectoriesStorage
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

    func cleanupCallCount() -> Int {
        cleanupCallCountStorage
    }
}
