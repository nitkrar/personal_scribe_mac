import SwiftUI
import PersonalScribeCore
import PersonalScribeSession

/// Settings > AI Models tab.
///
/// Stage A (step 3.2): renders a row per registered voice model with a
/// live download/ready chip driven by
/// `DefaultModelService.downloadStates`. Replaces the pre-3.2 inert tab
/// that hardcoded `StatusPill(status: .ready, label: "Current")`
/// regardless of disk reality.
///
/// The tab deliberately keeps a single `SettingsSection` header ("Voice
/// models") so Stage B can add a second "AI models" section without
/// restructuring the view. Delete / disk-space precheck / AI-model rows
/// are Stage B (deferred — see `plans/backlog/model-download-ux-bug-research.md`).
@MainActor
public struct AIModelsTab: View {
    @ObservedObject private var service: DefaultModelService

    public init(service: DefaultModelService = AppComposition.modelService) {
        self.service = service
    }

    public var body: some View {
        SettingsTabContainer {
            SettingsSection(
                title: "Voice models",
                description: "Voice-to-text models. Active mark follows Modes tab selection."
            ) {
                VStack(spacing: SettingsLayout.itemSpacing) {
                    ForEach(service.registeredModels, id: \.id) { descriptor in
                        ModelRow(
                            descriptor: descriptor,
                            state: service.downloadStates[descriptor.id],
                            isActive: service.activeDescriptor.voiceModel.id == descriptor.id,
                            onActivate: { activate(descriptor) }
                        )
                    }
                }
            }
        }
        // Ticket #039: belt + suspenders on top of `@ObservedObject`.
        // Re-sync against disk on every navigate-in so a model that
        // appeared (or disappeared) from disk while the tab was
        // off-screen flips its chip on re-entry. Idempotent when state
        // matches — no spurious renders.
        .onAppear {
            service.refresh()
        }
    }

    private func activate(_ descriptor: ModelDescriptor) {
        let target = ActiveModelDescriptor(
            voiceModel: descriptor,
            aiModelID: service.activeDescriptor.aiModelID
        )
        Task { @MainActor in
            try? await service.setActive(target)
        }
    }
}

/// A single row in the AI Models voice-model list.
///
/// Derives its chip label / color and trailing button from the injected
/// `ModelDownloadState?`. Rendering is pure — all side effects go
/// through the `onActivate` closure owned by the tab, so this view is
/// trivially reusable for Stage B's AI-models section.
///
/// Ticket #007: inline `shortDescription` replaces the raw byte size
/// as the second line; size moves to the ⓘ info popover alongside
/// computed-relative Speed / Accuracy bars and detail metadata. Row
/// padding is tightened (`compactCardPadding`) so three models fit
/// under the default `windowHeight` without scrolling.
@MainActor
struct ModelRow: View {
    let descriptor: ModelDescriptor
    let state: ModelDownloadState?
    let isActive: Bool
    /// Siblings used for the info popover's relative-rank computation.
    /// Defaults to the catalog-registered list.
    let siblings: [ModelDescriptor]
    let onActivate: () -> Void

    @State private var isInfoPopoverPresented = false

    init(
        descriptor: ModelDescriptor,
        state: ModelDownloadState?,
        isActive: Bool,
        siblings: [ModelDescriptor] = BuiltInModelCatalog.registeredModels,
        onActivate: @escaping () -> Void
    ) {
        self.descriptor = descriptor
        self.state = state
        self.isActive = isActive
        self.siblings = siblings
        self.onActivate = onActivate
    }

    var body: some View {
        SettingsCard(padding: SettingsLayout.compactCardPadding) {
            HStack(alignment: .center, spacing: SettingsLayout.itemSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(descriptor.displayName)
                            .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))

                        infoButton
                    }

                    if !descriptor.shortDescription.isEmpty {
                        Text(descriptor.shortDescription)
                            .font(PersonalScribeTheme.Typography.caption.font)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 0)

                StatusPill(status: chip.status, label: chip.label)

                actionButton
            }
        }
    }

    // MARK: - Info popover

    private var infoButton: some View {
        Button(action: { isInfoPopoverPresented.toggle() }) {
            Image(systemName: "info.circle")
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(descriptor.displayName)")
        .help("Show model details")
        .popover(
            isPresented: $isInfoPopoverPresented,
            arrowEdge: .top
        ) {
            ModelInfoPopover(
                presenter: ModelInfoPopoverPresenter(
                    descriptor: descriptor,
                    siblings: siblings
                )
            )
        }
    }

    // MARK: - Chip derivation (internal for tests)

    var phase: ModelDownloadState.Phase {
        state?.phase ?? .notDownloaded
    }

    var chip: (status: StatusPill.Status, label: String) {
        switch phase {
        case .notDownloaded:
            return (.neutral, "Not downloaded")
        case .downloading:
            let percent = Int((state?.fractionCompleted ?? 0) * 100)
            return (.warning, "Downloading \(percent)%")
        case .loading:
            return (.warning, "Loading…")
        case .ready:
            return (.ready, isActive ? "Active" : "Ready")
        case .failed(let message):
            // Trim the failure message to keep the chip narrow; the full
            // String(describing: error) still surfaces in logs.
            let trimmed = message.split(separator: "\n").first.map(String.init) ?? message
            let concise = trimmed.count > 40 ? String(trimmed.prefix(37)) + "…" : trimmed
            return (.failed, "Failed: \(concise)")
        }
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        switch phase {
        case .notDownloaded:
            Button("Download", action: onActivate)
                .buttonStyle(.borderedProminent)
        case .downloading, .loading:
            EmptyView()
        case .ready:
            if isActive {
                Button("Active") {}
                    .buttonStyle(.bordered)
                    .disabled(true)
            } else {
                Button("Set Active", action: onActivate)
                    .buttonStyle(.bordered)
            }
        case .failed:
            Button("Retry", action: onActivate)
                .buttonStyle(.borderedProminent)
        }
    }
}
