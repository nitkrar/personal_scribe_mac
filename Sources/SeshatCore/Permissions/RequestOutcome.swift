public struct RequestOutcome: Equatable, Sendable {
    public let prompted: Bool
    public let openedSettings: Bool
    public let requiresRelaunch: Bool
    public let finalStatus: PermissionStatus

    public init(
        prompted: Bool,
        openedSettings: Bool,
        requiresRelaunch: Bool,
        finalStatus: PermissionStatus
    ) {
        self.prompted = prompted
        self.openedSettings = openedSettings
        self.requiresRelaunch = requiresRelaunch
        self.finalStatus = finalStatus
    }
}
