import AppKit
import SwiftUI
import SeshatCore

@MainActor
public struct AdvancedTab: View {
    private let baseDirectoryResult: Result<URL, Error>
    private let openInFinder: @MainActor (URL) -> Void

    public init(
        baseDirectoryResult: Result<URL, Error> = Result { try SeshatConfig.baseDirectory() },
        openInFinder: @escaping @MainActor (URL) -> Void = {
            NSWorkspace.shared.activateFileViewerSelecting([$0])
        }
    ) {
        self.baseDirectoryResult = baseDirectoryResult
        self.openInFinder = openInFinder
    }

    public var body: some View {
        SettingsTabContainer {
            SettingsSection(
                title: "Advanced",
                description: "Filesystem location for Seshat's app support data."
            ) {
                switch baseDirectoryResult {
                case .success(let baseDirectory):
                    SettingsCard {
                        SettingsMetadataRow(
                            title: "Base directory",
                            value: baseDirectory.path
                        )

                        HStack {
                            Spacer()
                            ActionButton(title: "Open in Finder") {
                                openInFinder(baseDirectory)
                            }
                        }
                    }
                case .failure(let error):
                    SettingsCard {
                        Text("Failed to resolve the base directory.")
                            .font(SeshatTheme.Typography.body.font.weight(.semibold))
                        Text(error.localizedDescription)
                            .font(SeshatTheme.Typography.caption.font)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
