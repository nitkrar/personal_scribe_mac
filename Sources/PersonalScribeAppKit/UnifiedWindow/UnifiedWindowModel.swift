import Foundation

/// Observable routing state for the unified NavigationSplitView window.
///
/// Single source of truth for which `AppTab` is active. Tab switches
/// go through `setActiveTab(_:)` so SwiftUI observers can bind and
/// the model stays trivially testable without hosting the view.
///
/// Deliberately thin — no side effects, no persistence. Content-area
/// view models (Transcriptions, Modes, Home) own their own state.
@MainActor
public final class UnifiedWindowModel: ObservableObject {
    @Published public private(set) var activeTab: AppTab
    @Published private(set) var isShowingSetup = false
    @Published public private(set) var settingsShortcutsRequest: Int?
    @Published private(set) var settingsModelsRequest: Int?
    @Published private(set) var settingsPermissionsRequest: Int?
    private var nextSettingsShortcutsRequest = 0
    private var nextSettingsModelsRequest = 0
    private var nextSettingsPermissionsRequest = 0

    public init(initialTab: AppTab = .home) {
        self.activeTab = initialTab
    }

    public func setActiveTab(_ tab: AppTab) {
        activeTab = tab
        isShowingSetup = false
    }

    func showSetup() {
        isShowingSetup = true
    }

    public func openSettingsShortcuts() {
        activeTab = .settings
        isShowingSetup = false
        nextSettingsShortcutsRequest += 1
        settingsShortcutsRequest = nextSettingsShortcutsRequest
    }

    func openSettingsModels() {
        activeTab = .settings
        isShowingSetup = false
        nextSettingsModelsRequest += 1
        settingsModelsRequest = nextSettingsModelsRequest
    }

    func openSettingsPermissions() {
        activeTab = .settings
        isShowingSetup = false
        nextSettingsPermissionsRequest += 1
        settingsPermissionsRequest = nextSettingsPermissionsRequest
    }

    public func consumeSettingsShortcutsRequest(_ request: Int?) {
        guard settingsShortcutsRequest == request else {
            return
        }
        settingsShortcutsRequest = nil
    }

    func consumeSettingsModelsRequest(_ request: Int?) {
        guard settingsModelsRequest == request else { return }
        settingsModelsRequest = nil
    }

    func consumeSettingsPermissionsRequest(_ request: Int?) {
        guard settingsPermissionsRequest == request else { return }
        settingsPermissionsRequest = nil
    }
}
