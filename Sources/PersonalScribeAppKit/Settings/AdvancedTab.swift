import AppKit
import SwiftUI
import PersonalScribeCore

@MainActor
public struct AdvancedTab: View {
    @StateObject private var viewModel: AdvancedTabViewModel

    public init(
        baseDirectoryResult: Result<URL, Error> = Result { try AppConfig.baseDirectory() },
        defaults: UserDefaults = .standard,
        migrator: any BaseDirectoryMigrating = BaseDirectoryMigrator(
            logger: AppComposition.makeLogger(PersonalScribeLogCategory.app)
        ),
        selectDirectory: @escaping @MainActor (URL?) -> URL? = Self.presentDirectoryPicker,
        openInFinder: @escaping @MainActor (URL) -> Void = { url in
            // Bug #006: previously used `activateFileViewerSelecting([url])`,
            // which opens the PARENT folder with `url` highlighted — so
            // clicking "Open in Finder" surfaced `~/Library/Application
            // Support/` with `personal_scribe` selected, not the contents
            // of `personal_scribe/`. `NSWorkspace.shared.open(_:)` on a
            // directory URL opens that directory's contents.
            NSWorkspace.shared.open(url)
        }
    ) {
        _viewModel = StateObject(
            wrappedValue: AdvancedTabViewModel(
                baseDirectoryResult: baseDirectoryResult,
                defaults: defaults,
                migrator: migrator,
                selectDirectory: selectDirectory,
                openInFinder: openInFinder
            )
        )
    }

