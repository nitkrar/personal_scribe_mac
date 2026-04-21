import AppKit
import Foundation
import PersonalScribeAudio
import PersonalScribeCore
import PersonalScribeSession
import PersonalScribeTranscription

@MainActor
public enum AppComposition {
    private static let transcriptDatabaseFileName = "transcripts.sqlite"

    public static let modelService: DefaultModelService = {
        DefaultModelService(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.session)
        )
    }()

    public static let activeModeProvider: AppKitActiveModeProvider = {
        AppKitActiveModeProvider(modelService: modelService)
    }()

    public static let sessionCoordinator: SessionCoordinator = {
        let logger = PersonalScribeLogger(category: PersonalScribeLogCategory.session)
        let capture = AVAudioCaptureService(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.audio),
            inputDeviceProvider: AVFoundationInputDeviceProvider(defaults: .standard)
        )
        let transcriberProvider = ModelBoundTranscriberProvider()

        return SessionCoordinator(
            capture: capture,
            modelService: modelService,
            transcriberProvider: transcriberProvider,
            logger: logger,
            transcriptStore: makeTranscriptStore()
        )
    }()

    /// SQLiteTranscriptStore persists transcripts under
    /// `<base>/recordings/transcripts.sqlite` and migrates any legacy
    /// `transcripts.jsonl` sidecar atomically while leaving the JSONL file in
    /// place as a rollback artifact. Failures are logged and swallowed —
    /// losing history is preferable to blocking the app from starting when
    /// disk is read-only or the path isn't writable.
    private static func makeTranscriptStore() -> SQLiteTranscriptStore? {
        let logger = PersonalScribeLogger(category: PersonalScribeLogCategory.session)
        do {
            let storageLocator = AppConfig.liveStorageLocator()
            return try SQLiteTranscriptStore(storageLocator: storageLocator)
        } catch {
            logger.error("SQLiteTranscriptStore init failed; continuing without persistence", error: error)
            return nil
        }
    }

    public static func makeSessionCoordinator() -> SessionCoordinator {
        sessionCoordinator
    }

    public static func makeMetricsService() throws -> SQLiteMetricsService {
        let databaseURL = AppConfig.liveStorageLocator()
            .url(for: .recordings)
            .appendingPathComponent(transcriptDatabaseFileName, isDirectory: false)
            .standardizedFileURL

        return try SQLiteMetricsService(
            databaseURL: databaseURL,
            calendar: .current,
            referenceDateProvider: Date.init
        )
    }

    /// Read-only snapshot accessor used by the unified window's Home tab.
    /// Returns a `MetricsReading` backed by the same SQLite database as
    /// `makeMetricsService()`, so rollups + recents stay consistent.
    public static func makeMetricsReader() throws -> any MetricsReading {
        let databaseURL = AppConfig.liveStorageLocator()
            .url(for: .recordings)
            .appendingPathComponent(transcriptDatabaseFileName, isDirectory: false)
            .standardizedFileURL

        return try SQLiteMetricsReader(
            databaseURL: databaseURL,
            referenceDateProvider: Date.init
        )
    }

    public static func makeGlobalHotkeyMonitor() -> GlobalHotkeyMonitor {
        makeGlobalHotkeyMonitor(
            permissionService: makePermissionService(),
            coordinator: AppComposition.sessionCoordinator
        )
    }

    public static func makeGlobalHotkeyMonitor(
        permissionService: any PermissionService,
        coordinator: SessionCoordinator
    ) -> GlobalHotkeyMonitor {
        return GlobalHotkeyMonitor(
            onTrigger: {
                Task {
                    await coordinator.toggle()
                }
            },
            permissionService: makePermissionServiceAdapter(wrapping: permissionService)
        )
    }

    @MainActor
    public static let hotkeyMonitor: GlobalHotkeyMonitor = makeGlobalHotkeyMonitor()

    @MainActor
    static func makeStartupCoordinator(
        coordinator: SessionCoordinator = AppComposition.sessionCoordinator,
        hotkeyMonitor: GlobalHotkeyMonitor = AppComposition.hotkeyMonitor
    ) -> AppStartupCoordinator {
        let logger = PersonalScribeLogger(category: PersonalScribeLogCategory.app)

        return AppStartupCoordinator(
            startHotkeyMonitor: {
                hotkeyMonitor.start()
            },
            prepareTranscriber: {
                do {
                    try await coordinator.prepareTranscriber()
                } catch is CancellationError {
                    return
                } catch {
                    logger.error("Startup transcriber preparation failed", error: error)
                }
            },
            logger: logger
        )
    }

    static func makePermissionService() -> AppKitPermissionService {
        AppKitPermissionService()
    }

    private static func makePermissionServiceAdapter(
        wrapping permissionService: any PermissionService
    ) -> PermissionServiceAdapter {
        if let permissionService = permissionService as? PermissionServiceAdapter {
            return permissionService
        }

        return wrapPermissionService(permissionService)
    }

    private static func wrapPermissionService<Service: PermissionService>(
        _ permissionService: Service
    ) -> PermissionServiceAdapter {
        PermissionServiceAdapter(wrapping: permissionService)
    }
}
