import Foundation
import XCTest
import PersonalScribeCore
import PersonalScribeSession
@testable import PersonalScribeAppKit

@MainActor
final class AdvancedTabViewModelTests: XCTestCase {
    func testChangeBaseDirectory_schedulesMoveAndAsksForRestart() {
        let currentBase = URL(fileURLWithPath: "/tmp/current-base", isDirectory: true).standardizedFileURL
        let selectedBase = URL(fileURLWithPath: "/tmp/next-base", isDirectory: true).standardizedFileURL
        let migrator = FakeBaseDirectoryMigrator(outcome: .success(selectedBase))
        let viewModel = AdvancedTabViewModel(
            baseDirectoryResult: .success(currentBase),
            migrator: migrator,
            selectDirectory: { _ in selectedBase }
        )

        viewModel.changeBaseDirectory()

        XCTAssertEqual(migrator.recordedDestinations, [selectedBase])
        XCTAssertEqual(try? viewModel.baseDirectoryResult.get(), currentBase, "location changes only after restart")
        guard case .success(let message)? = viewModel.feedback else {
            return XCTFail("Expected a restart prompt.")
        }
        XCTAssertTrue(message.contains("Restart"))
        XCTAssertTrue(message.contains(selectedBase.path))
    }

    // Bug #006 regression: `openInFinder` must receive the resolved base
    // directory, not its parent. Prior behaviour used
    // `NSWorkspace.activateFileViewerSelecting([url])`, which opens the
    // PARENT with `url` highlighted — so clicking "Open in Finder" on
    // the Advanced tab surfaced `~/Library/Application Support/` with
    // `personal_scribe` selected, not the contents of `personal_scribe/`.
    func testRevealInFinder_opensResolvedBaseDirectory_notParent() {
        let baseDirectory = URL(
            fileURLWithPath: "/Users/example/Library/Application Support/personal_scribe",
            isDirectory: true
        ).standardizedFileURL
        var openedURLs: [URL] = []

        let viewModel = AdvancedTabViewModel(
            baseDirectoryResult: .success(baseDirectory),
            migrator: FakeBaseDirectoryMigrator(outcome: .success(nil)),
            selectDirectory: { _ in nil },
            openInFinder: { openedURLs.append($0) }
        )

        viewModel.revealInFinder()

        XCTAssertEqual(openedURLs, [baseDirectory])
        XCTAssertNotEqual(
            openedURLs.first,
            baseDirectory.deletingLastPathComponent(),
            "Opening the parent directory is the bug #006 regression — must open `personal_scribe/` itself."
        )
    }

    func testRevealInFinder_isNoOpWhenBaseDirectoryResolutionFailed() {
        var openedURLs: [URL] = []

        let viewModel = AdvancedTabViewModel(
            baseDirectoryResult: .failure(StubMigrationError(message: "unresolvable")),
            migrator: FakeBaseDirectoryMigrator(outcome: .success(nil)),
            selectDirectory: { _ in nil },
            openInFinder: { openedURLs.append($0) }
        )

        viewModel.revealInFinder()

        XCTAssertTrue(openedURLs.isEmpty, "Must not call openInFinder when the base directory is unresolvable.")
    }

    func testRevealLogFile_opensFileWhenItExists() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let locator = AdvancedTabTestStorageLocator(baseDirectory: tempDirectory)
        let logsDir = locator.url(for: .logs)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let errorsLog = logsDir.appendingPathComponent("errors.log", isDirectory: false)
        try Data("hello".utf8).write(to: errorsLog)

        var openedURLs: [URL] = []

        let viewModel = AdvancedTabViewModel(
            baseDirectoryResult: .success(tempDirectory),
            migrator: FakeBaseDirectoryMigrator(outcome: .success(nil)),
            selectDirectory: { _ in nil },
            openInFinder: { openedURLs.append($0) },
            storageLocator: locator
        )

        viewModel.revealLogFile(named: "errors.log")

