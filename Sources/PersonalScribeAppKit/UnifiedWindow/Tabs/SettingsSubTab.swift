import Foundation

public enum SettingsSubTab: String, CaseIterable, Identifiable, Sendable {
    case general     = "General"
    case permissions = "Permissions"
    case about       = "About"

    public var id: String { rawValue }
}
