import AppKit
import SwiftUI
import PersonalScribeCore
import PersonalScribeSession

/// Injectable app shell: Plan 04 defines this struct with a required-parameter init so
/// tests can construct it with fake dependencies. Plan 99 adds a separate `PersonalScribeAppMain`
/// type conforming to `App` with a parameterless init that reads from `AppComposition`.
/// This type intentionally does NOT conform to `SwiftUI.App` — `App`'s `init()` requirement
/// is incompatible with required-parameter init. Test code calls the init directly.
@MainActor
struct PersonalScribeApp {
    @StateObject private var model: MenuBarSceneModel

    init(
        coordinator: SessionCoordinator,
        permissionService: (any PermissionService)? = nil,
        clipboardWriter: @escaping @MainActor (String) -> Void = PersonalScribeApp.defaultClipboardWriter,
        openSettings: @escaping @MainActor () -> Void = PersonalScribeApp.defaultOpenSettings,
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.ui)
    ) {
        let resolvedPermissionService = permissionService ?? AppComposition.makePermissionService()

        _model = StateObject(
            wrappedValue: MenuBarSceneModel(
                coordinator: coordinator,
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

private extension PersonalScribeApp {
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