        XCTAssertEqual(openedURLs, [errorsLog])
    }

    func testRevealLogFile_fallsBackToLogsDirectoryWhenFileMissing() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let locator = AdvancedTabTestStorageLocator(baseDirectory: tempDirectory)

        var openedURLs: [URL] = []

        let viewModel = AdvancedTabViewModel(
            baseDirectoryResult: .success(tempDirectory),
            migrator: FakeBaseDirectoryMigrator(outcome: .success(nil)),
            selectDirectory: { _ in nil },
            openInFinder: { openedURLs.append($0) },
            storageLocator: locator
        )

        viewModel.revealLogFile(named: "debug.log")

        XCTAssertEqual(openedURLs, [locator.url(for: .logs)])
    }

    func testChangeBaseDirectory_reportsErrorMessageOnFailure() {
        let selectedBase = URL(fileURLWithPath: "/tmp/next-base", isDirectory: true).standardizedFileURL
        let viewModel = AdvancedTabViewModel(
            baseDirectoryResult: .success(URL(fileURLWithPath: "/tmp/current-base", isDirectory: true)),
            migrator: FakeBaseDirectoryMigrator(
                outcome: .failure(StubMigrationError(message: "The selected base directory is not writable."))
            ),
            selectDirectory: { _ in selectedBase }
        )

        viewModel.changeBaseDirectory()

        XCTAssertEqual(viewModel.feedback, .failure("The selected base directory is not writable."))
    }

    func testDiagnosticLoggingModePersistsUpdates() {
        let defaults = isolatedDefaults()

        let viewModel = AdvancedTabViewModel(
            baseDirectoryResult: .success(URL(fileURLWithPath: "/tmp/base", isDirectory: true)),
            defaults: defaults,
            migrator: FakeBaseDirectoryMigrator(outcome: .success(nil)),
            selectDirectory: { _ in nil }
        )

        XCTAssertEqual(viewModel.diagnosticLoggingMode, .errorsOnly)

        viewModel.setDiagnosticLoggingMode(.verbose)

        XCTAssertEqual(viewModel.diagnosticLoggingMode, .verbose)
        XCTAssertEqual(DiagnosticLoggingMode.resolve(from: defaults), .verbose)

        viewModel.setDiagnosticLoggingMode(.errorsOnly)

        XCTAssertEqual(viewModel.diagnosticLoggingMode, .errorsOnly)
        XCTAssertEqual(DiagnosticLoggingMode.resolve(from: defaults), .errorsOnly)
    }

    func testRecordAudioEnabledPreferenceRoundtrips() {
        let defaults = isolatedDefaults()
        let viewModel = AdvancedTabViewModel(
            baseDirectoryResult: .success(URL(fileURLWithPath: "/tmp/base", isDirectory: true)),
            defaults: defaults,
            migrator: FakeBaseDirectoryMigrator(outcome: .success(nil)),
            selectDirectory: { _ in nil }
        )

        viewModel.setRecordAudioEnabled(false)

        XCTAssertFalse(viewModel.recordAudioEnabled)
        XCTAssertFalse(RecordAudioEnabledPreference.resolve(from: defaults))

        viewModel.setRecordAudioEnabled(true)

        XCTAssertTrue(viewModel.recordAudioEnabled)
        XCTAssertTrue(RecordAudioEnabledPreference.resolve(from: defaults))
    }

    func testRecordAudioEnabledDefaultsToTrue() {
        let defaults = isolatedDefaults()
        let viewModel = AdvancedTabViewModel(
            baseDirectoryResult: .success(URL(fileURLWithPath: "/tmp/base", isDirectory: true)),
            defaults: defaults,
            migrator: FakeBaseDirectoryMigrator(outcome: .success(nil)),
            selectDirectory: { _ in nil }
        )

        XCTAssertTrue(viewModel.recordAudioEnabled)
        XCTAssertTrue(RecordAudioEnabledPreference.resolve(from: defaults))
    }

    func testOpenDiagnosticsWindowInvokesInjectedAction() {
        var openCount = 0
        let viewModel = AdvancedTabViewModel(
            baseDirectoryResult: .success(URL(fileURLWithPath: "/tmp/base", isDirectory: true)),
            migrator: FakeBaseDirectoryMigrator(outcome: .success(nil)),
            selectDirectory: { _ in nil },
            openDiagnosticsWindow: { openCount += 1 }
        )

        viewModel.openDiagnosticsWindow()
        viewModel.openDiagnosticsWindow()

        XCTAssertEqual(openCount, 2)
    }

    func testLogRetentionDaysDefaultsToFourteenAndPersistsUpdates() {
        let defaults = isolatedDefaults()
        let viewModel = AdvancedTabViewModel(
            baseDirectoryResult: .success(URL(fileURLWithPath: "/tmp/base", isDirectory: true)),
            defaults: defaults,
            migrator: FakeBaseDirectoryMigrator(outcome: .success(nil)),
            selectDirectory: { _ in nil }
        )

        XCTAssertEqual(viewModel.logRetentionDays, 14)
        XCTAssertEqual(LogRetentionDaysPreference.resolve(from: defaults), 14)

        viewModel.setLogRetentionDays(30)

        XCTAssertEqual(viewModel.logRetentionDays, 30)
        XCTAssertEqual(LogRetentionDaysPreference.resolve(from: defaults), 30)

        viewModel.setLogRetentionDays(0)

        XCTAssertEqual(viewModel.logRetentionDays, 0)
        XCTAssertEqual(LogRetentionDaysPreference.resolve(from: defaults), 0)
    }

    func testLogMaxFilesDefaultsToThirtyAndPersistsClampedUpdates() {
        let defaults = isolatedDefaults()
        let viewModel = AdvancedTabViewModel(
            baseDirectoryResult: .success(URL(fileURLWithPath: "/tmp/base", isDirectory: true)),
            defaults: defaults,
            migrator: FakeBaseDirectoryMigrator(outcome: .success(nil)),
            selectDirectory: { _ in nil }
        )

        XCTAssertEqual(viewModel.logMaxFiles, 30)

        viewModel.setLogMaxFiles(5)

        XCTAssertEqual(viewModel.logMaxFiles, 5)
        XCTAssertEqual(LogMaxFilesPreference.resolve(from: defaults), 5)

        viewModel.setLogMaxFiles(10_000)

        XCTAssertEqual(viewModel.logMaxFiles, LogMaxFilesPreference.maximum)
        XCTAssertEqual(LogMaxFilesPreference.resolve(from: defaults), LogMaxFilesPreference.maximum)
    }

    func testWhisperAdapterFilterMirrorsModelServiceAndPersistsUpdates() {
        let defaults = isolatedDefaults()
        let modelService = ActiveModelService(
            activeIDsPreference: Preference<[ModelKind: String]>(
                key: ActiveModelService.preferenceKey,
                default: [:],
                defaults: defaults
            ),
            registeredModels: [
                BuiltInModelCatalog.whisperKitSmall216MB,
                BuiltInModelCatalog.whisperCppSmallQ51,
            ],
            isDownloaded: { _ in true },
            download: { _, _ in },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )
        let viewModel = AdvancedTabViewModel(
            baseDirectoryResult: .success(URL(fileURLWithPath: "/tmp/base", isDirectory: true)),
            defaults: defaults,
            modelService: modelService,
            migrator: FakeBaseDirectoryMigrator(outcome: .success(nil)),
            selectDirectory: { _ in nil }
        )

        XCTAssertEqual(viewModel.whisperAdapterFilter, .both)

        viewModel.setWhisperAdapterFilter(.bridge)

        XCTAssertEqual(viewModel.whisperAdapterFilter, .bridge)
        XCTAssertEqual(modelService.whisperAdapterFilter, .bridge)
        XCTAssertEqual(WhisperAdapterFilter.resolve(from: defaults), .bridge)
    }

    func testAudioRetentionPersistsAllowedValues() {
        let defaults = isolatedDefaults()
        let viewModel = AdvancedTabViewModel(
            baseDirectoryResult: .success(URL(fileURLWithPath: "/tmp/base", isDirectory: true)),
            defaults: defaults,
            migrator: FakeBaseDirectoryMigrator(outcome: .success(nil)),
            selectDirectory: { _ in nil }
        )

        XCTAssertEqual(viewModel.audioRetentionDays, 7)
        XCTAssertEqual(AudioRecordingRetentionDaysPreference.resolve(from: defaults), 7)

        for value in [30, 14, 7, 1, 0] {
            viewModel.setAudioRetentionDays(value)
            XCTAssertEqual(viewModel.audioRetentionDays, value)
            XCTAssertEqual(AudioRecordingRetentionDaysPreference.resolve(from: defaults), value)
        }
    }

    func testAudioRetentionSanitizesUnknownValues() {
        let defaults = isolatedDefaults()
        let viewModel = AdvancedTabViewModel(
            baseDirectoryResult: .success(URL(fileURLWithPath: "/tmp/base", isDirectory: true)),
            defaults: defaults,
            migrator: FakeBaseDirectoryMigrator(outcome: .success(nil)),
            selectDirectory: { _ in nil }
        )

        viewModel.setAudioRetentionDays(9)
        XCTAssertEqual(viewModel.audioRetentionDays, 7)
        XCTAssertEqual(AudioRecordingRetentionDaysPreference.resolve(from: defaults), 7)

        viewModel.setAudioRetentionDays(18)
        XCTAssertEqual(viewModel.audioRetentionDays, 14)
        XCTAssertEqual(AudioRecordingRetentionDaysPreference.resolve(from: defaults), 14)

        viewModel.setAudioRetentionDays(45)
        XCTAssertEqual(viewModel.audioRetentionDays, 30)
        XCTAssertEqual(AudioRecordingRetentionDaysPreference.resolve(from: defaults), 30)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "AdvancedTabViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

private final class FakeBaseDirectoryMigrator: BaseDirectoryMigrating, @unchecked Sendable {
    private let outcome: Result<URL?, StubMigrationError>
    private(set) var recordedDestinations: [URL] = []

    init(outcome: Result<URL?, StubMigrationError>) {
        self.outcome = outcome
    }

    func scheduleMove(to newBase: URL) throws -> URL? {
        recordedDestinations.append(newBase.standardizedFileURL)
        return try outcome.get()
    }
}

private struct StubMigrationError: LocalizedError, Sendable, Equatable {
    let message: String

    var errorDescription: String? {
        message
    }
}

private struct AdvancedTabTestStorageLocator: StorageLocator {
    let baseDirectory: URL

    func url(for directory: ManagedDirectory) -> URL {
        baseDirectory
            .appendingPathComponent(directory.pathComponent, isDirectory: true)
            .standardizedFileURL
    }

    func ensureDirectoriesExist() throws {}
}

private extension AdvancedTabViewModelTests {
    func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AdvancedTabViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
