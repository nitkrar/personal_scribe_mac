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
    enum RowVisibility: Equatable {
        case standard
        case filteredActive
    }

    struct DisplayedModel: Equatable {
        let descriptor: ModelDescriptor
        let visibility: RowVisibility
    }

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
                        if let filterNotice = Self.filterNotice(for: kind, service: service) {
                            Text(filterNotice)
                                .font(PersonalScribeTheme.Typography.caption.font)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        ForEach(Self.displayedRows(for: kind, service: service), id: \.descriptor.id) { row in
                            VStack(alignment: .leading, spacing: SettingsLayout.inlineSpacing) {
                                ModelRow(
                                    descriptor: row.descriptor,
                                    state: service.downloadStates[row.descriptor.id],
                                    isActive: service.activeDescriptor(for: kind)?.id == row.descriptor.id,
                                    onActivate: { activate(row.descriptor, forKind: kind) },
                                    onDownload: { download(row.descriptor) },
                                    onDelete: { delete(row.descriptor) }
                                )
                                .opacity(row.visibility == .filteredActive ? 0.7 : 1)

                                if row.visibility == .filteredActive {
                                    Text("Active model stays in use even though this filter hides it. Change Settings > Advanced to show it again.")
                                        .font(PersonalScribeTheme.Typography.caption.font)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
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

    static func displayedRows(
        for kind: ModelKind,
        service: ActiveModelService
    ) -> [DisplayedModel] {
        let activeDescriptorID = service.activeDescriptor(for: kind)?.id
        return service.enabledModels(kind: kind).compactMap { descriptor in
            if service.isVisibleModel(descriptor) {
                return DisplayedModel(descriptor: descriptor, visibility: .standard)
            }
            if descriptor.id == activeDescriptorID {
                return DisplayedModel(descriptor: descriptor, visibility: .filteredActive)
            }
            return nil
        }
    }

    static func filterNotice(
        for kind: ModelKind,
        service: ActiveModelService
    ) -> String? {
        let hiddenWhisperModels = service.enabledModels(kind: kind).filter { descriptor in
            descriptor.engine.isWhisperFamily && !service.isVisibleModel(descriptor)
        }
        guard hiddenWhisperModels.isEmpty == false else {
            return nil
        }
        return "Some Whisper models are hidden by Whisper Adapter in Settings > Advanced."
    }

    private func descriptionForSection(kind: ModelKind) -> String {
        switch kind {
        case .asr:
            return "Voice-to-text models. Active mark follows Modes tab selection."
        case .streamingASR, .vad, .diarization, .tts:
            return ""
        }
    }

    private func activate(_ descriptor: ModelDescriptor, forKind kind: ModelKind) {
        service.setActive(descriptor, forKind: kind)
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
        // Tapping anywhere on the card (outside the trailing buttons)
        // opens the info popover — mirrors the Superwhisper row-click
        // pattern. The ⓘ button remains as a discoverable affordance.
        .contentShape(Rectangle())
        .onTapGesture {
            isInfoPopoverPresented = true
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
            // Hide Delete on the active model — its CoreML weights are
            // memory-mapped, so `removeItem` can fail or leave inodes
            // dangling for the running adapter. The user must switch
            // active first (which triggers Phase 3 eviction), then
            // delete is safe.
            if isActive {
                EmptyView()
            } else {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(descriptor.displayName)")
                .help("Delete \(descriptor.displayName)")
            }
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
            // Fraction is intentionally discarded — FluidAudio's
            // delegate callbacks for `URLSession.download(for:)` are
            // too coarse (~2 emits per file) to drive a smooth bar
            // without a custom delegate. Show a label-only chip
            // until that's revisited.
            return (.warning, "Downloading…")
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
