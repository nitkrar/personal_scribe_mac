import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

@MainActor
final class ModeLanguagePickerViewTests: XCTestCase {
    func testOptionsPrependAutoDetectAndSortLocalizedLabels() {
        let descriptor = ModelDescriptor(
            id: "multilingual",
            displayName: "Multilingual",
            repoFolderName: "multilingual",
            shortDescription: "",
            architecture: "",
            repository: "repo",
            revision: "main",
            requiredRelativePaths: ["model.bin"],
            approximateSizeBytes: 1,
            isEnabled: true,
            engine: .whisperKit,
            supportedLanguages: ["ja", "en"]
        )

        let options = ModeLanguagePickerView.options(
            for: descriptor,
            languageNameResolver: { _, code in
                switch code {
                case "en": return "English"
                case "ja": return "Japanese"
                default: return nil
                }
            }
        )

        XCTAssertEqual(
            options,
            [
                .init(code: nil, label: "Auto-detect"),
                .init(code: "en", label: "English (en)"),
                .init(code: "ja", label: "Japanese (ja)"),
            ]
        )
    }

    func testLocalizedDisplayNameFallsBackToBareCode() {
        XCTAssertEqual(
            ModeLanguagePickerView.localizedDisplayName(
                for: "ga",
                languageNameResolver: { _, _ in nil }
            ),
            "ga"
        )
    }
}
