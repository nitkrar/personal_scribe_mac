import PersonalScribeCore
import PersonalScribeSession
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
                case .advanced:
                    AdvancedTab()
                case .permissions:
                    PermissionsSubTab(
                        viewModel: PermissionsSubTabViewModel(
                            permissionService: permissionService,
                            defaults: defaults
                        )
                    )
                }
            }
        }
        // Settings uses a segmented `Picker` + `switch`, not SwiftUI's
        // `TabView`. The conditional render means `.onAppear` on
        // AIModelsTab does NOT reliably fire on every tab switch —
        // SwiftUI may keep the inactive view's state and skip the
        // appear hook. We observe the navigation state directly here
        // so the AI Models row reflects on-disk truth (e.g. after a
        // CLI `rm -rf .../models/<id>`) on every re-entry.
        .onChange(of: selectedSubTab) { _, new in
            if new == .aiModels {
                AppComposition.modelService.refresh()
            }
        }
    }
}
