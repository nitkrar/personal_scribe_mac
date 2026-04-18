import Foundation
#if canImport(IOKit)
import IOKit.hid
#endif

public enum InputMonitoringPermissionState: Sendable, Equatable {
    case notDetermined
    case granted
    case denied
}

public protocol PermissionProbing: Sendable {
    func checkInputMonitoring() -> InputMonitoringPermissionState
}

/// Queries Input Monitoring TCC status via `IOHIDCheckAccess`.
///
/// `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` is the correct bucket for
/// Input Monitoring. `CGPreflightListenEventAccess` reports the Accessibility
/// bucket and silently mis-reports when AX is granted but IM is denied.
///
/// Note: the system returns `.unknown` (mapped to `.notDetermined`) until the
/// process has attempted to install an event tap or global monitor at least
/// once. Callers that want an accurate verdict should probe only AFTER an
/// `NSEvent.addGlobalMonitorForEvents` attempt has been made.
public struct IOHIDPermissionProbe: PermissionProbing {
    public init() {}

    public func checkInputMonitoring() -> InputMonitoringPermissionState {
#if canImport(IOKit)
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        switch access {
        case kIOHIDAccessTypeGranted:
            return .granted
        case kIOHIDAccessTypeDenied:
            return .denied
        default:
            return .notDetermined
        }
#else
        return .notDetermined
#endif
    }
}
