import Foundation

public enum SettingsSubTab: String, CaseIterable, Identifiable, Sendable {
    case general     = "General"
    case aiModels    = "AI Models"
    case advanced    = "Advanced"
    case permissions = "Permissions"

    public var id: String { rawValue }
}
