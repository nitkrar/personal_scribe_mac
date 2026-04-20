import AppKit
import SwiftUI
import PersonalScribeCore

@MainActor
public struct AdvancedTab: View {
    @StateObject private var viewModel: AdvancedTabViewModel
    private let openInFinder: @MainActor (URL) -> Void

    public init(
        baseDirectoryResult: Result<URL, Error> = Result { try AppConfig.baseDirectory() },
        migrator: any BaseDirectoryMigrating = BaseDirectoryMigrator(),
        selectDirectory: @escaping @MainActor (URL?) -> URL? = Self.presentDirectoryPicker,
        openInFinder: @escaping @MainActor (URL) -> Void = {
            NSWorkspace.shared.activateFileViewerSelecting([$0])
        }
    ) {
        _viewModel = StateObject(
            wrappedValue: AdvancedTabViewModel(
                baseDirectoryResult: baseDirectoryResult,
                migrator: migrator,
                selectDirectory: selectDirectory
            )
        )
        self.openInFinder = openInFinder
    }

    public var body: some View {
        SettingsTabContainer {
            SettingsSection(
                title: "Advanced",
                description: "Filesystem location for \(AppBrand.displayName)'s app support data."
            ) {
                switch viewModel.baseDirectoryResult {
                case .success(let baseDirectory):
                    SettingsCard {
                        SettingsMetadataRow(
                            title: "Base directory",
                            value: baseDirectory.path
                        )

                        if viewModel.isMigrating || viewModel.feedback != nil {
                            Divider()
                            migrationStatusView
                        }

                        HStack(spacing: SettingsLayout.inlineSpacing) {
                            Spacer()
                            ActionButton(
                                title: "Open in Finder",
                                variant: .secondary,
                                isEnabled: !viewModel.isMigrating
                            ) {
                                openInFinder(baseDirectory)
                            }
                            ActionButton(title: "Change Base Directory…", isEnabled: !viewModel.isMigrating) {
                                Task {
                                    await viewModel.changeBaseDirectory()
                                }
                            }
                        }
                    }
                case .failure(let error):
                    SettingsCard {
                        Text("Failed to resolve the base directory.")
                            .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))
                        Text(error.localizedDescription)
                            .font(PersonalScribeTheme.Typography.caption.font)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var migrationStatusView: some View {
        if viewModel.isMigrating {
            HStack(spacing: SettingsLayout.inlineSpacing) {
                ProgressView()
                    .controlSize(.small)

                Text("Migrating models, modes, and recordings…")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(.secondary)
            }
        } else if let feedback = viewModel.feedback {
            Label(feedback.message, systemImage: feedback.systemImage)
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(.secondary)
        }
    }

    public static func presentDirectoryPicker(currentBaseDirectory: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Select a new base directory for \(AppBrand.displayName)'s models, modes, and recordings."
        panel.directoryURL = currentBaseDirectory
        return panel.runModal() == .OK ? panel.url?.standardizedFileURL : nil
    }
}

@MainActor
final class AdvancedTabViewModel: ObservableObject {
    enum Feedback: Equatable {
        case success(String)
        case failure(String)

        var message: String {
            switch self {
            case .success(let message), .failure(let message):
                message
            }
        }

        var systemImage: String {
            switch self {
            case .success:
                "checkmark.circle.fill"
            case .failure:
                "exclamationmark.triangle.fill"
            }
        }
    }

    @Published private(set) var baseDirectoryResult: Result<URL, Error>
    @Published private(set) var isMigrating = false
    @Published private(set) var feedback: Feedback?

    private let migrator: any BaseDirectoryMigrating
    private let selectDirectory: @MainActor (URL?) -> URL?

    init(
        baseDirectoryResult: Result<URL, Error> = Result { try AppConfig.baseDirectory() },
        migrator: any BaseDirectoryMigrating = BaseDirectoryMigrator(),
        selectDirectory: @escaping @MainActor (URL?) -> URL?
    ) {
        self.baseDirectoryResult = baseDirectoryResult
        self.migrator = migrator
        self.selectDirectory = selectDirectory
    }

    func changeBaseDirectory() async {
        guard !isMigrating else { return }
        guard let selectedDirectory = selectDirectory(currentBaseDirectory) else { return }

        isMigrating = true
        feedback = nil
        defer { isMigrating = false }

        do {
            let report = try await migrator.migrate(to: selectedDirectory)
            baseDirectoryResult = .success(selectedDirectory.standardizedFileURL)
            feedback = .success(Self.message(for: report))
        } catch {
            feedback = .failure(error.localizedDescription)
        }
    }

    private var currentBaseDirectory: URL? {
        switch baseDirectoryResult {
        case .success(let directory):
            directory
        case .failure:
            nil
        }
    }

    private static func message(for report: MigrationReport) -> String {
        switch report {
        case .noOp:
            return "Base directory already points to the selected folder."
        case .migrated(let movedSubdirs, let totalBytes):
            guard movedSubdirs.isEmpty == false else {
                return "Base directory changed. No existing models, modes, or recordings needed moving."
            }

            let formattedDirectories = ListFormatter.localizedString(byJoining: movedSubdirs)
            let formattedBytes = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            return "Moved \(formattedDirectories) (\(formattedBytes))."
        }
    }
}
