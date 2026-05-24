import AppKit
import PersonalScribeCore
import PersonalScribeSession
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct OfflineTranscriptionTab: View {
    @ObservedObject private var viewModel: OfflineTranscriptionTabViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var isDropTargeted = false

    init(viewModel: OfflineTranscriptionTabViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            mainContent

            if viewModel.hasSelectedCompletedJob {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.closeSelectedCompletedJob()
                    }

                completedTranscriptPane
                    .padding(PersonalScribeTheme.Spacing.windowPadding)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: viewModel.hasSelectedCompletedJob)
        .onExitCommand {
            if viewModel.hasSelectedCompletedJob {
                viewModel.closeSelectedCompletedJob()
            }
        }
    }

    private var mainContent: some View {
        SettingsTabContainer {
            SettingsSection(
                title: "Offline",
                description: "Transcribe saved audio files without starting a live capture session."
            ) {
                controlsCard
                dropZoneCard

                if !viewModel.jobs.isEmpty {
                    queueCard
                }
            }
        }
    }

    private var controlsCard: some View {
        SettingsCard(padding: SettingsLayout.compactCardPadding) {
            HStack(alignment: .top, spacing: SettingsLayout.itemSpacing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ASR model")
                        .font(PersonalScribeTheme.Typography.caption.font.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker(
                        "ASR model",
                        selection: Binding(
                            get: { viewModel.selectedDescriptorID },
                            set: { viewModel.setSelectedDescriptorID($0) }
                        )
                    ) {
                        ForEach(viewModel.availableDescriptors, id: \.id) { descriptor in
                            Text(descriptor.displayName).tag(descriptor.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 260, alignment: .leading)
                }

                Spacer(minLength: PersonalScribeTheme.Spacing.lg)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Speaker detection")
                        .font(PersonalScribeTheme.Typography.caption.font.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Toggle(
                        "Enable speaker identification",
                        isOn: Binding(
                            get: { viewModel.diarizationEnabled },
                            set: { viewModel.setDiarizationEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)
                }
            }
        }
    }

    private var dropZoneCard: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        return SettingsCard {
            VStack(alignment: .leading, spacing: SettingsLayout.itemSpacing) {
                Text("Files")
                    .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))

                Text("Drop `.wav`, `.m4a`, `.mp3`, or `.aac` files here, or browse from the recordings directory.")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous)
                    .fill(isDropTargeted ? palette.hoverState : palette.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous)
                            .strokeBorder(
                                palette.brandChampagne.opacity(isDropTargeted ? 0.48 : 0.22),
                                style: StrokeStyle(lineWidth: 1, dash: [8, 6])
                            )
                    }
                    .frame(minHeight: 112)
                    .overlay {
                        VStack(spacing: PersonalScribeTheme.Spacing.sm) {
                            Image(systemName: "arrow.up.doc")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(palette.primaryText.opacity(0.75))

                            Text("Drop audio files to queue them")
                                .font(PersonalScribeTheme.Typography.body.font.weight(.medium))

                            Text("Files stay in place. New transcripts are written into History.")
                                .font(PersonalScribeTheme.Typography.caption.font)
                                .foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)
                        .padding(PersonalScribeTheme.Spacing.lg)
                    }
                    .dropDestination(for: URL.self) { urls, _ in
                        Task {
                            await viewModel.handleFileDrop(urls)
                        }
                        return true
                    } isTargeted: { isTargeted in
                        self.isDropTargeted = isTargeted
                    }

                HStack {
                    Spacer()
                    Button("Browse…") {
                        let urls = Self.presentAudioPicker()
                        guard !urls.isEmpty else {
                            return
                        }

                        Task {
                            await viewModel.handlePickedFiles(urls)
                        }
                    }
                }
            }
        }
    }

    private var queueCard: some View {
        SettingsCard(padding: SettingsLayout.compactCardPadding) {
            VStack(alignment: .leading, spacing: SettingsLayout.itemSpacing) {
                Text("Queue")
                    .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))

                List(viewModel.jobs, id: \.id) { job in
                    HStack(spacing: SettingsLayout.itemSpacing) {
                        Label(job.url.lastPathComponent, systemImage: statusIcon(for: job.status))
                            .font(PersonalScribeTheme.Typography.body.font)
                            .lineLimit(1)

                        Spacer(minLength: 0)

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
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
                .frame(minHeight: 150, maxHeight: 220)
            }
        }
    }

    private var completedTranscriptPane: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        return VStack(alignment: .leading, spacing: SettingsLayout.itemSpacing) {
            HStack(alignment: .top, spacing: SettingsLayout.inlineSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.selectedCompletedJob?.url.lastPathComponent ?? "Transcript")
                        .font(PersonalScribeTheme.Typography.title.font)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("Read-only result")
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button {
                    viewModel.closeSelectedCompletedJob()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close transcript")
            }

            Divider()

            Group {
                if let text = viewModel.selectedTranscriptText {
                    ScrollView {
                        Text(text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                } else if let errorMessage = viewModel.selectedTranscriptErrorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .font(PersonalScribeTheme.Typography.body.font)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(SettingsLayout.cardPadding)
        .frame(width: 380)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    palette.brandChampagne.opacity(SettingsLayout.cardBorderOpacity),
                    lineWidth: SettingsLayout.cardBorderWidth
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 16, y: 6)
    }

    private func statusLabel(for status: OfflineTranscriptionCoordinator.JobStatus) -> String {
        switch status {
        case .queued:
            "Queued"
        case .inFlight(let progress):
            "Transcribing \(Int((progress * 100).rounded()))%"
        case .completed:
            "Completed"
        case .failed(let reason):
            switch reason {
            case .audioMissing:
                "Audio file missing"
            case .modelNotAvailable:
                "Model unavailable"
            case .conversionFailed:
                "Audio conversion failed"
            case .transcriptionFailed:
                "Transcription failed"
            case .other(let message):
                message.isEmpty ? "Failed" : message
            }
        case .cancelled:
            "Cancelled"
        }
    }

    private func statusIcon(for status: OfflineTranscriptionCoordinator.JobStatus) -> String {
        switch status {
        case .queued:
            "clock"
        case .inFlight:
            "waveform"
        case .completed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        case .cancelled:
            "xmark.circle"
        }
    }

    private func rowAction(
        for job: OfflineTranscriptionCoordinator.Job
    ) -> (title: String, handler: @MainActor () async -> Void)? {
        switch job.status {
        case .queued:
            ("Dequeue", {
                await viewModel.dequeueJob(id: job.id)
            })
        case .inFlight:
            ("Cancel", {
                await viewModel.cancelJob(id: job.id)
            })
        case .completed:
            ("View", {
                await viewModel.selectCompletedJob(id: job.id)
            })
        case .failed, .cancelled:
            nil
        }
    }

    static func presentAudioPicker() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.wav, .mpeg4Audio, .mp3, .audio]
        panel.directoryURL = try? AppConfig.recordingsDirectory()

        guard panel.runModal() == .OK else {
            return []
        }

        return panel.urls
    }
}
