import AppKit
import Combine
import XCTest
import PersonalScribeCore
import PersonalScribeSession
@testable import PersonalScribeAppKit

@MainActor
final class AppCompositionTests: XCTestCase {
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
        let suiteName = "AppCompositionTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let modelService = ActiveModelService(
            activeIDsPreference: Preference(key: ActiveModelService.preferenceKey, default: [:], defaults: defaults),
            isDownloaded: { _ in downloaded.value },
            download: { _, _ in },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )
        let (snapshots, continuation) = AsyncStream<SessionSnapshot>.makeStream()
        let task = AppComposition.refreshModelCacheWhenPreparationEnds(snapshots: snapshots, modelService: modelService)
        defer { task.cancel() }
        let descriptor = BuiltInModelCatalog.parakeetTDT06Bv2

        continuation.yield(SessionSnapshot(modelDownloadProgress: ModelDownloadProgress(
            phase: .downloading, fractionCompleted: 0.5, receivedBytes: 5, expectedBytes: 10
        )))
        downloaded.value = true
        continuation.yield(SessionSnapshot(modelDownloadProgress: nil))

        await waitUntil { modelService.downloadStates[descriptor.id]?.phase == .ready }
        XCTAssertEqual(modelService.downloadStates[descriptor.id]?.phase, .ready)
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
