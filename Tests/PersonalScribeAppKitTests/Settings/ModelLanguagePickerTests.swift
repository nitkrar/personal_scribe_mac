import XCTest
@testable import PersonalScribeAppKit
@testable import PersonalScribeCore

@MainActor
final class ModelLanguagePickerTests: XCTestCase {
    func testOptionsPlaceAutoDetectFirst() {
        let options = ModelLanguagePicker.options(
            for: makeDescriptor(supportedLanguages: ["ja", "en"]),
            locale: Locale(identifier: "en"),
            languageNameResolver: { _, languageCode in
                switch languageCode {
                case "en": return "English"
                case "ja": return "Japanese"
                default: return nil
                }
            }
        )

        XCTAssertEqual(options.first, .init(code: nil, label: "Auto-detect"))
        XCTAssertEqual(
            options.dropFirst().map(\.label),
            ["English (en)", "Japanese (ja)"]
        )
    }

    func testVisibilityIsFalseWhenDescriptorHasNoSupportedLanguages() {
        XCTAssertFalse(
            ModelLanguagePicker.isVisible(
                descriptor: makeDescriptor(supportedLanguages: nil),
                phase: .ready
            )
        )
    }

    func testVisibilityIsFalseWhenPhaseIsNotDownloaded() {
        XCTAssertFalse(
            ModelLanguagePicker.isVisible(
                descriptor: makeDescriptor(supportedLanguages: ["en", "ja"]),
                phase: .notDownloaded
            )
        )
    }

    func testUpdateSelectionWithAutoDetectClearsStoredHint() async {
        let suiteName = "ModelLanguagePickerTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let descriptor = makeDescriptor(supportedLanguages: ["en", "ja"])
        let preference = ModelLanguagePreference(
            suiteName: suiteName,
            registeredModels: [descriptor]
        )
        await preference.setHint("ja", for: descriptor.id)

        let viewModel = ModelLanguagePickerViewModel(
            descriptor: descriptor,
            preference: preference,
            locale: Locale(identifier: "en")
        )
        await viewModel.updateSelection(nil)
        let hint = await preference.hint(for: descriptor.id)

        XCTAssertNil(hint)
        XCTAssertEqual(storedHints(in: defaults), [:])
    }

    func testUpdateSelectionPersistsChosenLanguageCode() async {
        let suiteName = "ModelLanguagePickerTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let descriptor = makeDescriptor(supportedLanguages: ["en", "ja"])
        let preference = ModelLanguagePreference(
            suiteName: suiteName,
            registeredModels: [descriptor]
        )
        let viewModel = ModelLanguagePickerViewModel(
            descriptor: descriptor,
            preference: preference,
            locale: Locale(identifier: "en")
        )

        await viewModel.updateSelection("ja")
        let hint = await preference.hint(for: descriptor.id)

        XCTAssertEqual(hint, "ja")
        XCTAssertEqual(storedHints(in: defaults), [descriptor.id: "ja"])
    }

    func testLocalizedDisplayNameFallsBackToBareCodeWhenLookupFails() {
        XCTAssertEqual(
            ModelLanguagePicker.localizedDisplayName(
                for: "yue",
                locale: Locale(identifier: "en"),
                languageNameResolver: { _, _ in nil }
            ),
            "yue"
        )
    }

    private func makeDescriptor(
        supportedLanguages: [String]?
    ) -> ModelDescriptor {
        ModelDescriptor(
            id: "whisperkit-tiny",
            displayName: "Whisper Tiny (WhisperKit)",
            shortDescription: "fixture",
            architecture: "Whisper",
            repository: "example/whisperkit-tiny",
            revision: "abc123",
            requiredRelativePaths: ["model.bin"],
            approximateSizeBytes: 1,
            engine: .whisperKit,
            supportedLanguages: supportedLanguages
        )
    }

    private func storedHints(in defaults: UserDefaults) -> [String: String] {
        Preference<[String: String]>(
            key: ModelLanguagePreference.userDefaultsKey,
            default: [:],
            defaults: defaults
        ).resolve()
    }
}
