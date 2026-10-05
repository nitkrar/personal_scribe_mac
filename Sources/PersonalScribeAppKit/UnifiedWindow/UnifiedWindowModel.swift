import Foundation

public struct SettingsNavigationRequest: Equatable, Sendable {
    public enum Destination: Equatable, Sendable {
        case shortcuts
        case models
        case permissions
    }

    public let id: Int
    public let destination: Destination
}

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
    @Published public private(set) var settingsNavigationRequest: SettingsNavigationRequest?
    private var nextSettingsNavigationRequest = 0

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
        openSettings(.shortcuts)
    }

    func openSettingsModels() {
        openSettings(.models)
    }

    func openSettingsPermissions() {
        openSettings(.permissions)
    }

    private func openSettings(_ destination: SettingsNavigationRequest.Destination) {
        activeTab = .settings
        isShowingSetup = false
        nextSettingsNavigationRequest += 1
        settingsNavigationRequest = SettingsNavigationRequest(
            id: nextSettingsNavigationRequest,
            destination: destination
        )
    }

    public func consumeSettingsNavigationRequest(_ request: SettingsNavigationRequest?) {
        guard settingsNavigationRequest == request else { return }
        settingsNavigationRequest = nil
    }
}
