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

    public init(initialTab: AppTab = .home) {
        self.activeTab = initialTab
    }

    public func setActiveTab(_ tab: AppTab) {
        activeTab = tab
    }
}
