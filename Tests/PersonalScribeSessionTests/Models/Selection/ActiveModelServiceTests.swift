import Combine
import Foundation
import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeSession

@MainActor
final class ActiveModelServiceTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "PersonalScribeTests.ActiveModelService.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    /// Stored ids referencing models no longer in the registry must
    /// be pruned at init — fresh launch sees only canonical entries.
    func testInvalidStoredSelectionPrunesOnInit() {
        let defaults = isolatedDefaults()
        let preference = Preference<[ModelKind: String]>(
            key: ActiveModelService.preferenceKey,
            default: [:],
            defaults: defaults
        )
        preference.persist([.asr: "retired-model"])

        let service = ActiveModelService(
            activeIDsPreference: preference,
            isDownloaded: { _ in true },
            download: { _, _ in },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )

        XCTAssertNil(service.activeDescriptor(for: ModelKind.asr))
        XCTAssertEqual(preference.resolve(), [:])
    }

    /// `setActive` is a pure persist+assign — it never calls the
    /// download handler. The UI gates `setActive` behind "model is
    /// downloaded" (Modes tab hides non-downloaded modes; AI Models
    /// tab only shows Activate on `.ready` rows).
    ///
    /// Invariants pinned:
    /// 1. `isDownloaded: { _ in false }` — flipping the stub makes the
    ///    "no download handler" assertion load-bearing instead of
    ///    vacuous.
    /// 2. `$activeModelIDs` must publish the change — observers (e.g.
    ///    `ModesTabViewModel`'s Combine sink) subscribe to the
    ///    publisher, not the current value.
    func testSetActivePersistsAndAssignsWithoutCallingDownloadHandler() async throws {
        let defaults = isolatedDefaults()
        let preference = Preference<[ModelKind: String]>(
            key: ActiveModelService.preferenceKey,
            default: [:],
            defaults: defaults
        )
        let target = BuiltInModelCatalog.parakeetTDTCTC110M
        let recorder = DownloadRecorder()
        let service = ActiveModelService(
            activeIDsPreference: preference,
            isDownloaded: { _ in false },
            download: { descriptor, _ in
                await recorder.record(descriptor)
            },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )

        // Subscribe to the post-setActive publish only — drop the
        // initial value emitted on subscribe so we don't race with the
        // setActive call below. The test was previously waiting for
        // `seen == 2` (initial + post-setActive) which deadlocked under
        // Swift 6 strict concurrency when the @MainActor service's
        // publisher couldn't deliver synchronously to a non-MainActor
        // observer Task.
        let publications = Task { @MainActor () -> [ModelKind: String]? in
            for await value in service.$activeModelIDs.dropFirst().values {
                return value
            }
            return nil
        }
        await Task.yield()

        service.setActive(target)

        let published = await publications.value
        let recordedDescriptors = await recorder.recordedDescriptors()

        XCTAssertTrue(recordedDescriptors.isEmpty, "setActive must not invoke the download handler")
        XCTAssertEqual(published?[.asr], target.id, "setActive must publish through $activeModelIDs")
        XCTAssertEqual(service.activeDescriptor(for: ModelKind.asr)?.id, target.id)
        XCTAssertEqual(preference.resolve()[.asr], target.id)
    }

    func testIsDownloadedReturnsTrueForRegisteredDescriptorAndFalseForUnknownDescriptor() {
        let target = BuiltInModelCatalog.parakeetTDTCTC110M
        let shadowDescriptor = ModelDescriptor(
            id: target.id,
            displayName: "Shadow",
            shortDescription: "Test fixture.",
            architecture: "Test",
            repository: "FluidInference/shadow",
            revision: "shadow",
            requiredRelativePaths: [],
            approximateSizeBytes: 0,
            engine: .parakeetTDT
        )
        let missingDescriptor = ModelDescriptor(
            id: "missing-model",
            displayName: "Missing",
            shortDescription: "Test fixture.",
            architecture: "Test",
            repository: "FluidInference/missing",
            revision: "missing",
            requiredRelativePaths: [],
            approximateSizeBytes: 0,
            engine: .parakeetTDT
        )
        let service = ActiveModelService(
            activeIDsPreference: Preference<[ModelKind: String]>(
                key: ActiveModelService.preferenceKey,
                default: [:],
                defaults: isolatedDefaults()
            ),
            isDownloaded: { descriptor in
                descriptor == target
            },
            download: { _, _ in },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )

        XCTAssertTrue(service.isDownloaded(shadowDescriptor))
        XCTAssertFalse(service.isDownloaded(missingDescriptor))
    }

    func testDownloadPassesCanonicalDescriptorAndPublishesReady() async throws {
        let target = BuiltInModelCatalog.parakeetTDTCTC110M
        let shadowDescriptor = ModelDescriptor(
            id: target.id,
            displayName: "Shadow",
            shortDescription: "Test fixture.",
            architecture: "Test",
            repository: "FluidInference/shadow",
            revision: "shadow",
            requiredRelativePaths: [],
            approximateSizeBytes: 0,
            engine: .parakeetTDT
        )
        let descriptorRecorder = LockedDescriptorRecorder()
        let service = ActiveModelService(
            activeIDsPreference: Preference<[ModelKind: String]>(
                key: ActiveModelService.preferenceKey,
                default: [:],
                defaults: isolatedDefaults()
            ),
            isDownloaded: { _ in false },
            download: { descriptor, _ in
                descriptorRecorder.record(descriptor)
            },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )

        try await service.download(shadowDescriptor)

        XCTAssertEqual(descriptorRecorder.descriptors, [target])
        XCTAssertEqual(service.downloadStates[target.id]?.phase, .ready)
        XCTAssertEqual(service.downloadStates[target.id]?.fractionCompleted, 1)
    }

    func testDownloadPropagatesHandlerError() async {
        let service = ActiveModelService(
            activeIDsPreference: Preference<[ModelKind: String]>(
                key: ActiveModelService.preferenceKey,
                default: [:],
                defaults: isolatedDefaults()
            ),
            isDownloaded: { _ in false },
            download: { _, _ in
                throw DownloadTestError.handlerFailure
            },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )

        do {
            try await service.download(BuiltInModelCatalog.parakeetTDTCTC110M)
            XCTFail("Expected download to throw when the injected handler fails")
        } catch let error as DownloadTestError {
            XCTAssertEqual(error, .handlerFailure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - #016 — RAM-aware first-launch default

    /// Fresh UserDefaults (no persisted selection) on an 8 GB Mac:
    /// the convenience init's RAM probe picks the lightweight
    /// CTC-110M descriptor as the Preference's `default:`. The
    /// resolver then returns that descriptor since nothing is
    /// persisted.
    func testEightGiBMachineOnFreshInstallUsesLightweightDefault() {
        let defaults = isolatedDefaults()
        let service = ActiveModelService(
            defaults: defaults,
            physicalMemoryBytes: 8 * 1024 * 1024 * 1024,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )

        XCTAssertEqual(
            service.activeDescriptor(for: ModelKind.asr)?.id,
            BuiltInModelCatalog.parakeetTDTCTC110M.id
        )
    }

    /// Fresh UserDefaults on a 16 GB Mac: baseline default
    /// (parakeet-tdt-0.6b-v2). Guards the "don't regress high-RAM
    /// machines" invariant.
    func testSixteenGiBMachineOnFreshInstallUsesBaselineDefault() {
        let defaults = isolatedDefaults()
        let service = ActiveModelService(
            defaults: defaults,
            physicalMemoryBytes: 16 * 1024 * 1024 * 1024,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )

        XCTAssertEqual(
            service.activeDescriptor(for: ModelKind.asr)?.id,
            BuiltInModelCatalog.parakeetTDT06Bv2.id
        )
    }

    /// User chose v2 explicitly on a prior launch — the persisted
    /// selection wins over the RAM probe even on an 8 GB machine.
    /// Guards "user choice always wins after first launch."
    func testPersistedSelectionWinsOverRAMProbe() {
        let defaults = isolatedDefaults()
        let preference = Preference<[ModelKind: String]>(
            key: ActiveModelService.preferenceKey,
            default: [:],
            defaults: defaults
        )
        preference.persist([.asr: BuiltInModelCatalog.parakeetTDT06Bv2.id])

        // 8 GB — RAM probe would otherwise route to CTC-110M.
        let service = ActiveModelService(
            defaults: defaults,
            physicalMemoryBytes: 8 * 1024 * 1024 * 1024,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )

        XCTAssertEqual(
            service.activeDescriptor(for: ModelKind.asr)?.id,
            BuiltInModelCatalog.parakeetTDT06Bv2.id
        )
    }

    // MARK: - #024 — per-row delete

    func testRemoveDownloadedInvokesHandlerAndPublishesNotDownloaded() throws {
        let target = BuiltInModelCatalog.parakeetTDTCTC110M
        let spy = LockedDescriptorRecorder()
        // Shadow descriptor with the same id as `target` — proves the
        // service canonicalizes to the registered descriptor before
        // calling the handler.
        let shadowDescriptor = ModelDescriptor(
            id: target.id,
            displayName: "Shadow",
            shortDescription: "Test fixture.",
            architecture: "Test",
            repository: "FluidInference/shadow",
            revision: "shadow",
            requiredRelativePaths: [],
            approximateSizeBytes: 0,
            engine: .parakeetTDT
        )
        let service = ActiveModelService(
            activeIDsPreference: Preference<[ModelKind: String]>(
                key: ActiveModelService.preferenceKey,
                default: [:],
                defaults: isolatedDefaults()
            ),
            isDownloaded: { descriptor in descriptor.id == target.id },
            download: { _, _ in },
            removeDownloaded: { descriptor in
                spy.record(descriptor)
            },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )

        // Sanity: constructor seeded `.ready` for `target` via the
        // isDownloaded handler.
        XCTAssertEqual(service.downloadStates[target.id]?.phase, .ready)

        try service.removeDownloaded(shadowDescriptor)

        XCTAssertEqual(spy.descriptors, [target])
        XCTAssertEqual(service.downloadStates[target.id]?.phase, .notDownloaded)
        XCTAssertEqual(service.downloadStates[target.id]?.fractionCompleted, 0)
    }

    /// `setActive` must fire `onSetActive` after persist+assign so the
    /// composition root can prewarm the new model's transcriber.
    /// Without this, FluidAudio's auxiliary downloads (e.g. the 110m
    /// hybrid's CTC head fetch) land on the next prepare — usually
    /// the next app launch — instead of at the user-initiated
    /// activate moment.
    func testSetActiveFiresOnSetActiveHandler() async throws {
        let target = BuiltInModelCatalog.parakeetTDTCTC110M
        let service = ActiveModelService(
            activeIDsPreference: Preference<[ModelKind: String]>(
                key: ActiveModelService.preferenceKey,
                default: [:],
                defaults: isolatedDefaults()
            ),
            isDownloaded: { _ in true },
            download: { _, _ in },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )
        let counter = LockedSetActiveCounter()
        let firedExpectation = expectation(description: "onSetActive fires")
        service.onSetActive = {
            counter.increment()
            firedExpectation.fulfill()
        }

        service.setActive(target)

        await fulfillment(of: [firedExpectation], timeout: 1)
        XCTAssertEqual(counter.value, 1)
    }

    // MARK: - #024.10 — per-kind active state

    /// Pin the per-kind invariant: setting two `.asr` descriptors back-
    /// to-back evicts the first; setting a `.streamingASR` descriptor
    /// leaves `.asr` untouched and adds a separate slot.
    func testSetActiveStoresPerKindAndEvictsSameKind() {
        let v2 = BuiltInModelCatalog.parakeetTDT06Bv2
        let v3 = BuiltInModelCatalog.parakeetTDT06Bv3
        let streamingDescriptor = ModelDescriptor(
            id: "test-streaming-descriptor",
            displayName: "Streaming Test",
            shortDescription: "Synthetic streaming descriptor for the per-kind eviction test.",
            architecture: "Test",
            repository: "FluidInference/test-streaming",
            revision: "test",
            requiredRelativePaths: [],
            approximateSizeBytes: 0,
            engine: .parakeetEOU
        )
        let service = ActiveModelService(
            activeIDsPreference: Preference<[ModelKind: String]>(
                key: ActiveModelService.preferenceKey,
                default: [:],
                defaults: isolatedDefaults()
            ),
            registeredModels: BuiltInModelCatalog.registeredModels + [streamingDescriptor],
            isDownloaded: { _ in true },
            download: { _, _ in },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )

        service.setActive(v2)
        XCTAssertEqual(service.activeDescriptor(for: ModelKind.asr)?.id, v2.id)

        service.setActive(v3)
        XCTAssertEqual(
            service.activeDescriptor(for: ModelKind.asr)?.id,
            v3.id,
            "Setting another .asr descriptor must evict the prior .asr entry"
        )

        service.setActive(streamingDescriptor)
        XCTAssertEqual(
            service.activeDescriptor(for: ModelKind.asr)?.id,
            v3.id,
            "Setting a .streamingASR descriptor must NOT touch the .asr slot"
        )
        XCTAssertEqual(
            service.activeDescriptor(for: ModelKind.streamingASR)?.id,
            streamingDescriptor.id
        )
    }

    /// Phase 3 of the download/load split. When the user activates a
    /// new descriptor for a kind, the previously-active descriptor's
    /// adapter must be evicted from the provider's cache so its
    /// loaded CoreML weights are released. Without this, switching
    /// between models leaks RAM (the prior model's manager stays
    /// resident for the rest of the app session).
    func testSetActiveEvictsPreviouslyActiveDescriptorOfSameKind() {
        let v2 = BuiltInModelCatalog.parakeetTDT06Bv2
        let v3 = BuiltInModelCatalog.parakeetTDT06Bv3
        let evictRecorder = LockedDescriptorRecorder()
        let service = ActiveModelService(
            activeIDsPreference: Preference<[ModelKind: String]>(
                key: ActiveModelService.preferenceKey,
                default: [:],
                defaults: isolatedDefaults()
            ),
            isDownloaded: { _ in true },
            download: { _, _ in },
            evict: { descriptor in evictRecorder.record(descriptor) },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )

        // First activation has no previous — must NOT call evict.
        service.setActive(v2)
        XCTAssertTrue(
            evictRecorder.descriptors.isEmpty,
            "First setActive (no prior) must not evict spuriously"
        )

        // Switch — must evict v2.
        service.setActive(v3)
        XCTAssertEqual(evictRecorder.descriptors, [v2])

        // Re-set same descriptor — must NOT evict (no actual switch).
        service.setActive(v3)
        XCTAssertEqual(
            evictRecorder.descriptors,
            [v2],
            "Re-setActive with the same descriptor must not call evict"
        )
    }

    /// Adjacent invariant: switching kinds (e.g. activating a
    /// streamingASR descriptor) must not evict the existing `.asr`
    /// descriptor — those are separate slots in the per-kind map.
    func testSetActiveOfDifferentKindDoesNotEvictOtherKindActive() {
        let v3 = BuiltInModelCatalog.parakeetTDT06Bv3
        let streamingDescriptor = ModelDescriptor(
            id: "test-streaming-evict",
            displayName: "Streaming Evict Test",
            shortDescription: "Synthetic descriptor pinning the cross-kind no-evict invariant.",
            architecture: "Test",
            repository: "FluidInference/test-streaming-evict",
            revision: "test",
            requiredRelativePaths: [],
            approximateSizeBytes: 0,
            engine: .parakeetEOU
        )
        let evictRecorder = LockedDescriptorRecorder()
        let service = ActiveModelService(
            activeIDsPreference: Preference<[ModelKind: String]>(
                key: ActiveModelService.preferenceKey,
                default: [:],
                defaults: isolatedDefaults()
            ),
            registeredModels: BuiltInModelCatalog.registeredModels + [streamingDescriptor],
            isDownloaded: { _ in true },
            download: { _, _ in },
            evict: { descriptor in evictRecorder.record(descriptor) },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )

        service.setActive(v3)
        service.setActive(streamingDescriptor)

        XCTAssertTrue(
            evictRecorder.descriptors.isEmpty,
            "Activating a different-kind descriptor must not evict the existing kind's active descriptor"
        )
    }
}

private actor DownloadRecorder {
    private var descriptors: [ModelDescriptor] = []

    func record(_ descriptor: ModelDescriptor) {
        descriptors.append(descriptor)
    }

    func recordedDescriptors() -> [ModelDescriptor] {
        descriptors
    }
}

private final class LockedDescriptorRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ModelDescriptor] = []

    func record(_ descriptor: ModelDescriptor) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(descriptor)
    }

    var descriptors: [ModelDescriptor] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class LockedSetActiveCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

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

private enum DownloadTestError: Error, Equatable {
    case handlerFailure
}
