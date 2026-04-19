import AppKit
import SwiftUI
import SeshatCore
import SeshatSession

/// Injectable app shell: Plan 04 defines this struct with a required-parameter init so
/// tests can construct it with fake dependencies. Plan 99 adds a separate `SeshatAppMain`
/// type conforming to `App` with a parameterless init that reads from `AppComposition`.
/// This type intentionally does NOT conform to `SwiftUI.App` — `App`'s `init()` requirement
/// is incompatible with required-parameter init. Test code calls the init directly.
@MainActor
struct SeshatApp {
    @StateObject private var model: MenuBarSceneModel

    init(
        coordinator: SessionCoordinator,
        permissionRequester: any MicrophonePermissionRequesting,
        permissionService: PermissionServiceAdapter? = nil,
        permissionStateProvider: (@MainActor () -> MicrophonePermissionState)? = nil,
        clipboardWriter: @escaping @MainActor (String) -> Void = SeshatApp.defaultClipboardWriter,
        openSettings: @escaping @MainActor () -> Void = SeshatApp.defaultOpenSettings,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui)
    ) {
        let resolvedPermissionService = permissionService
            ?? SeshatAppMain.makeCompatibilityPermissionService(
                permissionRequester: permissionRequester,
                inputMonitoringProbe: IOHIDPermissionProbe(),
                isAccessibilityTrusted: { false }
            )

        _model = StateObject(
            wrappedValue: MenuBarSceneModel(
                coordinator: coordinator,
                permissionRequester: permissionRequester,
                permissionStateProvider: permissionStateProvider ?? {
                    if let permissionRequester = permissionRequester as? AppKitMicrophonePermissionRequester {
                        return permissionRequester.currentState()
                    }
                    return .notYetRequested
                },
                clipboardWriter: clipboardWriter,
                openSettings: openSettings,
                permissionService: resolvedPermissionService,
                logger: logger
            )
        )
    }

    var body: some Scene {
        // Menu bar surface is native NSStatusItem + NSMenu
        // (StatusItemController) — no SwiftUI in the menu bar per
        // MenuBarMenu/IMPORTANT.md. The Settings scene here only
        // satisfies SwiftUI scene non-emptiness.
        Settings {
            EmptyView()
        }
    }
}

private extension SeshatApp {
    static let defaultClipboardWriter: @MainActor (String) -> Void = { text in
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static let defaultOpenSettings: @MainActor () -> Void = {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
