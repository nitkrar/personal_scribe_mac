import Foundation
import ServiceManagement

// Protocol seam for SMAppService.mainApp so GeneralTabViewModel can be
// tested with a fake. The default concrete implementation
// `SystemLaunchAtLoginService` wraps `SMAppService.mainApp` — tests
// inject a fake instead of touching the real login-items registry.
//
// See plans/BACKLOG.md #005 for the UX-feedback rationale: register()
// / unregister() errors were previously swallowed with no user feedback;
// the status dot in GeneralTab now reflects `isEnabled` re-read after
// every call so a failed register turns the dot red.
@MainActor
public protocol LaunchAtLoginServicing: Sendable {
    var isEnabled: Bool { get }
    func register() throws
    func unregister() throws
}

@MainActor
public struct SystemLaunchAtLoginService: LaunchAtLoginServicing {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
