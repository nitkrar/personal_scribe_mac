import XCTest
@testable import PersonalScribeCore

final class ModelLanguagePreferenceTests: XCTestCase {
    func testHintReturnsNilForUnsetAndUnknownDescriptor() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let descriptor = makeDescriptor(
            id: "whisperkit-tiny",
            supportedLanguages: ["en", "ja", "zh"]
        )
        let preference = ModelLanguagePreference(
            suiteName: suiteName,
            registeredModels: [descriptor]
        )

        let currentHint = await preference.hint(for: descriptor.id)
        let missingHint = await preference.hint(for: "missing")

        XCTAssertNil(currentHint)
        XCTAssertNil(missingHint)
    }

    func testSetHintPersistsSupportedLanguage() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let descriptor = makeDescriptor(
            id: "whisperkit-tiny",
            supportedLanguages: ["en", "ja", "zh"]
        )
        let preference = ModelLanguagePreference(
            suiteName: suiteName,
            registeredModels: [descriptor]
        )

        await preference.setHint("ja", for: descriptor.id)

        let currentHint = await preference.hint(for: descriptor.id)

        XCTAssertEqual(currentHint, "ja")
        XCTAssertEqual(storedHints(in: defaults), [descriptor.id: "ja"])
    }

    func testSetHintNilClearsStoredEntry() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let descriptor = makeDescriptor(
            id: "whisperkit-tiny",
            supportedLanguages: ["en", "ja", "zh"]
        )
        storedPreference(defaults: defaults).persist([descriptor.id: "ja"])
        let preference = ModelLanguagePreference(
            suiteName: suiteName,
            registeredModels: [descriptor]
        )

        await preference.setHint(nil, for: descriptor.id)

        let currentHint = await preference.hint(for: descriptor.id)

        XCTAssertNil(currentHint)
        XCTAssertEqual(storedHints(in: defaults), [:])
    }

    func testValidationDropsEntriesForRemovedDescriptors() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let kept = makeDescriptor(
            id: "whisperkit-tiny",
            supportedLanguages: ["en", "ja", "zh"]
        )
        storedPreference(defaults: defaults).persist([
            kept.id: "ja",
            "removed-model": "en",
        ])

        let preference = ModelLanguagePreference(
            suiteName: suiteName,
            registeredModels: [kept]
        )

        let keptHint = await preference.hint(for: kept.id)
        let removedHint = await preference.hint(for: "removed-model")

        XCTAssertEqual(keptHint, "ja")
        XCTAssertNil(removedHint)
        XCTAssertEqual(storedHints(in: defaults), [kept.id: "ja"])
    }

    func testValidationDropsUnsupportedOrHiddenLanguages() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let whisperDescriptor = makeDescriptor(
            id: "whisperkit-tiny",
            supportedLanguages: ["en", "ja", "zh"]
        )
        let qwenDescriptor = makeDescriptor(
            id: "qwen3-asr-0.6b-f32",
            engine: .qwen3ASR,
            supportedLanguages: nil
        )
        storedPreference(defaults: defaults).persist([
            whisperDescriptor.id: "fr",
            qwenDescriptor.id: "ja",
        ])

        let preference = ModelLanguagePreference(
            suiteName: suiteName,
            registeredModels: [whisperDescriptor, qwenDescriptor]
        )

        let whisperHint = await preference.hint(for: whisperDescriptor.id)
        let qwenHint = await preference.hint(for: qwenDescriptor.id)

        XCTAssertNil(whisperHint)
        XCTAssertNil(qwenHint)
        XCTAssertEqual(storedHints(in: defaults), [:])
    }

    private func makeDescriptor(
        id: String,
        engine: TranscriptionEngine = .whisperKit,
        supportedLanguages: [String]?
    ) -> ModelDescriptor {
        ModelDescriptor(
            id: id,
            displayName: id,
            shortDescription: "fixture",
            architecture: "Whisper",
            repository: "example/\(id)",
            revision: "abc123",
            requiredRelativePaths: ["model.bin"],
            approximateSizeBytes: 1,
            engine: engine,
            supportedLanguages: supportedLanguages
        )
    }

    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "ModelLanguagePreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func storedHints(in defaults: UserDefaults) -> [String: String] {
        storedPreference(defaults: defaults).resolve()
    }

    private func storedPreference(
        defaults: UserDefaults
    ) -> Preference<[String: String]> {
        Preference(
            key: ModelLanguagePreference.userDefaultsKey,
            default: [:],
            defaults: defaults
        )
    }
}
