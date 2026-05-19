import XCTest
import PersonalScribeCore
import PersonalScribeSession
@testable import PersonalScribeAppKit

@MainActor
final class ModeDetailViewTests: XCTestCase {
    func testPinnedHiddenBridgeDescriptorKeepsLabelWhilePickerOptionsStayVisibleOnly() {
        let defaults = isolatedDefaults()
        let activePreference = Preference<[ModelKind: String]>(
            key: ActiveModelService.preferenceKey,
            default: [:],
            defaults: defaults
        )
        let filterPreference = WhisperAdapterFilter.preference(defaults: defaults)
        let whisperKit = makeDescriptor(id: "whisper-kit", engine: .whisperKit)
        let whisperBridge = makeDescriptor(id: "whisper-bridge", engine: .whisperCpp)
        filterPreference.persist(.native)
        let service = ActiveModelService(
            activeIDsPreference: activePreference,
            whisperAdapterFilterPreference: filterPreference,
            registeredModels: [whisperKit, whisperBridge],
            isDownloaded: { _ in true },
            download: { _, _ in }
        )

        XCTAssertEqual(
            ModeDetailView.pickableDescriptorsForKind(.asr, modelService: service).map(\.id),
            [whisperKit.id]
        )
        XCTAssertEqual(
            ModeDetailView.resolvedVoiceModelMenuButtonLabel(
                pinID: whisperBridge.id,
                modelService: service
            ),
            whisperBridge.displayName
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "ModeDetailViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func makeDescriptor(
        id: String,
        engine: TranscriptionEngine
    ) -> ModelDescriptor {
        ModelDescriptor(
            id: id,
            displayName: "Descriptor \(id)",
            shortDescription: "Synthetic descriptor for mode detail tests.",
            architecture: "Test",
            repository: "test/\(id)",
            revision: "test",
            requiredRelativePaths: [],
            approximateSizeBytes: 0,
            engine: engine,
            tokenizerSource: nil
        )
    }
}
