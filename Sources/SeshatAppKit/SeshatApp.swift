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
        permissionStateProvider: (@MainActor () -> MicrophonePermissionState)? = nil,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui)
    ) {
        let initialPermissionState: MicrophonePermissionState
        if let permissionStateProvider {
            initialPermissionState = permissionStateProvider()
        } else if let permissionRequester = permissionRequester as? AppKitMicrophonePermissionRequester {
            initialPermissionState = permissionRequester.currentState()
        } else {
            initialPermissionState = .notYetRequested
        }

        _model = StateObject(
            wrappedValue: MenuBarSceneModel(
                coordinator: coordinator,
                permissionRequester: permissionRequester,
                permissionStateProvider: { initialPermissionState },
                clipboardWriter: { text in
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                },
                openSettings: {
                    guard let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                    ) else {
                        return
                    }

                    NSWorkspace.shared.open(url)
                },
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
