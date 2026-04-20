import PersonalScribeCore
import SwiftUI

@MainActor
public struct SettingsTab: View {
    @State private var selectedSubTab: SettingsSubTab = .general

    private let defaults: UserDefaults
    private let permissionService: any PermissionService

    public init(
        defaults: UserDefaults = .standard,
        permissionService: any PermissionService
    ) {
        self.defaults = defaults
        self.permissionService = permissionService
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
                case .aiModels:
                    AIModelsTab()
                case .shortcuts:
                    ShortcutsTab(defaults: defaults)
                case .advanced:
                    AdvancedTab()
                case .permissions:
                    PermissionsSubTab(
                        viewModel: PermissionsSubTabViewModel(
                            permissionService: permissionService
                        )
                    )
                case .about:
                    AboutSubTab()
                }
            }
        }
    }
}
