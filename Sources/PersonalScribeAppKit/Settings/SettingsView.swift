import SwiftUI

@MainActor
public struct SettingsView: View {
    enum Tab: Hashable {
        case general
        case aiModels
        case modes
        case shortcuts
        case advanced
    }

    private let defaults: UserDefaults
    private let menuBarVisibilityProvider: @MainActor () -> Bool
    private let menuBarVisibilitySetter: @MainActor (Bool) -> Void

    @State private var selection: Tab = .general

    public init(
        defaults: UserDefaults = .standard,
        menuBarVisibilityProvider: @escaping @MainActor () -> Bool = { true },
        menuBarVisibilitySetter: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.defaults = defaults
        self.menuBarVisibilityProvider = menuBarVisibilityProvider
        self.menuBarVisibilitySetter = menuBarVisibilitySetter
    }

    public var body: some View {
        TabView(selection: $selection) {
            GeneralTab(
                defaults: defaults,
                menuBarVisibilityProvider: menuBarVisibilityProvider,
                menuBarVisibilitySetter: menuBarVisibilitySetter
            )
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            .tag(Tab.general)

            AIModelsTab()
                .tabItem {
                    Label("AI Models", systemImage: "cpu")
                }
                .tag(Tab.aiModels)

            ModesTab()
                .tabItem {
                    Label("Modes", systemImage: "square.stack.3d.up")
                }
                .tag(Tab.modes)

            ShortcutsTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }
                .tag(Tab.shortcuts)

            AdvancedTab()
                .tabItem {
                    Label("Advanced", systemImage: "folder")
                }
                .tag(Tab.advanced)
        }
        .frame(
            minWidth: SettingsLayout.windowWidth,
            minHeight: SettingsLayout.windowHeight
        )
    }
}

enum SettingsLayout {
    static let windowWidth: CGFloat = 760
    static let windowHeight: CGFloat = 520
    static let maxContentWidth: CGFloat = 620
    static let sectionSpacing: CGFloat = 24
    static let itemSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let cardCornerRadius: CGFloat = 10
    static let cardBorderWidth: CGFloat = 0.5
    static let cardBorderOpacity: Double = 0.18
    static let inlineSpacing: CGFloat = 8
}

struct SettingsTabContainer<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                content
            }
            .frame(maxWidth: SettingsLayout.maxContentWidth, alignment: .leading)
            .padding(PersonalScribeTheme.Spacing.windowPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.appBackground)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let description: String?

    private let content: Content

    init(
        title: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.itemSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(PersonalScribeTheme.Typography.display.font)

                if let description, !description.isEmpty {
                    Text(description)
                        .font(PersonalScribeTheme.Typography.body.font)
                        .foregroundStyle(.secondary)
                }
            }

            content
        }
    }
}

struct SettingsCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        VStack(alignment: .leading, spacing: SettingsLayout.itemSpacing) {
            content
        }
        .padding(SettingsLayout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(
                cornerRadius: SettingsLayout.cardCornerRadius,
                style: .continuous
            )
            .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: SettingsLayout.cardCornerRadius,
                style: .continuous
            )
            .strokeBorder(
                palette.brandChampagne.opacity(SettingsLayout.cardBorderOpacity),
                lineWidth: SettingsLayout.cardBorderWidth
            )
        )
    }
}

struct SettingsMetadataRow: View {
    let title: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(PersonalScribeTheme.Typography.caption.font.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(
                    monospaced
                        ? .system(size: PersonalScribeTheme.Typography.body.pointSize, design: .monospaced)
                        : PersonalScribeTheme.Typography.body.font
                )
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
