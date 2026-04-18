import SwiftUI

@MainActor
struct RecordButtonView: View {
    let viewModel: RecordButtonViewModel
    let action: @MainActor () async -> Void

    var body: some View {
        Button(role: viewModel.usesDestructiveRole ? .destructive : nil) {
            Task {
                await action()
            }
        } label: {
            Label(viewModel.title, systemImage: viewModel.systemImageName)
        }
        .disabled(!viewModel.isEnabled)
    }
}
