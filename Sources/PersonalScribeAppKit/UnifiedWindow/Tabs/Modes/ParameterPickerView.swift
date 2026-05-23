import SwiftUI
import PersonalScribeCore

/// Three-option picker for `Parameter<Bool>` (#089 L-19). Used in the
/// mode-detail Capture / Output cards. The "Default" option shows the
/// live UserDefaults value parenthetically so the user can tell which
/// behavior they'll get without opening GeneralTab.
@MainActor
struct ParameterPickerView: View {
    let title: String
    let settingKey: SettingKey<Bool>
    let parameter: Parameter<Bool>
    let onChange: (Parameter<Bool>) -> Void
    let defaults: UserDefaults

    init(
        title: String,
        settingKey: SettingKey<Bool>,
        parameter: Parameter<Bool>,
        defaults: UserDefaults = .standard,
        onChange: @escaping (Parameter<Bool>) -> Void
    ) {
        self.title = title
        self.settingKey = settingKey
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
                Text(Self.overrideLabel(for: true)).tag(Selection.forceOn)
                Text(Self.overrideLabel(for: false)).tag(Selection.forceOff)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 220)
        }
    }

    private var defaultLabel: String {
        let live = settingKey.resolve(from: defaults)
        return Self.defaultLabel(for: live)
    }

    static func defaultLabel(for value: Bool) -> String {
        "Default (\(overrideLabel(for: value)))"
    }

    static func overrideLabel(for value: Bool) -> String {
        value ? "On" : "Off"
    }

    private var selectionBinding: Binding<Selection> {
        Binding(
            get: {
                switch parameter {
                case .setting:
                    return .useDefault
                case .override(let value):
                    return value ? .forceOn : .forceOff
                }
            },
            set: { newValue in
                switch newValue {
                case .useDefault:
                    onChange(.setting(settingKey))
                case .forceOn:
                    onChange(.override(true))
                case .forceOff:
                    onChange(.override(false))
                }
            }
        )
    }

    private enum Selection: Hashable {
        case useDefault
        case forceOn
        case forceOff
    }
}
