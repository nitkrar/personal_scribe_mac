import Combine
import Foundation
import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeSession

/// TDD coverage for Stage A step 3.1 — the service-owned `downloadStates`
/// stream that Settings surfaces (AIModelsTab) subscribe to.
///
/// These tests drive `ActiveModelService.setActive` with a scripted
/// download handler and assert the published `[String: ModelDownloadState]`
/// dictionary transitions through the expected phases in order. They fail
/// on the pre-3.1 service because `setActive`'s `{ _ in }` no-op handler
/// dropped every progress tick.
@MainActor
final class ActiveModelServiceDownloadStateTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "PersonalScribeTests.ActiveModelServiceDownloadState.\(UUID().uuidString)"
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

    func testDownloadEmitsDownloadingLoadingAndReadyPhasesInOrder() async throws {
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

        try await service.download(target)

        cancellable.cancel()

        let phases = collector.phases()
        let uniquePhases = phases.reduce(into: [ModelDownloadState.Phase]()) { acc, phase in
            if acc.last != phase { acc.append(phase) }
        }

        XCTAssertEqual(
            uniquePhases,
            [.notDownloaded, .downloading, .loading, .ready]
        )
    }

    func testDownloadPublishesFailedStateWhenHandlerThrows() async {
        let target = BuiltInModelCatalog.parakeetTDTCTC110M
        let service = makeService(
            isDownloaded: { _ in false },
            download: { _, _ in
                throw DownloadStateTestError.handlerFailure
            }
        )

        do {
            try await service.download(target)
            XCTFail("Expected download to rethrow handler failure")
        } catch {
            // expected
        }

        guard case .failed(let message) = service.downloadStates[target.id]?.phase else {
            XCTFail("Expected \\.failed for \(target.id); got \(String(describing: service.downloadStates[target.id]?.phase))")
            return
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testDownloadEmitsReadyImmediatelyWhenModelAlreadyDownloaded() async throws {
        let target = BuiltInModelCatalog.parakeetTDTCTC110M
        let service = makeService(
            isDownloaded: { _ in true },
            download: { _, _ in
                XCTFail("Download handler must not be invoked for an already-downloaded model")
            }
        )

        try await service.download(target)

        XCTAssertEqual(service.downloadStates[target.id]?.phase, .ready)
    }

    // MARK: - Stage B — disk-space precheck

    /// Precheck: when the volume containing the models directory has
    /// less free space than the model's `approximateSizeBytes + 200 MB`
    /// buffer, `download` must refuse to start, publish a `.failed(...)`
    /// state with a "disk space" message, and throw
    /// `ModelSelectionError.insufficientDiskSpace(...)`.
    func testDownloadRejectsWhenDiskSpaceIsInsufficient() async {
        let target = BuiltInModelCatalog.parakeetTDT06Bv2
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
            try await service.download(target)
            XCTFail("Expected download to throw ModelSelectionError.insufficientDiskSpace")
        } catch let error as ModelSelectionError {
            guard case .insufficientDiskSpace(let required, let available) = error else {
                XCTFail("Expected .insufficientDiskSpace, got \(error)")
                return
            }
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
        XCTAssertTrue(
            message.lowercased().contains("disk space"),
            "Expected failure message to mention 'disk space'; got \(message)"
        )
    }

    /// Regression guard: when the provider reports ample free space the
    /// download path runs normally — precheck must not become a blocker
    /// on healthy machines.
    func testDownloadProceedsWhenDiskSpaceProviderReportsAmpleSpace() async throws {
        let target = BuiltInModelCatalog.parakeetTDTCTC110M
        let downloadInvocations = LockedCounter()
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

        try await service.download(target)

        XCTAssertEqual(downloadInvocations.value, 1)
        XCTAssertEqual(service.downloadStates[target.id]?.phase, .ready)
    }

    // MARK: - #039 — refresh() resyncs terminal states against disk

    /// A model downloaded out-of-band (e.g. by a prior session, or by
    /// the user manually placing files) must flip from `.notDownloaded`
    /// to `.ready` after `refresh()` re-reads disk. This is the core
    /// #039 invariant: AIModelsTab's `.onAppear { service.refresh() }`
    /// must pick up external disk mutations that happened while the tab
    /// was off-screen.
    func testRefreshPromotesNotDownloadedToReadyWhenModelAppearsOnDisk() {
        let disk = DiskStateHolder()
        let service = makeService(
            isDownloaded: { descriptor in disk.isDownloaded(descriptor) },
            download: { _, _ in }
        )
        let target = BuiltInModelCatalog.parakeetTDTCTC110M
        XCTAssertEqual(service.downloadStates[target.id]?.phase, .notDownloaded)

        disk.setDownloaded(true, for: target)
        service.refresh()

        XCTAssertEqual(service.downloadStates[target.id]?.phase, .ready)
        XCTAssertEqual(service.downloadStates[target.id]?.fractionCompleted, 1)
    }

    /// Symmetric to the promote case: a model deleted out-of-band must
    /// flip from `.ready` to `.notDownloaded` after `refresh()`. Guards
    /// against Settings showing "Ready" when the file has been removed
    /// from disk since service init.
    func testRefreshDemotesReadyToNotDownloadedWhenModelDisappearsFromDisk() {
        let disk = DiskStateHolder()
        let target = BuiltInModelCatalog.parakeetTDT06Bv2
        disk.setDownloaded(true, for: target)
        let service = makeService(
            isDownloaded: { descriptor in disk.isDownloaded(descriptor) },
            download: { _, _ in }
        )
        XCTAssertEqual(service.downloadStates[target.id]?.phase, .ready)

        disk.setDownloaded(false, for: target)
        service.refresh()

        XCTAssertEqual(service.downloadStates[target.id]?.phase, .notDownloaded)
        XCTAssertEqual(service.downloadStates[target.id]?.fractionCompleted, 0)
    }

    /// Regression guard: `refresh()` must NOT overwrite a `.downloading`
    /// state with `.notDownloaded`. During an in-flight download the
    /// files aren't on disk yet (staging dir), so `isDownloaded` returns
    /// false — reading that naively would stomp the progress chip.
    func testRefreshPreservesInFlightDownloadingStates() async throws {
        let disk = DiskStateHolder()
        let service = makeService(
            isDownloaded: { descriptor in disk.isDownloaded(descriptor) },
            download: { _, progress in
                progress(
                    .init(
                        phase: .downloading,
                        fractionCompleted: 0.42,
                        receivedBytes: 42,
                        expectedBytes: 100
                    )
                )
                // Park the handler so the test sees the .downloading
                // state before completion.
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        )
        let target = BuiltInModelCatalog.parakeetTDTCTC110M

        let downloadTask = Task {
            try await service.download(target)
        }
        // Wait for the progress tick to be ingested.
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(service.downloadStates[target.id]?.phase, .downloading)

        service.refresh()

        // Mid-flight refresh must not overwrite .downloading.
        XCTAssertEqual(service.downloadStates[target.id]?.phase, .downloading)
        XCTAssertEqual(service.downloadStates[target.id]?.fractionCompleted, 0.42)

        _ = try await downloadTask.value
    }

    /// `refresh()` must NOT clear a `.failed` state. Failure can coexist
    /// with a model that is on disk (rare) or off disk (common) — either
    /// way, the user explicitly hit Retry to clear; refresh should be
    /// passive.
    func testRefreshPreservesFailedState() async {
        let disk = DiskStateHolder()
        let service = makeService(
            isDownloaded: { descriptor in disk.isDownloaded(descriptor) },
            download: { _, _ in
                throw DownloadStateTestError.handlerFailure
            }
        )
        let target = BuiltInModelCatalog.parakeetTDTCTC110M

        do {
            try await service.download(target)
            XCTFail("Expected download to rethrow")
        } catch {
            // expected
        }
        guard case .failed = service.downloadStates[target.id]?.phase else {
            XCTFail("Test precondition: expected .failed")
            return
        }

        service.refresh()

        guard case .failed = service.downloadStates[target.id]?.phase else {
            XCTFail("refresh() must not clear .failed state")
            return
        }
    }

    /// `refresh()` must be idempotent when the on-disk state matches
    /// the published state — i.e. no-op in the common case where the
    /// user switches to AI Models and nothing has changed. Asserts via
    /// a publisher-subscriber that captures every published snapshot.
    func testRefreshIsNoOpWhenStateMatchesDisk() {
        let disk = DiskStateHolder()
        disk.setDownloaded(true, for: BuiltInModelCatalog.parakeetTDT06Bv2)
        let service = makeService(
            isDownloaded: { descriptor in disk.isDownloaded(descriptor) },
            download: { _, _ in }
        )

        let collector = SnapshotCollector()
        let cancellable = service.$downloadStates
            .dropFirst() // skip the initial-sink value
            .sink { snapshot in
                if let state = snapshot[BuiltInModelCatalog.parakeetTDT06Bv2.id] {
                    collector.append(state)
                }
            }

        service.refresh()
        cancellable.cancel()

        // Disk matches published state → refresh() should not republish.
        XCTAssertEqual(collector.phases(), [])
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
    ) -> ActiveModelService {
        let defaults = isolatedDefaults()
        let preference = Preference<[ModelKind: String]>(
            key: ActiveModelService.preferenceKey,
            default: [:],
            defaults: defaults
        )
        if let modelsDirectoryProvider, let diskSpaceProvider {
            return ActiveModelService(
                activeIDsPreference: preference,
                isDownloaded: isDownloaded,
                download: download,
                modelsDirectoryProvider: modelsDirectoryProvider,
                diskSpaceProvider: diskSpaceProvider,
                logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
            )
        }
        return ActiveModelService(
            activeIDsPreference: preference,
            isDownloaded: isDownloaded,
            download: download,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
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

/// Mutable disk-presence stub backing `refresh()` tests. The service
/// captures `isDownloaded` as a closure at init, so tests need a
/// reference holder to flip disk truth at runtime without reinitializing
/// the service.
private final class DiskStateHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var downloaded: Set<String> = []

    func setDownloaded(_ isDownloaded: Bool, for descriptor: ModelDescriptor) {
        lock.lock()
        defer { lock.unlock() }
        if isDownloaded {
            downloaded.insert(descriptor.id)
        } else {
            downloaded.remove(descriptor.id)
        }
    }

    func isDownloaded(_ descriptor: ModelDescriptor) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return downloaded.contains(descriptor.id)
    }
}
