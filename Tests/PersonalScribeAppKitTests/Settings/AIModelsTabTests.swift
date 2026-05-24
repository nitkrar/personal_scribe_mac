import XCTest
import PersonalScribeCore
import PersonalScribeSession
@testable import PersonalScribeAppKit

@MainActor
final class AIModelsTabTests: XCTestCase {
    func testDisplayedRowsRetainHiddenActiveDescriptorAndShowFilterNotice() {
        let defaults = isolatedDefaults()
        let activePreference = Preference<[ModelKind: String]>(
            key: ActiveModelService.preferenceKey,
            default: [:],
            defaults: defaults
        )
        let filterPreference = WhisperAdapterFilter.preference(defaults: defaults)
        let whisperKit = makeDescriptor(id: "whisper-kit", engine: .whisperKit)
        let whisperBridge = makeDescriptor(id: "whisper-bridge", engine: .whisperCpp)
        let parakeet = makeDescriptor(id: "parakeet", engine: .parakeetTDT)
        activePreference.persist([.asr: whisperBridge.id])
        filterPreference.persist(.native)
        let service = ActiveModelService(
            activeIDsPreference: activePreference,
            whisperAdapterFilterPreference: filterPreference,
            registeredModels: [parakeet, whisperKit, whisperBridge],
            isDownloaded: { _ in true },
            download: { _, _ in },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )

        let rows = AIModelsTab.displayedRows(for: .asr, service: service)

        XCTAssertEqual(rows.map(\.descriptor.id), [parakeet.id, whisperKit.id, whisperBridge.id])
        XCTAssertEqual(rows.map(\.visibility), [.standard, .standard, .filteredActive])
        XCTAssertEqual(
            AIModelsTab.filterNotice(for: .asr, service: service),
            "Some Whisper models are hidden by Whisper Adapter in Settings > Advanced."
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "AIModelsTabTests.\(UUID().uuidString)"
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
            shortDescription: "Synthetic descriptor for AI Models tests.",
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
