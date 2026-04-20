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

    init(
        model: UnifiedWindowModel,
        windowTint: WindowTint = .warm
    ) {
        self.model = model
        self.windowTint = windowTint
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
        tabStubView(for: model.activeTab)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .padding(PersonalScribeTheme.Spacing.xl)
            .background(windowTint.primaryBackground)
    }

    @ViewBuilder
    private func tabStubView(for tab: AppTab) -> some View {
        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.md) {
            Text(tab.rawValue)
                .font(PersonalScribeTheme.Typography.largeTitle.font)
                .foregroundStyle(windowTint.primaryText)

            Text(stubBody(for: tab))
                .font(PersonalScribeTheme.Typography.body.font)
                .foregroundStyle(windowTint.primaryText.opacity(0.6))
        }
    }

    private func stubBody(for tab: AppTab) -> String {
        switch tab {
        case .home:           return "Stats and recent transcriptions land in M3.5."
        case .transcriptions: return "Search + grouped transcript list migrate from NotesView in M3.2."
        case .modes:          return "Mode cards (Dictation, Command, Notes) land in M3.4."
        case .settings:       return "General / Permissions / About sub-tabs land in M3.3."
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
