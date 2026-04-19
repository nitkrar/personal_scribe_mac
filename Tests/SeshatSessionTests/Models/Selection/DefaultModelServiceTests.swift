import Combine
import Foundation
import XCTest
@testable import SeshatCore
@testable import SeshatSession

@MainActor
final class DefaultModelServiceTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "SeshatTests.DefaultModelService.\(UUID().uuidString)"
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

    func testSetActiveVoiceModelAutoDownloadsMissingModelAndPublishesUpdate() async throws {
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
            isDownloaded: { descriptor in
                descriptor.id != target.id
            },
            download: { descriptor, progress in
                await recorder.record(descriptor)
                progress(
                    .init(
                        phase: .downloading,
                        fractionCompleted: 1,
                        receivedBytes: 1,
                        expectedBytes: 1
                    )
                )
            }
        )

        let updates = Task { () -> ActiveModelDescriptor? in
            var seen = 0
            for await value in service.$activeDescriptor.values {
                seen += 1
                if seen == 2 {
                    return value
                }
            }
            return nil
        }
        await Task.yield()

        try await service.setActiveVoiceModel(target.id)

        let published = await updates.value
        let recordedDescriptors = await recorder.recordedDescriptors()

        XCTAssertEqual(published?.voiceModel.id, target.id)
        XCTAssertEqual(recordedDescriptors, [target])
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
