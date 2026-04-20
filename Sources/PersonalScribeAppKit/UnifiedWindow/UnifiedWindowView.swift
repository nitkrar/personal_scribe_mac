import SwiftUI
import PersonalScribeCore

/// Root SwiftUI view for the unified window (M3.1 scaffold).
///
/// Layout: `NavigationSplitView` with a fixed-width sidebar on the
/// leading edge and a tab-switched detail area. The detail area
/// content is a stub in M3.1 (each tab's real content lands in
/// M3.2–M3.5); the shell, navigation, and window tint wiring are
/// production-shape.
///
/// Reference: `plans/App UI design/Claude_Final_Bundle_Prompt.md` §3.
@MainActor
struct UnifiedWindowView: View {
    @ObservedObject var model: UnifiedWindowModel
    let windowTint: WindowTint

    // Tab-content dependencies. ViewModels are constructed once per
    // window lifetime by UnifiedWindowController and passed through;
    // recreating this view for WindowTint changes leaves @Published
    // subscriptions intact.
    @ObservedObject var homeViewModel: HomeTabViewModel
    @ObservedObject var transcriptionsViewModel: TranscriptionsTabViewModel
    @ObservedObject var modesViewModel: ModesTabViewModel
    let permissionService: any PermissionService
    let defaults: UserDefaults

    init(
        model: UnifiedWindowModel,
        windowTint: WindowTint = .warm,
        homeViewModel: HomeTabViewModel,
        transcriptionsViewModel: TranscriptionsTabViewModel,
        modesViewModel: ModesTabViewModel,
        permissionService: any PermissionService,
        defaults: UserDefaults = .standard
    ) {
        self.model = model
        self.windowTint = windowTint
        self.homeViewModel = homeViewModel
        self.transcriptionsViewModel = transcriptionsViewModel
        self.modesViewModel = modesViewModel
        self.permissionService = permissionService
        self.defaults = defaults
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: PersonalScribeTheme.Layout.sidebarWidth,
                    ideal: PersonalScribeTheme.Layout.sidebarWidth,
                    max: PersonalScribeTheme.Layout.sidebarWidth
                )
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(
            minWidth: PersonalScribeTheme.Layout.windowMinWidth,
            minHeight: PersonalScribeTheme.Layout.windowMinHeight
        )
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader
                .padding(.horizontal, PersonalScribeTheme.Spacing.lg)
                .padding(.vertical, PersonalScribeTheme.Spacing.lg)

            List(AppTab.allCases, selection: tabBinding) { tab in
                Label(tab.rawValue, systemImage: tab.systemImageName)
                    .tag(tab)
            }
            .listStyle(.sidebar)

            Spacer(minLength: 0)

            microphoneFooter
                .padding(.horizontal, PersonalScribeTheme.Spacing.lg)
                .padding(.vertical, PersonalScribeTheme.Spacing.md)
        }
        .background(windowTint.secondaryBackground)
    }

    private var brandHeader: some View {
        HStack(spacing: PersonalScribeTheme.Spacing.sm) {
            PersonalScribeLogoView()
                .frame(width: 24, height: 24)
            Text(AppBrand.displayName)
                .font(PersonalScribeTheme.Typography.title.font)
                .foregroundStyle(windowTint.primaryText)
        }
    }

    // Placeholder for M3.1 — the real indicator (current selected
    // input device + level meter) lands alongside microphone
    // selection in a later milestone.
    private var microphoneFooter: some View {
        HStack(spacing: PersonalScribeTheme.Spacing.xs) {
            Image(systemName: "mic")
            Text("Microphone")
                .font(PersonalScribeTheme.Typography.caption.font)
        }
        .foregroundStyle(windowTint.primaryText.opacity(0.6))
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        tabView(for: model.activeTab)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .padding(PersonalScribeTheme.Spacing.xl)
            .background(windowTint.primaryBackground)
            .windowTint(windowTint)
    }

    @ViewBuilder
    private func tabView(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeTab(viewModel: homeViewModel)
        case .transcriptions:
            TranscriptionsTab(viewModel: transcriptionsViewModel)
        case .modes:
            ModesTab(viewModel: modesViewModel)
        case .settings:
            SettingsTab(defaults: defaults, permissionService: permissionService)
        }
    }

    // MARK: - Binding bridge

    private var tabBinding: Binding<AppTab?> {
        Binding<AppTab?>(
            get: { model.activeTab },
            set: { newValue in
                if let newValue {
                    model.setActiveTab(newValue)
                }
            }
        )
    }
}
