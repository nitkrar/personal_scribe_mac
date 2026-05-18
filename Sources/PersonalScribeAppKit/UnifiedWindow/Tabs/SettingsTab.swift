import PersonalScribeCore
import PersonalScribeSession
import SwiftUI

@MainActor
public struct SettingsTab: View {
    @State private var selectedSubTab: SettingsSubTab = .general

    private let defaults: UserDefaults
    private let permissionService: any PermissionService
    private let menuBarVisibilityProvider: @MainActor () -> Bool
    private let menuBarVisibilitySetter: @MainActor (Bool) -> Void
    private let openDiagnosticsWindow: @MainActor () -> Void

    public init(
        defaults: UserDefaults = .standard,
        permissionService: any PermissionService,
        // Default to a no-op + always-visible reading. Production
        // wiring lives in `PersonalScribeAppMain` and points at
        // `StatusItemControllerHost.{isMenuBarVisible, setMenuBarVisible}`.
        // Default kept so existing test surfaces don't have to know
        // about the menu-bar plumbing.
        menuBarVisibilityProvider: @escaping @MainActor () -> Bool = { true },
        menuBarVisibilitySetter: @escaping @MainActor (Bool) -> Void = { _ in },
        openDiagnosticsWindow: @escaping @MainActor () -> Void = {}
    ) {
        self.defaults = defaults
        self.permissionService = permissionService
        self.menuBarVisibilityProvider = menuBarVisibilityProvider
        self.menuBarVisibilitySetter = menuBarVisibilitySetter
        self.openDiagnosticsWindow = openDiagnosticsWindow
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
                    GeneralTab(
                        defaults: defaults,
                        menuBarVisibilityProvider: menuBarVisibilityProvider,
                        menuBarVisibilitySetter: menuBarVisibilitySetter
                    )
                case .aiModels:
                    AIModelsTab()
                case .advanced:
                    AdvancedTab(
                        defaults: defaults,
                        openDiagnosticsWindow: openDiagnosticsWindow
                    )
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
