import SwiftUI

@MainActor
public struct SettingsTab: View {
    @State private var selectedSubTab: SettingsSubTab = .general

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.lg) {
            Text("Settings")
                .font(PersonalScribeTheme.Typography.largeTitle.font)

            Picker("Settings Section", selection: $selectedSubTab) {
                ForEach(SettingsSubTab.allCases) { subTab in
                    Text(subTab.rawValue)
                        .tag(subTab)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch selectedSubTab {
                case .general:
                    GeneralTab(defaults: defaults)
                case .permissions:
                    PermissionsSubTab()
                case .about:
                    AboutSubTab()
                }
            }
        }
    }
}

private struct PermissionsSubTab: View {
    var body: some View {
        Text("Permissions sub-tab lands in M3.3b")
    }
}

private struct AboutSubTab: View {
    var body: some View {
        Text("About sub-tab lands in M3.3c")
    }
}
