import Combine
import Foundation
import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeSession

@MainActor
final class DefaultModelServiceTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "PersonalScribeTests.DefaultModelService.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    func testInvalidStoredSelectionFallsBackToDefaultDescriptor() {
        let defaults = isolatedDefaults()
        let preference = Preference<ActiveModelDescriptor>(
            key: DefaultModelService.preferenceKey,
            default: BuiltInModelCatalog.defaultActiveDescriptor,
            defaults: defaults
        )
        let retiredModel = ModelDescriptor(
            id: "retired-model",
            displayName: "Retired",
            shortDescription: "Test fixture.",
            architecture: "Test",
            repository: "FluidInference/retired-model-coreml",
            revision: "deadbeef",
            requiredRelativePaths: ["parakeet_vocab.json"],
            approximateSizeBytes: 1,
            engine: .parakeetTDT
        )
        preference.persist(
            ActiveModelDescriptor(
                voiceModel: retiredModel,
                aiModelID: "assistant"
            )
        )

        let service = DefaultModelService(
            selectionPreference: preference,
            isDownloaded: { _ in true },
            download: { _, _ in }
        )

        XCTAssertEqual(service.activeDescriptor, BuiltInModelCatalog.defaultActiveDescriptor)
        XCTAssertEqual(preference.resolve(), BuiltInModelCatalog.defaultActiveDescriptor)
    }

    /// `setActive` is a pure persist+assign after #024 follow-up — it
    /// never calls the download handler. The UI gates `setActive`
    /// behind "model is downloaded" (Modes tab hides non-downloaded
    /// modes; AI Models tab only shows Activate on `.ready` rows).
    func testSetActiveVoiceModelPersistsAndAssignsWithoutCallingDownloadHandler() async throws {
        let defaults = isolatedDefaults()
        let preference = Preference<ActiveModelDescriptor>(
            key: DefaultModelService.preferenceKey,
            default: BuiltInModelCatalog.defaultActiveDescriptor,
            defaults: defaults
        )
        let target = BuiltInModelCatalog.parakeetTDTCTC110M
        let recorder = DownloadRecorder()
        let service = DefaultModelService(
            selectionPreference: preference,
            isDownloaded: { _ in true },
            download: { descriptor, _ in
                await recorder.record(descriptor)
            }
        )

        try await service.setActiveVoiceModel(target.id)

        let recordedDescriptors = await recorder.recordedDescriptors()
        XCTAssertTrue(recordedDescriptors.isEmpty, "setActive must not invoke the download handler")
        XCTAssertEqual(service.activeDescriptor.voiceModel.id, target.id)
        XCTAssertEqual(preference.resolve().voiceModel.id, target.id)
    }

    func testSetActiveVoiceModelRejectsUnknownIdentifier() async {
        let service = DefaultModelService(
            selectionPreference: Preference<ActiveModelDescriptor>(
                key: DefaultModelService.preferenceKey,
                default: BuiltInModelCatalog.defaultActiveDescriptor,
                defaults: isolatedDefaults()
            ),
            isDownloaded: { _ in true },
            download: { _, _ in }
        )

        do {
            try await service.setActiveVoiceModel("missing-model")
            XCTFail("Expected setActiveVoiceModel to throw for an unknown model identifier")
        } catch let error as ModelSelectionError {
            XCTAssertEqual(error, .unknownVoiceModelID("missing-model"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
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
        let service = DefaultModelService(
            selectionPreference: Preference<ActiveModelDescriptor>(
                key: DefaultModelService.preferenceKey,
                default: BuiltInModelCatalog.defaultActiveDescriptor,
                defaults: isolatedDefaults()
            ),
            isDownloaded: { descriptor in
                descriptor == target
            },
            download: { _, _ in }
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
        let service = DefaultModelService(
            selectionPreference: Preference<ActiveModelDescriptor>(
                key: DefaultModelService.preferenceKey,
                default: BuiltInModelCatalog.defaultActiveDescriptor,
                defaults: isolatedDefaults()
            ),
            isDownloaded: { _ in false },
            download: { descriptor, _ in
                descriptorRecorder.record(descriptor)
            }
        )

        try await service.download(shadowDescriptor)

        XCTAssertEqual(descriptorRecorder.descriptors, [target])
        XCTAssertEqual(service.downloadStates[target.id]?.phase, .ready)
        XCTAssertEqual(service.downloadStates[target.id]?.fractionCompleted, 1)
    }

    func testDownloadPropagatesHandlerError() async {
        let service = DefaultModelService(
            selectionPreference: Preference<ActiveModelDescriptor>(
                key: DefaultModelService.preferenceKey,
                default: BuiltInModelCatalog.defaultActiveDescriptor,
                defaults: isolatedDefaults()
            ),
            isDownloaded: { _ in false },
            download: { _, _ in
                throw DownloadTestError.handlerFailure
            }
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
        let service = DefaultModelService(
            defaults: defaults,
            physicalMemoryBytes: 8 * 1024 * 1024 * 1024
        )

        XCTAssertEqual(
            service.activeDescriptor.voiceModel.id,
            BuiltInModelCatalog.parakeetTDTCTC110M.id
        )
    }

    /// Fresh UserDefaults on a 16 GB Mac: baseline default
    /// (parakeet-tdt-0.6b-v2). Guards the "don't regress high-RAM
    /// machines" invariant.
    func testSixteenGiBMachineOnFreshInstallUsesBaselineDefault() {
        let defaults = isolatedDefaults()
        let service = DefaultModelService(
            defaults: defaults,
            physicalMemoryBytes: 16 * 1024 * 1024 * 1024
        )

        XCTAssertEqual(
            service.activeDescriptor.voiceModel.id,
            BuiltInModelCatalog.parakeetTDT06Bv2.id
        )
    }

    /// User chose v2 explicitly on a prior launch — the persisted
    /// selection wins over the RAM probe even on an 8 GB machine.
    /// Guards "user choice always wins after first launch."
    func testPersistedSelectionWinsOverRAMProbe() {
        let defaults = isolatedDefaults()
        // Persist v2 as the user's selection.
        let preference = Preference<ActiveModelDescriptor>(
            key: DefaultModelService.preferenceKey,
            default: BuiltInModelCatalog.defaultActiveDescriptor,
            defaults: defaults
        )
        preference.persist(
            ActiveModelDescriptor(
                voiceModel: BuiltInModelCatalog.parakeetTDT06Bv2,
                aiModelID: nil
            )
        )

        // 8 GB — RAM probe would otherwise route to CTC-110M.
        let service = DefaultModelService(
            defaults: defaults,
            physicalMemoryBytes: 8 * 1024 * 1024 * 1024
        )

        XCTAssertEqual(
            service.activeDescriptor.voiceModel.id,
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
        let service = DefaultModelService(
            selectionPreference: Preference<ActiveModelDescriptor>(
                key: DefaultModelService.preferenceKey,
                default: BuiltInModelCatalog.defaultActiveDescriptor,
                defaults: isolatedDefaults()
            ),
            isDownloaded: { descriptor in descriptor.id == target.id },
            download: { _, _ in },
            removeDownloaded: { descriptor in
                spy.record(descriptor)
            }
        )

        // Sanity: constructor seeded `.ready` for `target` via the
        // isDownloaded handler.
        XCTAssertEqual(service.downloadStates[target.id]?.phase, .ready)

        try service.removeDownloaded(shadowDescriptor)

        XCTAssertEqual(spy.descriptors, [target])
        XCTAssertEqual(service.downloadStates[target.id]?.phase, .notDownloaded)
        XCTAssertEqual(service.downloadStates[target.id]?.fractionCompleted, 0)
    }

    func testDescriptorForModeFallsBackToDefaultVoiceModelAndPreservesAISelection() {
        let service = DefaultModelService(
            selectionPreference: Preference<ActiveModelDescriptor>(
                key: DefaultModelService.preferenceKey,
                default: BuiltInModelCatalog.defaultActiveDescriptor,
                defaults: isolatedDefaults()
            ),
            isDownloaded: { _ in true },
            download: { _, _ in }
        )

        let mode = ModeDescriptor(
            id: "notes",
            name: "Notes",
            voiceModelID: "missing-model",
            aiModelID: "gpt-5"
        )
        let resolved = service.descriptor(for: mode)

        XCTAssertEqual(
            resolved.voiceModel.id,
            BuiltInModelCatalog.defaultActiveDescriptor.voiceModel.id
        )
        XCTAssertEqual(resolved.aiModelID, "gpt-5")
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

private final class LockedProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ModelDownloadProgress] = []

    func record(_ snapshot: ModelDownloadProgress) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(snapshot)
    }

    var snapshots: [ModelDownloadProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private enum DownloadTestError: Error, Equatable {
    case handlerFailure
}
