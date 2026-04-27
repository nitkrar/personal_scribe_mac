import Combine
import Foundation
import PersonalScribeCore
import PersonalScribeSession

@MainActor
final class MenuBarSceneModel: ObservableObject {
    @Published var state: SessionState = .idle
    @Published var lastResultText: String? = nil
    @Published var preparationProgress: ModelDownloadProgress?

    let appStore: AppStore
    private let coordinator: SessionCoordinator
    private let permissionService: any PermissionService
    private let clipboardWriter: @MainActor (String) -> Void
    private let outputService: any OutputService
    private let openURL: @MainActor (URL) -> Void
    private let onClipboardOnlyCopy: @MainActor () -> Void
    private let logger: PersonalScribeLogger
    private let onObservationCancelled: (@Sendable () -> Void)?
    private var snapshotObservation: AnyCancellable?
    private var lastAutoPastedTranscript: String?
    private(set) var observationTaskCreationCount = 0

    var snapshot: AppStoreSnapshot {
        appStore.snapshot
    }

    init(
        appStore: AppStore,
        coordinator: SessionCoordinator,
        clipboardWriter: @escaping @MainActor (String) -> Void,
        outputService: any OutputService,
        permissionService: any PermissionService,
        openURL: @escaping @MainActor (URL) -> Void,
        onClipboardOnlyCopy: @escaping @MainActor () -> Void = {},
        onObservationCancelled: (@Sendable () -> Void)? = nil,
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.ui)
    ) {
        let snapshot = appStore.snapshot
        _state = Published(initialValue: snapshot.sessionState)
        _lastResultText = Published(initialValue: snapshot.lastTranscriptionResult?.text)
        _preparationProgress = Published(initialValue: snapshot.modelDownloadProgress)
        self.appStore = appStore
        self.coordinator = coordinator
        self.permissionService = permissionService
        self.clipboardWriter = clipboardWriter
        self.outputService = outputService
        self.openURL = openURL
        self.onClipboardOnlyCopy = onClipboardOnlyCopy
        self.onObservationCancelled = onObservationCancelled
        self.logger = logger
    }

    convenience init(
        coordinator: SessionCoordinator,
        clipboardWriter: @escaping @MainActor (String) -> Void,
        outputService: (any OutputService)? = nil,
        openSettings: @escaping @MainActor () -> Void,
        permissionService: (any PermissionService)? = nil,
        openURL: (@MainActor (URL) -> Void)? = nil,
        onClipboardOnlyCopy: @escaping @MainActor () -> Void = {},
        onObservationCancelled: (@Sendable () -> Void)? = nil,
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.ui)
    ) {
        let resolvedPermissionService = permissionService ?? AppComposition.makePermissionService()
        let appStorePermissionService = Self.makePermissionServiceAdapter(
            wrapping: resolvedPermissionService
        )
        let appStore = AppStore(
            session: coordinator.appStoreSessionProvider(),
            permissions: appStorePermissionService,
            workflowModeRegistry: AppComposition.workflowModeRegistry,
            visibilityModeSource: AppKitVisibilityModeProvider()
        )
        appStore.start()

        self.init(
            appStore: appStore,
            coordinator: coordinator,
            clipboardWriter: clipboardWriter,
            outputService: outputService ?? ClipboardBatchOutput(),
            permissionService: resolvedPermissionService,
            openURL: openURL ?? { _ in openSettings() },
            onClipboardOnlyCopy: onClipboardOnlyCopy,
            onObservationCancelled: onObservationCancelled,
            logger: logger
        )
    }

    func startObserving() {
        guard snapshotObservation == nil else { return }

        logger.info("Starting AppStore observation")
        observationTaskCreationCount += 1
        applySnapshot(appStore.snapshot)
        snapshotObservation = appStore.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.applySnapshot(self.appStore.snapshot)
                }
            }
        }
    }

    func handleRecordButtonTap() async {
        logger.info("Record button tapped")

        // No permissions gating — menu items should always work. If
        // permissions are missing, the record path surfaces the failure
        // visibly (OS prompt for mic, SessionCoordinator → .error for
        // IM-denied, etc.) rather than silently routing the click to an
        // onboarding window. User explicitly asked for this behaviour
        // (2026-04-19) after a `defaults delete` left menu items stuck
        // in an onboarding-required state.
        switch permissionService.statuses[.microphone] ?? .pending {
        case .granted, .denied:
            await coordinator.toggle()
        case .pending:
            let outcome = await permissionService.request(.microphone)
            logger.info("Microphone permission request completed: \(outcome.finalStatus == .granted)")
            await coordinator.toggle()
        }
    }

    func copyLatestTranscript() {
        guard let lastResultText, !lastResultText.isEmpty else {
            logger.info("Copy transcript skipped because no transcript is available")
            return
        }

        logger.info("Copying latest transcript to clipboard")
        clipboardWriter(lastResultText)
    }

    func openMicrophonePrivacySettings() {
        logger.info("Opening microphone privacy settings")
        openURL(permissionService.systemSettingsDeepLink(for: .microphone))
    }

    private func autoPasteTranscriptIfNeeded(_ transcript: String?) {
        guard let transcript, !transcript.isEmpty else { return }
        guard transcript != lastAutoPastedTranscript else { return }

        lastAutoPastedTranscript = transcript
        let outputService = outputService
        let onClipboardOnlyCopy = onClipboardOnlyCopy
        let logger = logger

        Task { @MainActor in
            switch await outputService.deliverBatch(text: transcript) {
            case .delivered(let target, _):
                if target == .clipboardOnly || target == .selfFrontmost {
                    onClipboardOnlyCopy()
                }
            case .failed(let error):
                logger.error("Auto-paste transcript delivery failed", error: error)
            case .ignoredEmptyInput:
                break
            }
        }
    }

    private func applySnapshot(_ snapshot: AppStoreSnapshot) {
        let previousState = state
        state = snapshot.sessionState
        preparationProgress = snapshot.modelDownloadProgress

        if snapshot.sessionState.isIdle {
            let transcriptText = snapshot.lastTranscriptionResult?.text
            lastResultText = transcriptText

            if !previousState.isIdle {
                autoPasteTranscriptIfNeeded(transcriptText)
            }
        } else {
            lastResultText = nil
        }
    }

    isolated deinit {
        onObservationCancelled?()
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

private extension SessionState {
    var isIdle: Bool {
        if case .idle = self {
            return true
        }

        return false
    }
}
