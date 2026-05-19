import SwiftUI
import PersonalScribeCore

@MainActor
struct IntegerParameterStepperView: View {
    let title: String
    let settingKey: SettingKey<Int>
    let parameter: Parameter<Int>
    let range: ClosedRange<Int>
    let step: Int
    let onChange: (Parameter<Int>) -> Void
    let defaults: UserDefaults

    init(
        title: String,
        settingKey: SettingKey<Int>,
        parameter: Parameter<Int>,
        range: ClosedRange<Int>,
        step: Int,
        defaults: UserDefaults = .standard,
        onChange: @escaping (Parameter<Int>) -> Void
    ) {
        self.title = title
        self.settingKey = settingKey
        self.parameter = parameter
        self.range = range
        self.step = step
        self.defaults = defaults
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(PersonalScribeTheme.Typography.body.font)

                Spacer(minLength: PersonalScribeTheme.Spacing.sm)

                Picker("", selection: selectionBinding) {
                    Text(defaultLabel).tag(Selection.useDefault)
                    Text("Override").tag(Selection.override)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            }

            Stepper(
                value: valueBinding,
                in: range,
                step: step
            ) {
                Text("\(resolvedValue) ms")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(.secondary)
            }
            .disabled(isUsingDefault)
        }
    }

    private var isUsingDefault: Bool {
        if case .setting = parameter {
            return true
        }
        return false
    }

    private var resolvedValue: Int {
        switch parameter {
        case .setting:
            return settingKey.resolve(from: defaults)
        case .override(let value):
            return min(max(value, range.lowerBound), range.upperBound)
        }
    }

    private var defaultLabel: String {
        "Default (\(settingKey.resolve(from: defaults)) ms)"
    }

    private var selectionBinding: Binding<Selection> {
        Binding(
            get: { isUsingDefault ? .useDefault : .override },
            set: { newValue in
                switch newValue {
                case .useDefault:
                    onChange(.setting(settingKey))
                case .override:
                    onChange(.override(settingKey.resolve(from: defaults)))
                }
            }
        )
    }

    private var valueBinding: Binding<Int> {
        Binding(
            get: { resolvedValue },
            set: { newValue in
                onChange(
                    .override(
                        min(max(newValue, range.lowerBound), range.upperBound)
                    )
                )
            }
        )
    }

    private enum Selection: Hashable {
        case useDefault
        case override
    }
}
