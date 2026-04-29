import SwiftUI
import PersonalScribeCore

/// Per-mode override picker for `Parameter<SpeakerSeparationSensitivity>`
/// (#092). Mirrors `ParameterPickerView`'s tri-state shape (Default vs.
/// per-mode override) but accepts an enum value rather than the boolean
/// On/Off the existing picker is hardcoded against. Lives separately so
/// `ParameterPickerView` stays focused on the boolean recipe parameters
/// it already serves.
@MainActor
struct SensitivityParameterPickerView: View {
    let title: String
    let parameter: Parameter<SpeakerSeparationSensitivity>
    let onChange: (Parameter<SpeakerSeparationSensitivity>) -> Void
    let defaults: UserDefaults

    init(
        title: String,
        parameter: Parameter<SpeakerSeparationSensitivity>,
        defaults: UserDefaults = .standard,
        onChange: @escaping (Parameter<SpeakerSeparationSensitivity>) -> Void
    ) {
        self.title = title
        self.parameter = parameter
        self.defaults = defaults
        self.onChange = onChange
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(PersonalScribeTheme.Typography.body.font)

            Spacer(minLength: PersonalScribeTheme.Spacing.sm)

            Picker("", selection: selectionBinding) {
                Text(defaultLabel).tag(Selection.useDefault)
                Text("Force Relaxed").tag(Selection.force(.relaxed))
                Text("Force Balanced").tag(Selection.force(.balanced))
                Text("Force Strict").tag(Selection.force(.strict))
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 260)
        }
    }

    private var defaultLabel: String {
        let live = SpeakerSeparationSensitivityPreference.resolve(from: defaults)
        return "Default (Live: \(Self.label(for: live)))"
    }

    private var selectionBinding: Binding<Selection> {
        Binding(
            get: {
                switch parameter {
                case .setting:
                    return .useDefault
                case .override(let value):
                    return .force(value)
                }
            },
            set: { newValue in
                switch newValue {
                case .useDefault:
                    onChange(.setting(PreferenceKeys.speakerSeparationSensitivity))
                case .force(let value):
                    onChange(.override(value))
                }
            }
        )
    }

    private static func label(for sensitivity: SpeakerSeparationSensitivity) -> String {
        switch sensitivity {
        case .relaxed: "Relaxed"
        case .balanced: "Balanced"
        case .strict: "Strict"
        }
    }

    private enum Selection: Hashable {
        case useDefault
        case force(SpeakerSeparationSensitivity)
    }
}
