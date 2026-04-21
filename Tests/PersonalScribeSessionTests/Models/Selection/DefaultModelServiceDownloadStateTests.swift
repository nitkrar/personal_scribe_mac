import Combine
import Foundation
import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeSession

/// TDD coverage for Stage A step 3.1 — the service-owned `downloadStates`
/// stream that Settings surfaces (AIModelsTab) subscribe to.
///
/// These tests drive `DefaultModelService.setActive` with a scripted
/// download handler and assert the published `[String: ModelDownloadState]`
/// dictionary transitions through the expected phases in order. They fail
/// on the pre-3.1 service because `setActive`'s `{ _ in }` no-op handler
/// dropped every progress tick.
@MainActor
final class DefaultModelServiceDownloadStateTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "PersonalScribeTests.DefaultModelServiceDownloadState.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    func testInitialDownloadStatesReflectOnDiskPresence() {
        let downloadedModel = BuiltInModelCatalog.parakeetTDT06Bv2
        let service = makeService(
            isDownloaded: { $0.id == downloadedModel.id },
            download: { _, _ in }
        )

        XCTAssertEqual(
            service.downloadStates[downloadedModel.id]?.phase,
            .ready
        )
        XCTAssertEqual(
            service.downloadStates[BuiltInModelCatalog.parakeetTDTCTC110M.id]?.phase,
            .notDownloaded
        )
        XCTAssertEqual(
            service.downloadStates[BuiltInModelCatalog.parakeetTDT06Bv3.id]?.phase,
            .notDownloaded
        )
    }

    func testSetActiveEmitsDownloadingLoadingAndReadyPhasesInOrder() async throws {
        let target = BuiltInModelCatalog.parakeetTDTCTC110M
        let service = makeService(
            isDownloaded: { _ in false },
            download: { _, progress in
                progress(
                    .init(
                        phase: .downloading,
                        fractionCompleted: 0.25,
                        receivedBytes: 25,
                        expectedBytes: 100
                    )
                )
                progress(
                    .init(
                        phase: .downloading,
                        fractionCompleted: 0.75,
                        receivedBytes: 75,
                        expectedBytes: 100
                    )
                )
                progress(
                    .init(
                        phase: .loading,
                        fractionCompleted: 1,
                        receivedBytes: 100,
                        expectedBytes: 100
                    )
                )
            }
        )

        let collector = SnapshotCollector()
        let cancellable = service.$downloadStates
            .sink { snapshot in
                if let state = snapshot[target.id] {
                    collector.append(state)
                }
            }

        try await service.setActive(
            ActiveModelDescriptor(voiceModel: target, aiModelID: nil)
        )

        cancellable.cancel()

        let phases = collector.phases()

        // Drop duplicates (the initial `.notDownloaded` + any `.downloading`
        // ticks may coalesce). Assert on the ordered unique sequence so the
        // test is robust against Combine delivery quirks.
        let uniquePhases = phases.reduce(into: [ModelDownloadState.Phase]()) { acc, phase in
            if acc.last != phase { acc.append(phase) }
        }

        XCTAssertEqual(
            uniquePhases,
            [.notDownloaded, .downloading, .loading, .ready]
        )
    }

    func testSetActivePublishesFailedStateWhenDownloadThrows() async {
        let target = BuiltInModelCatalog.parakeetTDTCTC110M
        let service = makeService(
            isDownloaded: { _ in false },
            download: { _, _ in
                throw DownloadStateTestError.handlerFailure
            }
        )

        do {
            try await service.setActive(
                ActiveModelDescriptor(voiceModel: target, aiModelID: nil)
            )
            XCTFail("Expected setActive to rethrow handler failure")
        } catch {
            // expected
        }

        guard case .failed(let message) = service.downloadStates[target.id]?.phase else {
            XCTFail("Expected \\.failed for \(target.id); got \(String(describing: service.downloadStates[target.id]?.phase))")
            return
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testSetActiveEmitsReadyImmediatelyWhenModelAlreadyDownloaded() async throws {
        let target = BuiltInModelCatalog.parakeetTDTCTC110M
        let service = makeService(
            isDownloaded: { _ in true },
            download: { _, _ in
                XCTFail("Download handler must not be invoked for an already-downloaded model")
            }
        )

        try await service.setActive(
            ActiveModelDescriptor(voiceModel: target, aiModelID: nil)
        )

        XCTAssertEqual(service.downloadStates[target.id]?.phase, .ready)
    }

    // MARK: - Stage B — disk-space precheck

    /// Precheck: when the volume containing the models directory has
    /// less free space than the model's `approximateSizeBytes + 200 MB`
    /// buffer, `setActive` must refuse to start the download, publish a
    /// `.failed(...)` state with a "disk space" message, and throw
    /// `ModelSelectionError.insufficientDiskSpace(...)`.
    func testSetActiveRejectsDownloadWhenDiskSpaceIsInsufficient() async {
        let target = BuiltInModelCatalog.parakeetTDT06Bv2
        // parakeetTDT06Bv2.approximateSizeBytes == 450_000_000 (see
        // BuiltInModelCatalog). Report 100 MB free — well below the
        // `450 MB + 200 MB` requirement.
        let availableBytes: Int64 = 100 * 1024 * 1024
        let downloadInvocations = LockedCounter()
        let service = makeService(
            isDownloaded: { _ in false },
            download: { _, _ in
                downloadInvocations.increment()
                XCTFail("Download handler must not be invoked when disk space is insufficient")
            },
            modelsDirectoryProvider: { URL(fileURLWithPath: "/tmp/personal-scribe-precheck-test-\(UUID().uuidString)") },
            diskSpaceProvider: { _ in availableBytes }
        )

        do {
            try await service.setActive(
                ActiveModelDescriptor(voiceModel: target, aiModelID: nil)
            )
            XCTFail("Expected setActive to throw ModelSelectionError.insufficientDiskSpace")
        } catch let error as ModelSelectionError {
            guard case .insufficientDiskSpace(let required, let available) = error else {
                XCTFail("Expected .insufficientDiskSpace, got \(error)")
                return
            }
            // Required must include the 200 MB buffer on top of the
            // declared model size.
            XCTAssertGreaterThan(required, target.approximateSizeBytes)
            XCTAssertEqual(available, availableBytes)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(downloadInvocations.value, 0)

        guard case .failed(let message) = service.downloadStates[target.id]?.phase else {
            XCTFail("Expected .failed phase after precheck; got \(String(describing: service.downloadStates[target.id]?.phase))")
            return
        }
        // Message must mention disk space so the AIModelsTab row's
        // "Failed: <message>" chip is self-explanatory.
        XCTAssertTrue(
            message.lowercased().contains("disk space"),
            "Expected failure message to mention 'disk space'; got \(message)"
        )
    }

    /// Regression guard: when the provider reports ample free space the
    /// existing download path runs normally — precheck must not become
    /// a blocker on healthy machines.
    func testSetActiveProceedsWhenDiskSpaceProviderReportsAmpleSpace() async throws {
        let target = BuiltInModelCatalog.parakeetTDTCTC110M
        let downloadInvocations = LockedCounter()
        // 50 GB free — far more than `approximateSizeBytes + buffer`.
        let availableBytes: Int64 = 50 * 1024 * 1024 * 1024
        let service = makeService(
            isDownloaded: { _ in false },
            download: { _, progress in
                downloadInvocations.increment()
                progress(
                    .init(
                        phase: .finished,
                        fractionCompleted: 1,
                        receivedBytes: 1,
                        expectedBytes: 1
                    )
                )
            },
            modelsDirectoryProvider: { URL(fileURLWithPath: "/tmp/personal-scribe-precheck-test-\(UUID().uuidString)") },
            diskSpaceProvider: { _ in availableBytes }
        )

        try await service.setActive(
            ActiveModelDescriptor(voiceModel: target, aiModelID: nil)
        )

        XCTAssertEqual(downloadInvocations.value, 1)
        XCTAssertEqual(service.downloadStates[target.id]?.phase, .ready)
    }

    // MARK: - Helpers

    private func makeService(
        isDownloaded: @escaping @Sendable (ModelDescriptor) -> Bool,
        download: @escaping @Sendable (
            ModelDescriptor,
            @escaping @Sendable (ModelDownloadProgress) -> Void
        ) async throws -> Void,
        modelsDirectoryProvider: (@Sendable () -> URL?)? = nil,
        diskSpaceProvider: (@Sendable (URL) -> Int64?)? = nil
    ) -> DefaultModelService {
        let defaults = isolatedDefaults()
        let preference = Preference<ActiveModelDescriptor>(
            key: DefaultModelService.preferenceKey,
            default: BuiltInModelCatalog.defaultActiveDescriptor,
            defaults: defaults
        )
        if let modelsDirectoryProvider, let diskSpaceProvider {
            return DefaultModelService(
                selectionPreference: preference,
                isDownloaded: isDownloaded,
                download: download,
                modelsDirectoryProvider: modelsDirectoryProvider,
                diskSpaceProvider: diskSpaceProvider
            )
        }
        return DefaultModelService(
            selectionPreference: preference,
            isDownloaded: isDownloaded,
            download: download
        )
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Int = 0

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        storage += 1
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@MainActor
private final class SnapshotCollector {
    private var storage: [ModelDownloadState] = []

    func append(_ state: ModelDownloadState) {
        storage.append(state)
    }

    func phases() -> [ModelDownloadState.Phase] {
        storage.map(\.phase)
    }
}

private enum DownloadStateTestError: Error, Equatable {
    case handlerFailure
}
