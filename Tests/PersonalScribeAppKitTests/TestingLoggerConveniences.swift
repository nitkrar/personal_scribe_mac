import AppKit
import Foundation
import PersonalScribeCore
@testable import PersonalScribeAppKit
@testable import PersonalScribeSession

@MainActor
private enum AppKitTestingDiagnostics {
    static func logger(_ category: String = PersonalScribeLogCategory.ui) -> PersonalScribeLogger {
        PersonalScribeLogger.testing(category: category)
    }
}

@MainActor
extension HotkeyEventTap {
    convenience init(
        decider: @escaping Decider,
        installer: @escaping Installer = { callback, userInfo in
            CGHotkeyEventTapInstaller.createTap(callback: callback, userInfo: userInfo)
        }
    ) {
        self.init(
            decider: decider,
            installer: installer,
            logger: AppKitTestingDiagnostics.logger()
        )
    }
}

@MainActor
extension KeyEventRouter {
    convenience init(
        tapFactory: @escaping TapFactory = { decider in
            HotkeyEventTap(decider: decider)
        },
        installLocal: @escaping LocalInstaller = { mask, handler in
            NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
        },
        installGlobal: @escaping GlobalInstaller = { mask, handler in
            NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
        },
        uninstall: @escaping Uninstaller = { handle in
            NSEvent.removeMonitor(handle)
        }
    ) {
        self.init(
            tapFactory: tapFactory,
            installLocal: installLocal,
            installGlobal: installGlobal,
            uninstall: uninstall,
            logger: AppKitTestingDiagnostics.logger()
        )
    }
}

@MainActor
extension GlobalHotkeyMonitor {
    convenience init(
        onToggle: @escaping @MainActor () -> Void,
        onHoldStart: @escaping @MainActor () -> Void = {},
        onHoldRelease: @escaping @MainActor () -> Void = {},
        recordingHotkey: HotkeyPreference = HotkeyPreference.resolve(),
        holdThreshold: TimeInterval = GlobalHotkeyMonitor.holdThreshold,
        doubleTapWindow: TimeInterval = GlobalHotkeyMonitor.doubleTapWindow,
        scheduleHoldDetection: @escaping HoldScheduler = { delay, action in
            let workItem = DispatchWorkItem {
                Task { @MainActor in
                    action()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            return {
                workItem.cancel()
            }
        },
        permissionService: (any PermissionService)? = nil,
        router: KeyEventRouter? = nil,
        logSink: (@Sendable (_ level: String, _ message: String) -> Void)? = nil
    ) {
        self.init(
            onToggle: onToggle,
            onHoldStart: onHoldStart,
            onHoldRelease: onHoldRelease,
            recordingHotkey: recordingHotkey,
            holdThreshold: holdThreshold,
            doubleTapWindow: doubleTapWindow,
            scheduleHoldDetection: scheduleHoldDetection,
            permissionService: permissionService,
            router: router,
            logger: AppKitTestingDiagnostics.logger(),
            logSink: logSink
        )
    }
}

@MainActor
extension AppStartupCoordinator {
    convenience init(
        hotkeyDelay: Duration = .milliseconds(250),
        prepareDelay: Duration = .seconds(1),
        startHotkeyMonitor: @escaping HotkeyStarter,
        prepareTranscriber: @escaping @Sendable () async -> Void,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.init(
            hotkeyDelay: hotkeyDelay,
            prepareDelay: prepareDelay,
            startHotkeyMonitor: startHotkeyMonitor,
            prepareTranscriber: prepareTranscriber,
            sleep: sleep,
            logger: AppKitTestingDiagnostics.logger(PersonalScribeLogCategory.app)
        )
    }
}

@MainActor
extension PersonalScribeApp {
    init(
        coordinator: SessionCoordinator,
        permissionService: (any PermissionService)? = nil,
        clipboardWriter: @escaping @MainActor (String) -> Void = { _ in },
        openSettings: @escaping @MainActor () -> Void = {}
    ) {
        self.init(
            coordinator: coordinator,
            permissionService: permissionService,
            clipboardWriter: clipboardWriter,
            openSettings: openSettings,
            logger: AppKitTestingDiagnostics.logger()
        )
    }
}

extension ActiveModelService {
    convenience init(
        activeIDsPreference: Preference<[ModelKind: String]>,
        whisperAdapterFilterPreference: Preference<WhisperAdapterFilter>? = nil,
        registeredModels: [ModelDescriptor] = BuiltInModelCatalog.registeredModels,
        isDownloaded: @escaping @Sendable (ModelDescriptor) -> Bool,
        download: @escaping @Sendable (
            ModelDescriptor,
            @escaping @Sendable (ModelDownloadProgress) -> Void
        ) async throws -> Void,
        removeDownloaded: @escaping @Sendable (ModelDescriptor) throws -> Void = { _ in },
        evict: @escaping @Sendable (ModelDescriptor) -> Void = { _ in },
        modelsDirectoryProvider: @escaping @Sendable () -> URL? = { nil },
        diskSpaceProvider: @escaping @Sendable (URL) -> Int64? = { _ in nil }
    ) {
        self.init(
            activeIDsPreference: activeIDsPreference,
            whisperAdapterFilterPreference: whisperAdapterFilterPreference,
            registeredModels: registeredModels,
            isDownloaded: isDownloaded,
            download: download,
            removeDownloaded: removeDownloaded,
            evict: evict,
            modelsDirectoryProvider: modelsDirectoryProvider,
            diskSpaceProvider: diskSpaceProvider,
            logger: AppKitTestingDiagnostics.logger(PersonalScribeLogCategory.session)
        )
    }
}

@MainActor
extension PillOverlayPresenter {
    convenience init(
        model: PillOverlayViewModel,
        onTap: @escaping @MainActor () -> Void = {},
        panelBuilder: any PillOverlayPanelBuilding,
        responseCardBuilder: any ResponseCardBuilding = LiveResponseCardBuilder()
    ) {
        self.init(
            model: model,
            onTap: onTap,
            panelBuilder: panelBuilder,
            responseCardBuilder: responseCardBuilder,
            diagnosticLogger: AppKitTestingDiagnostics.logger()
        )
    }
}
