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
@MainActor
struct ModelRow: View {
    let descriptor: ModelDescriptor
    let state: ModelDownloadState?
    let isActive: Bool
    let onActivate: () -> Void

    var body: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: SettingsLayout.itemSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(descriptor.displayName)
                        .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))
                    Text(sizeDescription)
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                StatusPill(status: chip.status, label: chip.label)

                actionButton
            }
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

    // MARK: - Size formatting (internal for tests)

    var sizeDescription: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: descriptor.approximateSizeBytes)
    }
}