    public var body: some View {
        SettingsTabContainer {
            SettingsSection(
                title: "Advanced",
                description: "Filesystem location and local diagnostics controls."
            ) {
                switch viewModel.baseDirectoryResult {
                case .success(let baseDirectory):
                    SettingsCard {
                        baseDirectoryRow(baseDirectory: baseDirectory)

                        if viewModel.isMigrating || viewModel.feedback != nil {
                            Divider()
                            migrationStatusView
                        }
                    }
                    diagnosticsCard
                case .failure(let error):
                    SettingsCard {
                        Text("Failed to resolve the base directory.")
                            .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))
                        Text(error.localizedDescription)
                            .font(PersonalScribeTheme.Typography.caption.font)
                            .foregroundStyle(.secondary)
                    }
                    diagnosticsCard
                }
            }
        }
    }

    private var diagnosticsCard: some View {
        SettingsCard {
            Text("Diagnostics")
                .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))

            Picker(
                "Diagnostic logging",
                selection: Binding(
                    get: { viewModel.diagnosticLoggingMode },
                    set: { viewModel.setDiagnosticLoggingMode($0) }
                )
            ) {
                Text("Errors Only").tag(DiagnosticLoggingMode.errorsOnly)
                Text("Verbose").tag(DiagnosticLoggingMode.verbose)
            }
            .pickerStyle(.segmented)

            Text(viewModel.diagnosticLoggingModeDescription)
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: SettingsLayout.inlineSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Log retention")
                        .font(PersonalScribeTheme.Typography.body.font.weight(.medium))

                    Spacer()

                    Text(viewModel.logRetentionDescription)
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(.secondary)
                }

                Stepper(
                    "Keep daily archives",
                    value: Binding(
                        get: { viewModel.logRetentionDays },
                        set: { viewModel.setLogRetentionDays($0) }
                    ),
                    in: LogRetentionDaysPreference.minimum...LogRetentionDaysPreference.maximum
                )

                Text(viewModel.logRetentionSummary)
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Toggle(
                "Show live diagnostics overlay",
                isOn: Binding(
                    get: { viewModel.showLiveDiagnosticsOverlay },
                    set: { viewModel.setShowLiveDiagnosticsOverlay($0) }
                )
            )
            .disabled(viewModel.isLiveDiagnosticsOverlayToggleDisabled)

            if viewModel.isLiveDiagnosticsOverlayToggleDisabled {
                Text("Set Diagnostic logging to Verbose to enable the overlay.")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Single-line compact row: `Base directory` label, middle-truncated
    /// path, and two icon-only buttons (Reveal in Finder, Change). The
    /// previous two-block layout (metadata row + right-aligned button
    /// stack) pushed onto two lines at the default Settings width — see
    /// bug #006.
    @ViewBuilder
    private func baseDirectoryRow(baseDirectory: URL) -> some View {
        HStack(spacing: SettingsLayout.inlineSpacing) {
            Text("Base directory")
                .font(PersonalScribeTheme.Typography.caption.font.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)

            Text(baseDirectory.path)
                .font(
                    .system(
                        size: PersonalScribeTheme.Typography.caption.pointSize,
                        design: .monospaced
                    )
                )
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            IconButton(
                systemImage: "magnifyingglass",
                help: "Open in Finder",
                isEnabled: !viewModel.isMigrating
            ) {
                viewModel.revealInFinder()
            }

            IconButton(
                systemImage: "folder",
                help: "Change base directory…",
                isEnabled: !viewModel.isMigrating
            ) {
                Task {
                    await viewModel.changeBaseDirectory()
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
    @Published private(set) var diagnosticLoggingMode: DiagnosticLoggingMode
    @Published private(set) var logRetentionDays: Int
    @Published private(set) var showLiveDiagnosticsOverlay: Bool

    private let defaults: UserDefaults
    private let migrator: any BaseDirectoryMigrating
    private let selectDirectory: @MainActor (URL?) -> URL?
    private let openInFinder: @MainActor (URL) -> Void

    init(
        baseDirectoryResult: Result<URL, Error> = Result { try AppConfig.baseDirectory() },
        defaults: UserDefaults = .standard,
        migrator: any BaseDirectoryMigrating = BaseDirectoryMigrator(
            logger: AppComposition.makeLogger(PersonalScribeLogCategory.app)
        ),
        selectDirectory: @escaping @MainActor (URL?) -> URL?,
        openInFinder: @escaping @MainActor (URL) -> Void = { url in
            NSWorkspace.shared.open(url)
        }
    ) {
        self.baseDirectoryResult = baseDirectoryResult
        self.defaults = defaults
        self.migrator = migrator
        self.selectDirectory = selectDirectory
        self.openInFinder = openInFinder
        let diagnosticLoggingMode = DiagnosticLoggingMode.resolve(from: defaults)
        self.diagnosticLoggingMode = diagnosticLoggingMode
        logRetentionDays = LogRetentionDaysPreference.resolve(from: defaults)
        let storedOverlay = ShowLiveDiagnosticsOverlayPreference.resolve(from: defaults)
        showLiveDiagnosticsOverlay = diagnosticLoggingMode == .verbose && storedOverlay
    }

    var diagnosticLoggingModeDescription: String {
        switch diagnosticLoggingMode {
        case .errorsOnly:
            return "Persist only error diagnostics to disk and the Console."
        case .verbose:
            return "Capture debug, info, notice, and error diagnostics locally."
        }
    }

    var logRetentionDescription: String {
        switch logRetentionDays {
        case 0:
            return "Disabled"
        case 1:
            return "1 day"
        default:
            return "\(logRetentionDays) days"
        }
    }

    var logRetentionSummary: String {
        switch logRetentionDays {
        case 0:
            return "Current logs still rotate daily at local midnight. Archived logs are not pruned automatically."
        case 1:
            return "Current logs rotate daily at local midnight. Keep the most recent 1 day of archived logs."
        default:
            return "Current logs rotate daily at local midnight. Keep the most recent \(logRetentionDays) days of archived logs."
        }
    }

    var isLiveDiagnosticsOverlayToggleDisabled: Bool {
        diagnosticLoggingMode != .verbose
    }

    func setLogRetentionDays(_ days: Int) {
        let sanitized = LogRetentionDaysPreference.sanitized(days)
        logRetentionDays = sanitized
        LogRetentionDaysPreference.persist(sanitized, to: defaults)
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

    /// Invokes the injected Finder opener with the currently resolved
    /// base directory. Routed through the VM (rather than called from
    /// the view) so tests can assert the URL matches the resolved base
    /// directory, not its parent — see bug #006.
    func revealInFinder() {
        guard let currentBaseDirectory else { return }
        openInFinder(currentBaseDirectory)
    }

    func setDiagnosticLoggingMode(_ mode: DiagnosticLoggingMode) {
        diagnosticLoggingMode = mode
        mode.persist(to: defaults)

        if mode != .verbose {
            showLiveDiagnosticsOverlay = false
            ShowLiveDiagnosticsOverlayPreference.persist(false, to: defaults)
        }
    }

    func setShowLiveDiagnosticsOverlay(_ isEnabled: Bool) {
        guard diagnosticLoggingMode == .verbose else {
            showLiveDiagnosticsOverlay = false
            ShowLiveDiagnosticsOverlayPreference.persist(false, to: defaults)
            return
        }

        showLiveDiagnosticsOverlay = isEnabled
        ShowLiveDiagnosticsOverlayPreference.persist(isEnabled, to: defaults)
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

/// Compact icon-only button used by the `Advanced` base-directory row
/// so it fits on one line alongside a truncating path label. The
/// hover `.help(_:)` tooltip carries the textual label for
/// accessibility + discoverability — see bug #006. Kept file-local
/// because no other call site currently needs this shape; promote to
/// `Sources/PersonalScribeAppKit/Components/` if a second consumer
/// appears.
private struct IconButton: View {
    let systemImage: String
    let help: String
    var isEnabled: Bool = true
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.primaryText)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(
                        cornerRadius: PersonalScribeTheme.Radius.row,
                        style: .continuous
                    )
                    .fill(palette.elevatedSurface)
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: PersonalScribeTheme.Radius.row,
                        style: .continuous
                    )
                    .strokeBorder(
                        palette.brandChampagne.opacity(
                            PersonalScribeTheme.Components.ActionButton.secondaryBorderOpacity
                        ),
                        lineWidth: PersonalScribeTheme.Components.ActionButton.borderWidth
                    )
                )
                .opacity(
                    isEnabled
                        ? 1.0
                        : PersonalScribeTheme.Components.ActionButton.disabledOpacity
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
    }
}
