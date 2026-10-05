import AppKit
import Combine
import XCTest
import PersonalScribeCore
import PersonalScribeSession
import PersonalScribeTestSupport
@testable import PersonalScribeAppKit

@MainActor
final class AppCompositionTests: XCTestCase {
    func testSelectingCurrentModeDoesNotFinalizeOrMutate() async {
        var events: [String] = []

        await AppComposition.selectModeIfNeeded(
            selectedModeID: "dictation",
            currentModeID: "dictation",
            finalizePaused: { events.append("finalize") },
            setCurrent: { events.append("set:\($0)") }
        )

        XCTAssertTrue(events.isEmpty)
    }

    func testSelectingDifferentModeFinalizesBeforeSwitch() async {
        var events: [String] = []

        await AppComposition.selectModeIfNeeded(
            selectedModeID: "notes",
            currentModeID: "dictation",
            finalizePaused: { events.append("finalize") },
            setCurrent: { events.append("set:\($0)") }
        )

        XCTAssertEqual(events, ["finalize", "set:notes"])
    }

    func testCurrentModeHotkeyStopsPausedSessionWithStandardPasteDelivery() async throws {
        let hotkey = HotkeyPreference(
            keyCode: 0,
            tapCount: 1,
            modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue
        )
        let mode = WorkflowMode(
            id: "medical",
            name: "Medical",
            glyph: "mic",
            hotkey: hotkey,
            pipelineShape: .batch,
            processors: [
                .transcriber(kind: .asr, descriptorID: BuiltInModelCatalog.parakeetTDTCTC110M.id),
            ],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste(enabled: .override(true))]
        )
        let registry = try WorkflowModeRegistry(
            store: InMemoryWorkflowModeStore(
                initial: WorkflowModeDocument(defaultModeID: mode.id, customModes: [mode])
            ),
            availableKindsProvider: { Set(ModelKind.allCases) }
        )
        registry.setCurrent(id: mode.id)
        let buffer = try PCMBuffer(
            samples: Array(repeating: 0.1, count: 16_000),
            timestamp: ContinuousClock().now
        )
        let sink = HotkeyOutputSink()
        let coordinator = SessionCoordinator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            transcriber: FakeTranscriber(
                result: TranscriptionResult(
                    text: "paste me",
                    audioDuration: .seconds(1),
                    processingDuration: .zero
                )
            ),
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session),
            outputSink: sink
        )
        let monitor = GlobalHotkeyMonitor(onToggle: {})
        AppComposition.configurePerModeHotkeys(
            on: monitor,
            registry: registry,
            coordinator: coordinator,
            modelService: makePinnedAsrModelService()
        )

        await coordinator.toggle()
        try await Task.sleep(for: .milliseconds(20))
        await coordinator.pauseIfRecording()
        let pausedState = await coordinator.state()
        XCTAssertEqual(pausedState, .paused)

        monitor.handle(event: try makeKeyDownEvent(
            keyCode: 0,
            modifierFlags: [.command, .option],
            characters: "a",
            timestamp: 1
        ))
        for _ in 0..<200 {
            if await !sink.deliverySinks().isEmpty { break }
            try? await Task.sleep(for: .milliseconds(5))
        }

        let deliverySinks = await sink.deliverySinks()
        XCTAssertEqual(deliverySinks, [[.frontmostPaste(enabled: true)]])
        XCTAssertEqual(registry.currentMode.id, mode.id)
    }

    func testMakePermissionServiceReturnsProductionType() {
        let service = AppComposition.makePermissionService()

        XCTAssertEqual(
            String(reflecting: type(of: service)),
            String(reflecting: AppKitPermissionService.self)
        )
    }

    func testConfigurePerModeHotkeysWiresProvidedMonitorToRegistryCurrentMode() async throws {
        let perModeHotkey = HotkeyPreference(
            keyCode: 0, // 'a'
            tapCount: 1,
            modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue
        )
        let mode = WorkflowMode(
            id: "med-notes",
            name: "Medical Notes",
            glyph: "mic",
            hotkey: perModeHotkey,
            pipelineShape: .batch,
            processors: [
                .transcriber(
                    kind: .asr,
                    descriptorID: BuiltInModelCatalog.parakeetTDTCTC110M.id
                )
            ],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste(enabled: .override(true))]
        )
        let registry = try WorkflowModeRegistry(
            store: InMemoryWorkflowModeStore(
                initial: WorkflowModeDocument(defaultModeID: nil, customModes: [mode])
            ),
            availableKindsProvider: { Set(ModelKind.allCases) }
        )
        let modelService = makePinnedAsrModelService()
        let coordinator = DevelopmentComposition.makeTestingSessionCoordinator()
        let monitor = GlobalHotkeyMonitor(onToggle: { })

        AppComposition.configurePerModeHotkeys(
            on: monitor,
            registry: registry,
            coordinator: coordinator,
            modelService: modelService
        )

        monitor.handle(event: try makeKeyDownEvent(
            keyCode: 0,
            modifierFlags: [.command, .option],
            characters: "a",
            timestamp: 1.0
        ))

        for _ in 0..<100 where registry.currentMode.id != "med-notes" {
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(registry.currentMode.id, "med-notes")
    }

    func testObservePerModeHotkeysUpdatesProvidedMonitorWhenModeSaved() async throws {
        let perModeHotkey = HotkeyPreference(
            keyCode: 0, // 'a'
            tapCount: 1,
            modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue
        )
        let mode = WorkflowMode(
            id: "med-notes",
            name: "Medical Notes",
            glyph: "mic",
            hotkey: perModeHotkey,
            pipelineShape: .batch,
            processors: [
                .transcriber(
                    kind: .asr,
                    descriptorID: BuiltInModelCatalog.parakeetTDTCTC110M.id
                )
            ],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste(enabled: .override(true))]
        )
        let registry = try WorkflowModeRegistry(
            store: InMemoryWorkflowModeStore(),
            availableKindsProvider: { Set(ModelKind.allCases) }
        )
        let modelService = makePinnedAsrModelService()
        let coordinator = DevelopmentComposition.makeTestingSessionCoordinator()
        let monitor = GlobalHotkeyMonitor(onToggle: { })
        let observation = AppComposition.observePerModeHotkeys(
            on: monitor,
            registry: registry,
            coordinator: coordinator,
            modelService: modelService
        )
        defer { observation.cancel() }

        try registry.saveCustom(mode)

        await waitUntil {
            do {
                monitor.handle(event: try self.makeKeyDownEvent(
                    keyCode: 0,
                    modifierFlags: [.command, .option],
                    characters: "a",
                    timestamp: 1.0
                ))
            } catch {
                XCTFail("Failed to synthesize per-mode keyDown: \(error)")
            }
            return registry.currentMode.id == "med-notes"
        }

        XCTAssertEqual(registry.currentMode.id, "med-notes")
    }

    func testPerModeHotkeyRegistersOnceItsModelBecomesAvailable() async throws {
        let mode = WorkflowMode(
            id: "needs-asr",
            name: "Needs ASR",
            glyph: "mic",
            hotkey: HotkeyPreference(
                keyCode: 0, // 'a'
                tapCount: 1,
                modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue
            ),
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste(enabled: .override(true))]
        )
        let registry = try WorkflowModeRegistry(
            store: InMemoryWorkflowModeStore(initial: WorkflowModeDocument(defaultModeID: nil, customModes: [mode])),
            availableKindsProvider: { Set(ModelKind.allCases) }
        )
        let downloaded = DownloadedFlag()
        let suiteName = "AppCompositionTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let modelService = ActiveModelService(
            activeIDsPreference: Preference(key: ActiveModelService.preferenceKey, default: [:], defaults: defaults),
            isDownloaded: { _ in downloaded.value },
            download: { _, _ in },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )
        let monitor = GlobalHotkeyMonitor(onToggle: { })
        let observation = AppComposition.observePerModeHotkeys(
            on: monitor,
            registry: registry,
            coordinator: DevelopmentComposition.makeTestingSessionCoordinator(),
            modelService: modelService
        )
        defer { observation.cancel() }
        try await Task.sleep(for: .milliseconds(100))
        monitor.handle(event: try makeKeyDownEvent(
            keyCode: 0, modifierFlags: [.command, .option], characters: "a", timestamp: 0.5
        ))
        XCTAssertEqual(registry.currentMode.id, "dictation", "hotkey must be inert while the model is missing")

        downloaded.value = true
        modelService.refresh()
        modelService.setActive(BuiltInModelCatalog.parakeetTDT06Bv2, forKind: .asr)

        await waitUntil {
            do {
                monitor.handle(event: try self.makeKeyDownEvent(
                    keyCode: 0,
                    modifierFlags: [.command, .option],
                    characters: "a",
                    timestamp: 1.0
                ))
            } catch {
                XCTFail("Failed to synthesize per-mode keyDown: \(error)")
            }
            return registry.currentMode.id == "needs-asr"
        }
        XCTAssertEqual(registry.currentMode.id, "needs-asr")
    }

    func testModelCacheRefreshesWhenPreparationProgressEnds() async throws {
        let downloaded = DownloadedFlag()
        let descriptor = BuiltInModelCatalog.parakeetTDT06Bv2
        let suiteName = "AppCompositionTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let modelService = ActiveModelService(
            activeIDsPreference: Preference(
                key: ActiveModelService.preferenceKey,
                default: [.asr: descriptor.id],
                defaults: defaults
            ),
            isDownloaded: { _ in downloaded.value },
            download: { _, _ in },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )
        let (snapshots, continuation) = AsyncStream<SessionSnapshot>.makeStream()
        let task = AppComposition.refreshModelCacheWhenPreparationEnds(snapshots: snapshots, modelService: modelService)
        defer { task.cancel() }
        continuation.yield(SessionSnapshot(modelDownloadProgress: ModelDownloadProgress(
            phase: .downloading, fractionCompleted: 0.5, receivedBytes: 5, expectedBytes: 10
        ), modelDownloadDescriptorID: descriptor.id))
        await waitUntil { modelService.downloadStates[descriptor.id]?.phase == .downloading }
        XCTAssertEqual(modelService.downloadStates[descriptor.id]?.fractionCompleted, 0.5)
        downloaded.value = true
        continuation.yield(SessionSnapshot(modelDownloadProgress: nil))

        await waitUntil { modelService.downloadStates[descriptor.id]?.phase == .ready }
        XCTAssertEqual(modelService.downloadStates[descriptor.id]?.phase, .ready)
    }

    func testPreparationProgressStaysWithPreparedModelAfterActiveModelSwitch() async throws {
        let prepared = BuiltInModelCatalog.parakeetTDT06Bv2
        let newlyActive = BuiltInModelCatalog.parakeetTDTCTC110M
        let suiteName = "AppCompositionTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = ActiveModelService(
            activeIDsPreference: Preference(
                key: ActiveModelService.preferenceKey,
                default: [.asr: prepared.id],
                defaults: defaults
            ),
            isDownloaded: { _ in false },
            download: { _, _ in },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )
        let (snapshots, continuation) = AsyncStream<SessionSnapshot>.makeStream()
        let task = AppComposition.refreshModelCacheWhenPreparationEnds(
            snapshots: snapshots,
            modelService: service
        )
        defer { task.cancel() }

        service.setActive(newlyActive, forKind: .asr)
        continuation.yield(SessionSnapshot(
            modelDownloadProgress: ModelDownloadProgress(
                phase: .downloading,
                fractionCompleted: 0.4,
                receivedBytes: 4,
                expectedBytes: 10
            ),
            modelDownloadDescriptorID: prepared.id
        ))

        await waitUntil { service.downloadStates[prepared.id]?.phase == .downloading }
        XCTAssertEqual(service.downloadStates[prepared.id]?.fractionCompleted, 0.4)
        XCTAssertEqual(service.downloadStates[newlyActive.id]?.phase, .notDownloaded)
    }

    func testReporterIncludesDebugFileSink() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let reporter = AppComposition.makeDiagnosticsReporter(
            storageLocatorProvider: { TestStorageLocator(baseDirectory: tempDirectory) },
            diagnosticLoggingModeProvider: { .verbose },
            diagnosticsStore: DiagnosticsStore(capacity: 20)
        )

        reporter.debug("debug-only", category: PersonalScribeLogCategory.app)
        reporter.info("info-only", category: PersonalScribeLogCategory.app)

        let debugContents = try await waitForLogContents(named: "debug.log", in: tempDirectory)
        let diagnosticsContents = try await waitForLogContents(named: "diagnostics.log", in: tempDirectory)

        XCTAssertTrue(debugContents.contains("level=debug"))
        XCTAssertTrue(debugContents.contains("message=\"debug-only\""))
        XCTAssertTrue(diagnosticsContents.contains("level=info"))
        XCTAssertTrue(diagnosticsContents.contains("message=\"info-only\""))
        XCTAssertFalse(diagnosticsContents.contains("message=\"debug-only\""))
    }

    func testReporterWritesInfoToDiagnosticsLogInDefaultErrorsOnlyMode() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let reporter = AppComposition.makeDiagnosticsReporter(
            storageLocatorProvider: { TestStorageLocator(baseDirectory: tempDirectory) },
            diagnosticLoggingModeProvider: { .errorsOnly },
            diagnosticsStore: DiagnosticsStore(capacity: 20)
        )

        reporter.info("session-evidence", category: PersonalScribeLogCategory.session)

        let diagnosticsContents = try await waitForLogContents(named: "diagnostics.log", in: tempDirectory)
        XCTAssertTrue(diagnosticsContents.contains("message=\"session-evidence\""))
    }

    private func makePinnedAsrModelService() -> ActiveModelService {
        let suiteName = "AppCompositionTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ActiveModelService(
            defaults: defaults,
            physicalMemoryBytes: 8_000_000_000,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )
    }

    private func makeKeyDownEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        characters: String,
        timestamp: TimeInterval
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: timestamp,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters.lowercased(),
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(10),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(for: pollInterval, tolerance: pollInterval)
        }
        XCTFail("Timed out waiting for condition after \(timeout)")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func waitForLogContents(named fileName: String, in baseDirectory: URL) async throws -> String {
        let url = baseDirectory
            .appendingPathComponent(ManagedDirectory.logs.pathComponent, isDirectory: true)
            .appendingPathComponent(fileName)

        for _ in 0..<100 {
            if let contents = try? String(contentsOf: url, encoding: .utf8) {
                return contents
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for log at \(url.path)")
        return ""
    }
}

@MainActor
private final class FakePermissionService: PermissionService {
    @Published private(set) var statuses: [Permission: PermissionStatus] = [
        .microphone: .granted,
        .accessibility: .granted,
    ]

    func status(for permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .pending
    }

    func request(_ permission: Permission) async -> RequestOutcome {
        RequestOutcome(
            prompted: false,
            openedSettings: false,
            requiresRelaunch: false,
            finalStatus: status(for: permission)
        )
    }

    func statusSnapshot() -> [Permission: PermissionStatus] {
        statuses
    }

    func refresh() {}

    func systemSettingsDeepLink(for permission: Permission) -> URL {
        URL(string: "https://example.invalid/\(permission.rawValue)")!
    }
}

private struct TestStorageLocator: StorageLocator {
    let baseDirectory: URL

    func url(for directory: ManagedDirectory) -> URL {
        baseDirectory
            .appendingPathComponent(directory.pathComponent, isDirectory: true)
            .standardizedFileURL
    }

    func ensureDirectoriesExist() throws {}
}

private final class DownloadedFlag: @unchecked Sendable {
    var value = false
}

private actor HotkeyOutputSink: PipelineOutputSink {
    private var sinks: [[BoundOutputSink]] = []

    func deliverPartial(_ revision: TranscriptProgress) async throws {}

    func deliverFinal(_ result: TranscriptionResult, sinks: [BoundOutputSink]) async throws -> String? {
        self.sinks.append(sinks)
        return nil
    }

    func resetForNewSession() async {}

    func deliverySinks() -> [[BoundOutputSink]] {
        sinks
    }
}
