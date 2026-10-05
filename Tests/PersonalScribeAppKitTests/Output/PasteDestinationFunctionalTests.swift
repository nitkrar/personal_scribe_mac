import AppKit
import XCTest
import PersonalScribeCore
import PersonalScribeSession
import PersonalScribeTestSupport
@testable import PersonalScribeAppKit

/// #117 end to end: real coordinator, output stage, clipboard paste,
/// database and metrics. Only audio, ⌘V and the frontmost app are faked.
@MainActor
final class PasteDestinationFunctionalTests: XCTestCase {
    func testPasteIntoAnotherAppRecordsItAndCountsInAppsUsed() async throws {
        let outcome = try await dictate(
            into: .frontmost(bundleID: "com.apple.Notes", pid: 4242, appName: "Notes")
        )

        XCTAssertEqual(outcome.destinations, ["Notes"])
        XCTAssertEqual(outcome.appsUsed, 1)
    }

    func testClipboardOnlyDeliveryStaysClipboardAndIsNotCounted() async throws {
        let outcome = try await dictate(
            into: .frontmost(bundleID: AppBrand.bundleIdentifier, pid: 4242, appName: AppBrand.displayName)
        )

        XCTAssertEqual(outcome.destinations, [TranscriptEntry.clipboardDestination])
        XCTAssertEqual(outcome.appsUsed, 0)
    }

    private func dictate(into target: PasteTarget) async throws -> (destinations: [String?], appsUsed: Int) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteDestinationFunctionalTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let database = try AppDatabase(
            locator: AppStorageLocator(environment: [:], testingBaseDirectoryOverrideProvider: { base })
        )
        let logger = PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        let repository = TranscriptRepository(database: database, logger: logger)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("personal_scribe.test.\(UUID().uuidString)"))
        let snapshots = PasteboardSnapshotService(
            itemsReader: { pasteboard.pasteboardItems ?? [] },
            itemsWriter: { items in
                pasteboard.clearContents()
                pasteboard.writeObjects(items)
            },
            stringWriter: { string in
                pasteboard.clearContents()
                return pasteboard.setString(string, forType: .string)
            },
            changeCountReader: { pasteboard.changeCount }
        )
        let outputStage = SessionOutputStage(
            live: LiveCursorOutput(logger: logger, snapshotService: snapshots, isAccessibilityTrusted: { true }),
            batch: ClipboardBatchOutput(
                logger: logger,
                snapshotService: snapshots,
                scheduleRestore: { _, _ in },
                isAccessibilityTrusted: { true },
                pasteShortcutPoster: { _ in true },
                pasteTarget: { target }
            ),
            logger: logger
        )
        let suiteName = "PasteDestinationFunctionalTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let activeModels = Preference<[ModelKind: String]>(
            key: ActiveModelService.preferenceKey,
            default: [:],
            defaults: defaults
        )
        activeModels.persist([.asr: BuiltInModelCatalog.parakeetTDTCTC110M.id])
        let modelService = ActiveModelService(
            activeIDsPreference: activeModels,
            isDownloaded: { _ in true },
            download: { _, _ in },
            logger: logger
        )
        let availableKinds: @Sendable () -> Set<ModelKind> = { Set(ModelKind.allCases.filter(\.isEnabled)) }
        let coordinator = SessionCoordinator(
            capture: FakeAudioCapturer(
                buffers: [try PCMBuffer(samples: Array(repeating: 0.1, count: 16_000), timestamp: ContinuousClock().now)]
            ),
            modelService: modelService,
            processorProvider: FixedTranscriberProvider(
                transcriber: FakeTranscriber(
                    result: TranscriptionResult(text: "hello there", audioDuration: .seconds(1), processingDuration: .zero)
                )
            ),
            logger: logger,
            transcriptRepository: repository,
            workflowModeRegistry: try WorkflowModeRegistry(
                store: InMemoryWorkflowModeStore(),
                availableKindsProvider: availableKinds
            ),
            availableKindsProvider: availableKinds,
            outputSink: outputStage
        )

        await coordinator.toggle()
        await coordinator.toggle()
        for _ in 0..<200 where await coordinator.snapshot().sessionState != .completed {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(pasteboard.string(forType: .string), "Hello there.")

        let metrics = SQLiteMetricsService(appDatabase: database, logger: logger)
        let snapshot = try await metrics.loadSnapshot(
            window: MetricsWindow(start: .distantPast, end: Date()),
            recentLimit: 0
        )
        return (await repository.recent(limit: 10).map(\.destinationApp), snapshot.rollups.appsUsed)
    }
}

private struct FixedTranscriberProvider: ModelBoundProcessorProviding, @unchecked Sendable {
    let transcriber: any Transcriber

    func transcriber(for descriptor: ModelDescriptor) throws -> any Transcriber { transcriber }
    func streamingTranscriber(for descriptor: ModelDescriptor) throws -> any StreamingTranscriber {
        throw ModelSelectionError.descriptorNotRegistered(id: descriptor.id)
    }
    func diarizer(for descriptor: ModelDescriptor) throws -> any SpeakerDiarizer {
        throw ModelSelectionError.descriptorNotRegistered(id: descriptor.id)
    }
    func isDownloaded(_ descriptor: ModelDescriptor) -> Bool { true }
    func download(
        _ descriptor: ModelDescriptor,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {}
    func removeDownloadedFiles(_ descriptor: ModelDescriptor) throws {}
    func evict(_ descriptor: ModelDescriptor) {}
    func preparedDescriptors() -> [ModelDescriptor] { [] }
}
