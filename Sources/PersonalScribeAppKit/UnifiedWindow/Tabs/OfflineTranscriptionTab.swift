import AppKit
import PersonalScribeCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct OfflineTranscriptionTab: View {
    @ObservedObject private var viewModel: OfflineTranscriptionTabViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.windowTint) private var windowTint
    @State private var isDropTargeted = false

    init(viewModel: OfflineTranscriptionTabViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        ZStack(alignment: .trailing) {
            SettingsTabContainer {
                SettingsSection(
                    title: "Offline Transcription",
                    description: "Re-transcribe past recordings or import audio files for batch processing."
                ) {
                    settingsCard
                    dropZoneCard(palette: palette)
                    if !viewModel.jobs.isEmpty {
                        queueCard(palette: palette)
                    }
                }
            }
            .background(resolvedBackground(palette: palette))

            if viewModel.isSidePanePresented {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.dismissSidePane()
                    }

                sidePane(palette: palette)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .onExitCommand {
            if viewModel.isSidePanePresented {
                viewModel.dismissSidePane()
            }
        }
        .animation(.easeInOut(duration: 0.18), value: viewModel.isSidePanePresented)
    }
}

private extension OfflineTranscriptionTab {
    var settingsCard: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: SettingsLayout.itemSpacing) {
                HStack(spacing: SettingsLayout.inlineSpacing) {
                    Text("Model")
                        .font(PersonalScribeTheme.Typography.caption.font.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)

                    Picker("Model", selection: $viewModel.selectedModelID) {
                        ForEach(viewModel.availableModels, id: \.id) { descriptor in
                            Text(descriptor.displayName).tag(descriptor.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 320)
                }

                Spacer(minLength: SettingsLayout.itemSpacing)

                Toggle("Detect speakers", isOn: $viewModel.diarizationEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
            }
        }
    }

    func dropZoneCard(palette: PersonalScribeTheme.Palette) -> some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: SettingsLayout.inlineSpacing) {
                    Image(systemName: "arrow.down.doc")
                        .foregroundStyle(.secondary)
                    Text("Drop audio files here or")
                        .font(PersonalScribeTheme.Typography.body.font)
                        .foregroundStyle(.secondary)
                    Button("Browse…") {
                        Task {
                            await viewModel.handlePickedFiles(Self.presentAudioPicker())
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer(minLength: 0)
                }

                Text("Supports .wav .m4a .mp3 .aac · runs when live capture is idle")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(
                    cornerRadius: SettingsLayout.cardCornerRadius,
                    style: .continuous
                )
                .fill(
                    isDropTargeted
                        ? palette.brandChampagne.opacity(0.14)
                        : Color.clear
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: SettingsLayout.cardCornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    isDropTargeted
                        ? palette.brandChampagne.opacity(0.9)
                        : palette.brandChampagne.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )
            )
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
                Self.handleDroppedProviders(providers) { urls in
                    Task {
                        await viewModel.handleFileDrop(urls)
                    }
                }
            }
        }
    }

    func queueCard(palette: PersonalScribeTheme.Palette) -> some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent")
                    .font(PersonalScribeTheme.Typography.caption.font.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                ForEach(Array(viewModel.jobs.enumerated()), id: \.element.id) { index, job in
                    if index > 0 {
                        Divider().opacity(0.4)
                    }
                    queueRow(job: job, palette: palette)
                }
            }
        }
    }

    func queueRow(
        job: OfflineTranscriptionCoordinator.Job,
        palette: PersonalScribeTheme.Palette
    ) -> some View {
        HStack(spacing: SettingsLayout.inlineSpacing) {
            Image(systemName: statusIcon(for: job.status))
                .foregroundStyle(statusIconColor(for: job.status, palette: palette))
                .frame(width: 16)

            Text(job.url.lastPathComponent)
                .font(PersonalScribeTheme.Typography.body.font)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: SettingsLayout.inlineSpacing)

            Text(statusLabel(for: job.status))
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(.secondary)

            if let action = rowAction(for: job) {
                Button(action.title) {
                    Task {
                        await action.handler()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }

    func statusIconColor(
        for status: OfflineTranscriptionCoordinator.JobStatus,
        palette: PersonalScribeTheme.Palette
    ) -> Color {
        switch status {
        case .queued: return .secondary
        case .inFlight: return palette.statusLink
        case .completed: return palette.statusLink
        case .failed: return .orange
        case .cancelled: return .secondary
        }
    }

    func sidePane(palette: PersonalScribeTheme.Palette) -> some View {
        VStack(alignment: .leading, spacing: SettingsLayout.itemSpacing) {
            HStack(spacing: SettingsLayout.inlineSpacing) {
                Text("Transcript")
                    .font(PersonalScribeTheme.Typography.title.font)

                Spacer(minLength: 0)

                Button {
                    viewModel.dismissSidePane()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close transcript")
            }

            Group {
                if viewModel.isLoadingSidePane {
                    HStack(spacing: SettingsLayout.inlineSpacing) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading transcript…")
                            .font(PersonalScribeTheme.Typography.caption.font)
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage = viewModel.sidePaneErrorMessage {
                    Text(errorMessage)
                        .font(PersonalScribeTheme.Typography.body.font)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    ScrollView {
                        Text(viewModel.sidePaneText ?? "")
                            .font(PersonalScribeTheme.Typography.body.font)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(PersonalScribeTheme.Spacing.lg)
        .frame(minWidth: 360, maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    palette.brandChampagne.opacity(SettingsLayout.cardBorderOpacity),
                    lineWidth: SettingsLayout.cardBorderWidth
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: -6, y: 0)
        .padding(PersonalScribeTheme.Spacing.windowPadding)
    }

    func resolvedBackground(palette: PersonalScribeTheme.Palette) -> Color {
        if let windowTint {
            return windowTint.primaryBackground
        }
        return palette.appBackground
    }

    func rowAction(for job: OfflineTranscriptionCoordinator.Job) -> (
        title: String,
        handler: @MainActor () async -> Void
    )? {
        switch job.status {
        case .queued:
            return ("Dequeue", {
                await viewModel.dequeueJob(id: job.id)
            })
        case .inFlight:
            return ("Cancel", {
                await viewModel.cancelJob(id: job.id)
            })
        case .completed:
            return ("View", {
                viewModel.selectedCompletedJobID = job.id
            })
        case .failed, .cancelled:
            return nil
        }
    }

    func statusLabel(for status: OfflineTranscriptionCoordinator.JobStatus) -> String {
        switch status {
        case .queued:
            return "Queued"
        case .inFlight(let progress):
            return "Transcribing \(Int((progress * 100).rounded()))%"
        case .completed:
            return "Completed"
        case .failed(let reason):
            switch reason {
            case .audioMissing:
                return "Missing audio"
            case .modelNotAvailable:
                return "Model unavailable"
            case .conversionFailed:
                return "Conversion failed"
            case .transcriptionFailed:
                return "Transcription failed"
            case .other(let message):
                return message
            }
        case .cancelled:
            return "Cancelled"
        }
    }

    func statusIcon(for status: OfflineTranscriptionCoordinator.JobStatus) -> String {
        switch status {
        case .queued:
            return "clock"
        case .inFlight:
            return "waveform"
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        case .cancelled:
            return "xmark.circle"
        }
    }

    static func presentAudioPicker() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["wav", "m4a", "mp3", "aac"].compactMap {
            UTType(filenameExtension: $0)
        }
        panel.prompt = "Add"
        panel.message = "Choose audio files to transcribe offline."
        panel.directoryURL = try? AppConfig.recordingsDirectory()
        guard panel.runModal() == .OK else {
            return []
        }
        return panel.urls.map(\.standardizedFileURL)
    }

    static func handleDroppedProviders(
        _ providers: [NSItemProvider],
        completion: @escaping @MainActor ([URL]) -> Void
    ) -> Bool {
        let matchingProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard matchingProviders.isEmpty == false else {
            return false
        }

        let group = DispatchGroup()
        let collector = DroppedURLCollector()

        for provider in matchingProviders {
            group.enter()
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, _ in
                defer { group.leave() }

                let resolvedURL: URL?
                switch item {
                case let data as Data:
                    resolvedURL = URL(dataRepresentation: data, relativeTo: nil)
                case let url as URL:
                    resolvedURL = url
                case let string as String:
                    resolvedURL = URL(string: string)
                default:
                    resolvedURL = nil
                }

                guard let resolvedURL else {
                    return
                }
                collector.append(resolvedURL.standardizedFileURL)
            }
        }

        group.notify(queue: .main) {
            completion(collector.urls)
        }
        return true
    }
}

private final class DroppedURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }
}
