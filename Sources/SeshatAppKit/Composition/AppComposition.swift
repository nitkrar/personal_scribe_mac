import AppKit
import Foundation
import SeshatAudio
import SeshatCore
import SeshatSession
import SeshatTranscription

@MainActor
public enum AppComposition {
    private static let transcriptDatabaseFileName = "transcripts.sqlite"

    public static let sessionCoordinator: SessionCoordinator = {
        let logger = SeshatLogger(category: SeshatLogCategory.session)
        let capture = AVAudioCaptureService(
            logger: SeshatLogger(category: SeshatLogCategory.audio)
        )
        let modelService = DefaultModelService(
            logger: SeshatLogger(category: SeshatLogCategory.session)
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
        let logger = SeshatLogger(category: SeshatLogCategory.session)
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

        // TODO: consumer wiring in SeshatAppMain deferred until Phase 2 Home tab lands
        return try SQLiteMetricsService(
            databaseURL: databaseURL,
            calendar: .current,
            referenceDateProvider: Date.init
        )
    }

    public static func makeGlobalHotkeyMonitor(
        permissionService: PermissionServiceAdapter? = nil,
        coordinator: SessionCoordinator = AppComposition.sessionCoordinator
    ) -> GlobalHotkeyMonitor {
        GlobalHotkeyMonitor(
            onTrigger: {
                Task {
                    await coordinator.toggle()
                }
            },
            emergencyQuitRequested: {
                NSApplication.shared.terminate(nil)
            },
            permissionService: permissionService
        )
    }

    @MainActor
    public static let hotkeyMonitor: GlobalHotkeyMonitor = makeGlobalHotkeyMonitor()

    @MainActor
    static func makeStartupCoordinator(
        coordinator: SessionCoordinator = AppComposition.sessionCoordinator,
        hotkeyMonitor: GlobalHotkeyMonitor = AppComposition.hotkeyMonitor
    ) -> AppStartupCoordinator {
        let logger = SeshatLogger(category: SeshatLogCategory.app)

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

    public static func makeMicrophonePermissionRequester() -> any MicrophonePermissionRequesting {
        AppKitMicrophonePermissionRequester()
    }

    static func makePermissionService() -> AppKitPermissionService {
        AppKitPermissionService()
    }
}
