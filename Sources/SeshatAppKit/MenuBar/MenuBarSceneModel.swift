import Combine
import Foundation
import SeshatCore
import SeshatSession

@MainActor
final class MenuBarSceneModel: ObservableObject {
    @Published var state: SessionState = .idle
    @Published var permissionState: MicrophonePermissionState
    @Published var lastResultText: String? = nil
    @Published var preparationProgress: ModelDownloadProgress?

    private let coordinator: SessionCoordinator
    private let permissionRequester: any MicrophonePermissionRequesting
    private let permissionStateProvider: @MainActor () -> MicrophonePermissionState
    private let clipboardWriter: @MainActor (String) -> Void
    private let pasteInjector: @MainActor (String) -> PasteRoutingDecision
    private let openSettings: @MainActor () -> Void
    private let areCriticalPermissionsGranted: @MainActor () -> Bool
    private let openOnboardingRequested: @MainActor () -> Void
    private let onClipboardOnlyCopy: @MainActor () -> Void
    private let logger: SeshatLogger
    private let onObservationCancelled: (@Sendable () -> Void)?
    private var observationTask: Task<Void, Never>?
    private var preparationObservationTask: Task<Void, Never>?
    private var lastAutoPastedTranscript: String?
    private(set) var observationTaskCreationCount = 0

    init(
        coordinator: SessionCoordinator,
        permissionRequester: any MicrophonePermissionRequesting,
        permissionStateProvider: @escaping @MainActor () -> MicrophonePermissionState,
        clipboardWriter: @escaping @MainActor (String) -> Void,
        pasteInjector: @escaping @MainActor (String) -> PasteRoutingDecision = { _ in .pasteAtCursor },
        openSettings: @escaping @MainActor () -> Void,
        areCriticalPermissionsGranted: @escaping @MainActor () -> Bool = { true },
        openOnboardingRequested: @escaping @MainActor () -> Void = {},
        onClipboardOnlyCopy: @escaping @MainActor () -> Void = {},
        onObservationCancelled: (@Sendable () -> Void)? = nil,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui)
    ) {
        self.coordinator = coordinator
        self.permissionRequester = permissionRequester
        self.permissionStateProvider = permissionStateProvider
        self.clipboardWriter = clipboardWriter
        self.pasteInjector = pasteInjector
        self.openSettings = openSettings
        self.areCriticalPermissionsGranted = areCriticalPermissionsGranted
        self.openOnboardingRequested = openOnboardingRequested
        self.onClipboardOnlyCopy = onClipboardOnlyCopy
        self.onObservationCancelled = onObservationCancelled
        self.logger = logger
        self.permissionState = permissionStateProvider()
    }

    func startObserving() {
        guard observationTask == nil else { return }

        logger.info("Starting coordinator observation")
        observationTaskCreationCount += 1
        let coordinator = coordinator
        observationTask = Task { [weak self, coordinator] in
            guard let self else { return }
            let stream = await coordinator.stateStream()
            for await newState in stream {
                let lastResultText: String?
                if case .idle = newState {
                    lastResultText = await coordinator.lastResult()?.text
                } else {
                    lastResultText = nil
                }

                await MainActor.run {
                    self.state = newState
                    if case .idle = newState {
                        self.lastResultText = lastResultText
                        self.autoPasteTranscriptIfNeeded(lastResultText)
                    }
                }
            }
        }

        preparationObservationTask = Task { [weak self, coordinator] in
            guard let self else { return }
            let stream = await coordinator.modelDownloadProgress()
            for await progress in stream {
                await MainActor.run {
                    switch progress.phase {
                    case .idle, .finished:
                        self.preparationProgress = nil
                    case .downloading, .loading:
                        self.preparationProgress = progress
                    }
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
        switch permissionState {
        case .granted, .denied:
            await coordinator.toggle()
        case .notYetRequested:
            let granted = await permissionRequester.requestAccess()
            permissionState = granted ? .granted : .denied
            logger.info("Microphone permission request completed: \(granted)")
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
        openSettings()
    }

    private func autoPasteTranscriptIfNeeded(_ transcript: String?) {
        guard let transcript, !transcript.isEmpty else { return }
        guard transcript != lastAutoPastedTranscript else { return }

        lastAutoPastedTranscript = transcript
        let route = pasteInjector(transcript)
        if case .clipboardOnly = route {
            onClipboardOnlyCopy()
        }
    }

    deinit {
        observationTask?.cancel()
        preparationObservationTask?.cancel()
        onObservationCancelled?()
    }
}
