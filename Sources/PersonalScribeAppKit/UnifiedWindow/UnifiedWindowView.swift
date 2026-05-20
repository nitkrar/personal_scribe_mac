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
    @Environment(\.colorScheme) private var colorScheme

    // Tab-content dependencies. ViewModels are constructed once per
    // window lifetime by UnifiedWindowController and passed through;
    // recreating this view for WindowTint changes leaves @Published
    // subscriptions intact.
    @ObservedObject var homeViewModel: HomeTabViewModel
    @ObservedObject var transcriptionsViewModel: TranscriptionsTabViewModel
    @ObservedObject var modesViewModel: ModesListViewModel
    @ObservedObject var microphoneFooterViewModel: MicrophoneFooterViewModel
    let permissionService: any PermissionService
    let defaults: UserDefaults
    let menuBarVisibilityProvider: @MainActor () -> Bool
    let menuBarVisibilitySetter: @MainActor (Bool) -> Void
    let openDiagnosticsWindow: @MainActor () -> Void

    init(
        model: UnifiedWindowModel,
        windowTint: WindowTint = .warm,
        homeViewModel: HomeTabViewModel,
        transcriptionsViewModel: TranscriptionsTabViewModel,
        modesViewModel: ModesListViewModel,
        microphoneFooterViewModel: MicrophoneFooterViewModel,
        permissionService: any PermissionService,
        defaults: UserDefaults = .standard,
        menuBarVisibilityProvider: @escaping @MainActor () -> Bool = { true },
        menuBarVisibilitySetter: @escaping @MainActor (Bool) -> Void = { _ in },
        openDiagnosticsWindow: @escaping @MainActor () -> Void = {}
    ) {
        self.model = model
        self.windowTint = windowTint
        self.homeViewModel = homeViewModel
        self.transcriptionsViewModel = transcriptionsViewModel
        self.modesViewModel = modesViewModel
        self.microphoneFooterViewModel = microphoneFooterViewModel
        self.permissionService = permissionService
        self.defaults = defaults
        self.menuBarVisibilityProvider = menuBarVisibilityProvider
        self.menuBarVisibilitySetter = menuBarVisibilitySetter
        self.openDiagnosticsWindow = openDiagnosticsWindow
    }

    var body: some View {
        // Pin column visibility to `.all` so macOS never auto-collapses
        // the sidebar — either via the toolbar chevron or when detail
        // content requests more width than the current window fits.
        // The sidebar is the only way to route between top-level tabs,
        // so losing it leaves the user stranded on whatever tab is
        // active (see bug #1b, 2026-04-21 dogfood).
        NavigationSplitView(columnVisibility: .constant(.all)) {
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

            List(AppTab.sidebarListCases, selection: tabBinding) { tab in
                sidebarRow(for: tab)
                    .tag(tab)
            }
            .listStyle(.sidebar)

            Spacer(minLength: 0)

            microphoneFooter
                .padding(.horizontal, PersonalScribeTheme.Spacing.lg)
                .padding(.top, PersonalScribeTheme.Spacing.md)
                .padding(.bottom, PersonalScribeTheme.Spacing.xs)

            aboutFooter
                .padding(.horizontal, PersonalScribeTheme.Spacing.lg)
                .padding(.top, PersonalScribeTheme.Spacing.xs)
                .padding(.bottom, PersonalScribeTheme.Spacing.md)
        }
        .background(UnifiedWindowChrome.sidebarBackground(scheme: colorScheme, tint: windowTint))
        // Thin 1px separator between sidebar and detail pane.
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(UnifiedWindowChrome.chromeSeparator(scheme: colorScheme, tint: windowTint))
                .frame(width: 1)
        }
    }

    /// Sidebar row with a champagne left-accent bar on the active tab.
    @ViewBuilder
    private func sidebarRow(for tab: AppTab) -> some View {
        let isActive = model.activeTab == tab
        let accentColor = PersonalScribeTheme.Palette.for(scheme: colorScheme).brandChampagne
        HStack(spacing: 0) {
            // Champagne accent bar — 3pt wide, full row height.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(isActive ? accentColor : Color.clear)
                .frame(width: 3)
                .padding(.vertical, 4)

            Label(tab.rawValue, systemImage: tab.systemImageName)
                .padding(.leading, PersonalScribeTheme.Spacing.xs)
        }
    }

    private var brandHeader: some View {
        HStack(spacing: PersonalScribeTheme.Spacing.sm) {
            PersonalScribeLogoView()
                .frame(width: 24, height: 24)
            Text(AppBrand.displayName)
                .font(PersonalScribeTheme.Typography.title.font)
                .foregroundStyle(UnifiedWindowChrome.chromeText(scheme: colorScheme, tint: windowTint))
        }
    }

    // Status readout of the currently-configured input device
    // (issue #008). Click / hover stays inert — the clickable
    // title-bar accessory is tracked separately as #037.
    //
    // The view model observes `UserDefaults.didChangeNotification` so
    // the label updates live when the user picks a device from the
    // menu-bar Microphone submenu (which writes `SelectedAudioInputDeviceID`).
    private var microphoneFooter: some View {
        HStack(spacing: PersonalScribeTheme.Spacing.xs) {
            Image(systemName: "mic")
            Text(microphoneFooterViewModel.currentDeviceName ?? "No input device")
                .font(PersonalScribeTheme.Typography.caption.font)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(UnifiedWindowChrome.chromeText(scheme: colorScheme, tint: windowTint).opacity(0.6))
        .accessibilityLabel(
            "Current input device: \(microphoneFooterViewModel.currentDeviceName ?? "None")"
        )
    }

    /// Clickable footer row for the About tab. Styled to match the
    /// Microphone footer (muted caption + symbol) rather than the
    /// sidebar-list tab rows, so it reads as a secondary affordance
    /// rather than a peer of Home / Transcriptions / Modes / Settings.
    private var aboutFooter: some View {
        Button {
            model.setActiveTab(.about)
        } label: {
            HStack(spacing: PersonalScribeTheme.Spacing.xs) {
                Image(systemName: AppTab.about.systemImageName)
                Text(AppTab.about.rawValue)
                    .font(PersonalScribeTheme.Typography.caption.font)
                Spacer(minLength: 0)
            }
            .foregroundStyle(
                UnifiedWindowChrome.chromeText(scheme: colorScheme, tint: windowTint).opacity(
                    model.activeTab == .about ? 1.0 : 0.6
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("About \(AppBrand.displayName)"))
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
            .background(UnifiedWindowChrome.detailBackground(scheme: colorScheme, tint: windowTint))
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
            SettingsTab(
                defaults: defaults,
                permissionService: permissionService,
                menuBarVisibilityProvider: menuBarVisibilityProvider,
                menuBarVisibilitySetter: menuBarVisibilitySetter,
                openDiagnosticsWindow: openDiagnosticsWindow
            )
        case .about:
            AboutSubTab()
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
