import SwiftUI
import PersonalScribeCore
import PersonalScribeSession

/// Settings > AI Models tab.
///
/// Renders one `SettingsSection` per enabled `ModelKind` (#024.10),
/// with live download/ready chips driven by
/// `ActiveModelService.downloadStates`. Today only `.asr` is enabled;
/// future kinds (streaming ASR, diarization, …) light up as the
/// corresponding adapters land (#078).
@MainActor
public struct AIModelsTab: View {
    @ObservedObject private var service: ActiveModelService

    public init(service: ActiveModelService = AppComposition.modelService) {
        self.service = service
    }

    public var body: some View {
        SettingsTabContainer {
            // #024.10: one `SettingsSection` per enabled `ModelKind`.
            // Today only `.asr` is enabled — non-asr kinds (streaming
            // ASR, diarization, …) stay hidden until adapters land
            // (#078 follow-up). Section header uses `kind.displayName`.
            ForEach(enabledKinds, id: \.self) { kind in
                SettingsSection(
                    title: kind.displayName,
                    description: descriptionForSection(kind: kind)
                ) {
                    VStack(spacing: SettingsLayout.itemSpacing) {
                        ForEach(service.enabledModels(kind: kind), id: \.id) { descriptor in
                            ModelRow(
                                descriptor: descriptor,
                                state: service.downloadStates[descriptor.id],
                                isActive: service.activeDescriptor(for: descriptor.kind)?.id == descriptor.id,
                                onActivate: { activate(descriptor) },
                                onDownload: { download(descriptor) },
                                onDelete: { delete(descriptor) }
                            )
                        }
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

    private var enabledKinds: [ModelKind] {
        ModelKind.allCases.filter(\.isEnabled)
    }

    private func descriptionForSection(kind: ModelKind) -> String {
        switch kind {
        case .asr:
            return "Voice-to-text models. Active mark follows Modes tab selection."
        case .streamingASR, .vad, .diarization, .tts:
            return ""
        }
    }

    private func activate(_ descriptor: ModelDescriptor) {
        service.setActive(descriptor)
    }

    private func delete(_ descriptor: ModelDescriptor) {
        // #024: the service publishes `.notDownloaded` inside
        // `removeDownloaded`, so `@ObservedObject` will rerender the
        // row — no explicit `refresh()` call needed here.
        try? service.removeDownloaded(descriptor)
    }

    private func download(_ descriptor: ModelDescriptor) {
        // #024 follow-up: `download` is the download-only path. It
        // never reassigns the active model — that's `setActive`.
        Task { @MainActor in
            try? await service.download(descriptor)
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
    let onDownload: () -> Void
    let onDelete: () -> Void

    @State private var isInfoPopoverPresented = false

    init(
        descriptor: ModelDescriptor,
        state: ModelDownloadState?,
        isActive: Bool,
        siblings: [ModelDescriptor] = BuiltInModelCatalog.registeredModels,
        onActivate: @escaping () -> Void,
        onDownload: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {}
    ) {
        self.descriptor = descriptor
        self.state = state
        self.isActive = isActive
        self.siblings = siblings
        self.onActivate = onActivate
        self.onDownload = onDownload
        self.onDelete = onDelete
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
                        HStack(spacing: 6) {
                            Text(descriptor.shortDescription)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text("·")
                            Text(Self.diskSizeLabel(for: descriptor))
                        }
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                trailingControls
            }
        }
    }

    // MARK: - Trailing controls

    @ViewBuilder
    private var trailingControls: some View {
        switch phase {
        case .downloading, .loading, .failed:
            StatusPill(status: chip.status, label: chip.label)
            actionButton
        case .notDownloaded, .ready:
            activityDot
            if phase == .ready, !isActive {
                Button("Activate", action: onActivate)
                    .buttonStyle(.borderless)
                    .font(PersonalScribeTheme.Typography.caption.font)
            }
            stableIconButton
        }
    }

    private var activityDot: some View {
        let isReadyAndActive = (phase == .ready) && isActive
        return Circle()
            .fill(isReadyAndActive ? Color.green : Color.secondary)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var stableIconButton: some View {
        switch phase {
        case .notDownloaded:
            Button(action: onDownload) {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Download \(descriptor.displayName)")
            .help("Download \(descriptor.displayName)")
        case .ready:
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(descriptor.displayName)")
            .help("Delete \(descriptor.displayName)")
        case .downloading, .loading, .failed:
            EmptyView()
        }
    }

    private static func diskSizeLabel(for descriptor: ModelDescriptor) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: descriptor.approximateSizeBytes)
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

    // MARK: - Action button (transient phases only)

    @ViewBuilder
    private var actionButton: some View {
        switch phase {
        case .downloading, .loading:
            EmptyView()
        case .failed:
            // #024.4: Retry re-runs the download, not setActive. Before
            // the activate/download split, onActivate auto-downloaded;
            // after the split, Retry must route to onDownload or the
            // failed row is permanently stuck.
            Button("Retry", action: onDownload)
                .buttonStyle(.borderedProminent)
        case .notDownloaded, .ready:
            // Stable phases are handled by `stableIconButton`.
            EmptyView()
        }
    }
}
