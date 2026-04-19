import Combine
import Foundation
import SeshatCore
import SeshatSession

@MainActor
final class MenuBarSceneModel: ObservableObject {
    @Published var state: SessionState = .idle
    @Published var lastResultText: String? = nil
    @Published var preparationProgress: ModelDownloadProgress?

    private let coordinator: SessionCoordinator
    private let permissionService: any PermissionService
    private let clipboardWriter: @MainActor (String) -> Void
    private let pasteInjector: @MainActor (String) -> PasteRoutingDecision
    private let openURL: @MainActor (URL) -> Void
    private let onClipboardOnlyCopy: @MainActor () -> Void
    private let logger: SeshatLogger
    private let onObservationCancelled: (@Sendable () -> Void)?
    private var observationTask: Task<Void, Never>?
    private var preparationObservationTask: Task<Void, Never>?
    private var permissionObservation: AnyCancellable?
    private var lastAutoPastedTranscript: String?
    private(set) var observationTaskCreationCount = 0

    var permissionState: MicrophonePermissionState {
        (permissionService.statuses[.microphone] ?? .pending).microphonePermissionState
    }

    init(
        coordinator: SessionCoordinator,
        permissionRequester: any MicrophonePermissionRequesting = AppKitMicrophonePermissionRequester(),
        permissionStateProvider: @escaping @MainActor () -> MicrophonePermissionState = { .notYetRequested },
        clipboardWriter: @escaping @MainActor (String) -> Void,
        pasteInjector: @escaping @MainActor (String) -> PasteRoutingDecision = { _ in .pasteAtCursor },
        openSettings: @escaping @MainActor () -> Void,
        permissionService: (any PermissionService)? = nil,
        openURL: (@MainActor (URL) -> Void)? = nil,
        areCriticalPermissionsGranted: @escaping @MainActor () -> Bool = { true },
        openOnboardingRequested: @escaping @MainActor () -> Void = {},
        onClipboardOnlyCopy: @escaping @MainActor () -> Void = {},
        onObservationCancelled: (@Sendable () -> Void)? = nil,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui)
    ) {
        _ = areCriticalPermissionsGranted
        _ = openOnboardingRequested
        let resolvedPermissionService = permissionService
            ?? Self.makeCompatibilityPermissionService(
                permissionRequester: permissionRequester,
                permissionStateProvider: permissionStateProvider
            )
        self.coordinator = coordinator
        self.permissionService = resolvedPermissionService
        self.clipboardWriter = clipboardWriter
        self.pasteInjector = pasteInjector
        self.openURL = openURL ?? { _ in openSettings() }
        self.onClipboardOnlyCopy = onClipboardOnlyCopy
        self.onObservationCancelled = onObservationCancelled
        self.logger = logger
        self.permissionObservation = Self.observePermissionChanges(for: resolvedPermissionService) { [weak self] in
            self?.objectWillChange.send()
        }
    }

    private static func observePermissionChanges<Service: PermissionService>(
        for service: Service,
        onChange: @escaping @MainActor () -> Void
    ) -> AnyCancellable {
        service.objectWillChange.sink { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    onChange()
                }
            }
        }
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

    private static func makeCompatibilityPermissionService(
        permissionRequester: any MicrophonePermissionRequesting,
        permissionStateProvider: @escaping @MainActor () -> MicrophonePermissionState
    ) -> PermissionServiceAdapter {
        @MainActor
        final class StateBox {
            var statuses: [Permission: PermissionStatus]

            init(statuses: [Permission: PermissionStatus]) {
                self.statuses = statuses
            }
        }

        let box = StateBox(statuses: [
            .microphone: permissionStateProvider().unifiedPermissionStatus,
            .inputMonitoring: .pending,
            .accessibility: .pending,
        ])

        return PermissionServiceAdapter(
            initialStatuses: box.statuses,
            statusReader: { permission in
                box.statuses[permission] ?? .pending
            },
            requester: { permission in
                guard permission == .microphone else {
                    return RequestOutcome(
                        prompted: false,
                        openedSettings: false,
                        requiresRelaunch: false,
                        finalStatus: box.statuses[permission] ?? .pending
                    )
                }

                let granted = await permissionRequester.requestAccess()
                let finalStatus: PermissionStatus = granted ? .granted : .denied
                box.statuses[.microphone] = finalStatus
                return RequestOutcome(
                    prompted: true,
                    openedSettings: false,
                    requiresRelaunch: false,
                    finalStatus: finalStatus
                )
            },
            refresher: {
                box.statuses
            }
        )
    }
}
