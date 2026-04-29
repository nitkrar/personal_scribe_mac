import PersonalScribeCore
import PersonalScribeSession
import SwiftUI

/// Modes tab for the unified window (#089). Hosts the modes-list +
/// detail editor in a `NavigationStack`. The list-tab body keeps the
/// historical "Modes" page title outside the nav stack so the unified
/// window's outer chrome stays consistent with other tabs.
@MainActor
struct ModesTab: View {
    @ObservedObject private var viewModel: ModesListViewModel

    init(viewModel: ModesListViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.lg) {
            Text("Modes")
                .font(PersonalScribeTheme.Typography.largeTitle.font)
            ModesListView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { viewModel.startObserving() }
        .onDisappear { viewModel.stopObserving() }
    }
}
