import SwiftUI
import PersonalScribeCore

@MainActor
struct ModelLanguagePicker: View {
    struct Option: Identifiable, Equatable {
        let code: String?
        let label: String

        var id: String { code ?? "__auto_detect__" }
    }

    let descriptor: ModelDescriptor
    let phase: ModelDownloadState.Phase

    @StateObject private var viewModel: ModelLanguagePickerViewModel

    init(
        descriptor: ModelDescriptor,
        phase: ModelDownloadState.Phase,
        preference: ModelLanguagePreference = AppComposition.modelLanguagePreference,
        locale: Locale = .current
    ) {
        self.descriptor = descriptor
        self.phase = phase
        _viewModel = StateObject(
            wrappedValue: ModelLanguagePickerViewModel(
                descriptor: descriptor,
                preference: preference,
                locale: locale
            )
        )
    }

    var body: some View {
        if Self.isVisible(descriptor: descriptor, phase: phase) {
            HStack(alignment: .firstTextBaseline) {
                Text("Language")
                    .font(PersonalScribeTheme.Typography.body.font)

                Spacer(minLength: PersonalScribeTheme.Spacing.sm)

                Picker("", selection: selectionBinding) {
                    ForEach(viewModel.options) { option in
                        Text(option.label).tag(option.code as String?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 240)
            }
            .task(id: descriptor.id) {
                await viewModel.loadSelection()
            }
        }
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedLanguage },
            set: { newValue in
                Task {
                    await viewModel.updateSelection(newValue)
                }
            }
        )
    }

    static func isVisible(
        descriptor: ModelDescriptor,
        phase: ModelDownloadState.Phase
    ) -> Bool {
        guard descriptor.supportedLanguages != nil else {
            return false
        }

        return phase == .ready
    }

    static func options(
        for descriptor: ModelDescriptor,
        locale: Locale = .current,
        languageNameResolver: (Locale, String) -> String? = { locale, languageCode in
            locale.localizedString(forLanguageCode: languageCode)
        }
    ) -> [Option] {
        guard let supportedLanguages = descriptor.supportedLanguages else {
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

@MainActor
final class ModelLanguagePickerViewModel: ObservableObject {
    @Published private(set) var selectedLanguage: String?

    let descriptor: ModelDescriptor
    let options: [ModelLanguagePicker.Option]

    private let preference: ModelLanguagePreference

    init(
        descriptor: ModelDescriptor,
        preference: ModelLanguagePreference,
        locale: Locale = .current
    ) {
        self.descriptor = descriptor
        self.preference = preference
        self.options = ModelLanguagePicker.options(
            for: descriptor,
            locale: locale
        )
    }

    func loadSelection() async {
        selectedLanguage = await preference.hint(for: descriptor.id)
    }

    func updateSelection(_ language: String?) async {
        selectedLanguage = language
        await preference.setHint(language, for: descriptor.id)
    }
}
