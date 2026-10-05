import PersonalScribeCore
import PersonalScribeSession
import SwiftUI

@MainActor
public struct SettingsTab: View {
    @State private var selectedSubTab: SettingsSubTab = .general

    private let defaults: UserDefaults
    private let permissionService: any PermissionService
    private let shortcutsNavigationRequest: Int?
    private let modelsNavigationRequest: Int?
    private let onConsumeShortcutsNavigationRequest: @MainActor (Int?) -> Void
    private let onConsumeModelsNavigationRequest: @MainActor (Int?) -> Void
    private let menuBarVisibilityProvider: @MainActor () -> Bool
    private let menuBarVisibilitySetter: @MainActor (Bool) -> Void
    private let openDiagnosticsWindow: @MainActor () -> Void

    public init(
        defaults: UserDefaults = .standard,
        permissionService: any PermissionService,
        shortcutsNavigationRequest: Int? = nil,
        modelsNavigationRequest: Int? = nil,
        onConsumeShortcutsNavigationRequest: @escaping @MainActor (Int?) -> Void = { _ in },
        onConsumeModelsNavigationRequest: @escaping @MainActor (Int?) -> Void = { _ in },
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
        self.shortcutsNavigationRequest = shortcutsNavigationRequest
        self.modelsNavigationRequest = modelsNavigationRequest
        self.onConsumeShortcutsNavigationRequest = onConsumeShortcutsNavigationRequest
        self.onConsumeModelsNavigationRequest = onConsumeModelsNavigationRequest
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
                        shortcutsNavigationRequest: shortcutsNavigationRequest,
                        onConsumeShortcutsNavigationRequest: onConsumeShortcutsNavigationRequest,
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
                            permissionService: permissionService
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
        .onChange(of: shortcutsNavigationRequest) {
            selectedSubTab = .general
        }
        .onChange(of: modelsNavigationRequest) {
            selectedSubTab = .aiModels
            onConsumeModelsNavigationRequest(modelsNavigationRequest)
        }
        .onAppear {
            if modelsNavigationRequest != nil {
                selectedSubTab = .aiModels
                onConsumeModelsNavigationRequest(modelsNavigationRequest)
            } else if shortcutsNavigationRequest != nil {
                selectedSubTab = .general
            }
        }
    }
}
