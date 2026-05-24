import SwiftUI
import PersonalScribeCore

@MainActor
struct ModeLanguagePickerView: View {
    struct Option: Identifiable, Equatable {
        let code: String?
        let label: String

        var id: String { code ?? "__auto_detect__" }
    }

    let title: String
    let selectedLanguage: String?
    let options: [Option]
    let onChange: (String?) -> Void

    init(
        title: String = "Language",
        selectedLanguage: String?,
        options: [Option],
        onChange: @escaping (String?) -> Void
    ) {
        self.title = title
        self.selectedLanguage = selectedLanguage
        self.options = options
        self.onChange = onChange
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(PersonalScribeTheme.Typography.body.font)

            Spacer(minLength: PersonalScribeTheme.Spacing.sm)

            Picker("", selection: selectionBinding) {
                ForEach(options) { option in
                    Text(option.label).tag(option.code as String?)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 260)
        }
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { selectedLanguage },
            set: { onChange($0) }
        )
    }

    static func options(
        for descriptor: ModelDescriptor,
        locale: Locale = .current,
        languageNameResolver: (Locale, String) -> String? = { locale, languageCode in
            locale.localizedString(forLanguageCode: languageCode)
        }
    ) -> [Option] {
        guard let supportedLanguages = descriptor.supportedLanguages, !supportedLanguages.isEmpty else {
            return []
        }

        let localizedOptions = supportedLanguages
            .map { languageCode in
                Option(
                    code: languageCode,
                    label: localizedDisplayName(
                        for: languageCode,
                        locale: locale,
                        languageNameResolver: languageNameResolver
                    )
                )
            }
            .sorted {
                $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
            }

        return [Option(code: nil, label: "Auto-detect")] + localizedOptions
    }

    static func localizedDisplayName(
        for languageCode: String,
        locale: Locale = .current,
        languageNameResolver: (Locale, String) -> String? = { locale, languageCode in
            locale.localizedString(forLanguageCode: languageCode)
        }
    ) -> String {
        guard
            let localizedName = languageNameResolver(locale, languageCode)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !localizedName.isEmpty,
            localizedName.localizedCaseInsensitiveCompare(languageCode) != .orderedSame
        else {
            return languageCode
        }

        return "\(localizedName) (\(languageCode))"
    }
}
