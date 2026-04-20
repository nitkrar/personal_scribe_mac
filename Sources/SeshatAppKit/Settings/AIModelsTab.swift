import SwiftUI
import SeshatCore

@MainActor
public struct AIModelsTab: View {
    private let descriptor: ModelDescriptor

    public init(
        descriptor: ModelDescriptor = BuiltInModelCatalog.descriptor(
            for: BuiltInModelCatalog.defaultModelId
        ) ?? BuiltInModelCatalog.parakeetTDT06Bv2
    ) {
        self.descriptor = descriptor
    }

    public var body: some View {
        SettingsTabContainer {
            SettingsSection(
                title: "AI Models",
                description: "Read-only metadata for the currently registered transcription model."
            ) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(descriptor.displayName)
                            .font(SeshatTheme.Typography.body.font.weight(.semibold))

                        Text("Model switching lands in Phase 3.F.")
                            .font(SeshatTheme.Typography.caption.font)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    StatusPill(status: .ready, label: "Current")
                }

                SettingsCard {
                    SettingsMetadataRow(title: "ID", value: descriptor.id, monospaced: true)
                    Divider()
                    SettingsMetadataRow(title: "Display Name", value: descriptor.displayName)
                    Divider()
                    SettingsMetadataRow(title: "Repository", value: descriptor.repository, monospaced: true)
                    Divider()
                    SettingsMetadataRow(title: "Revision", value: descriptor.revision, monospaced: true)
                }
            }
        }
    }
}
