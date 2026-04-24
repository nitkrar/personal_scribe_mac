import Combine
import Foundation
import PersonalScribeCore

@MainActor
public final class PillOverlayController: ObservableObject {
    public let viewModel: PillOverlayViewModel

    private let appStore: AppStore
    private let defaults: UserDefaults?
    private let legacyVisibilityModeBridge: LegacyVisibilityModeBridge?
    private let presenter: PillOverlayPresenter
    private var cancellables: Set<AnyCancellable> = []
    private var recordingStatusCardContent: StatusCardContent?
    /// Stage B (#046) consumer-side cache of the last VAD fire-token
    /// this controller rendered a notification for. Compared against
    /// `SessionSnapshot.vadAutoStopFireToken` by the driver to guarantee
    /// the notification renders exactly once per auto-stop fire.
    private var lastSeenVadFireToken: UUID?
    /// Stage B (#046) closure invoked when the user taps the "Update
    /// settings to change" link inside the auto-stopped notification.
    /// Injected at composition time (Chunk E wires this to the
    /// `openSettingsTab` closure from `PersonalScribeAppMain`). When
    /// nil, the link still renders but taps are no-ops.
    /// Closure that opens Settings at the VAD-prefs section. Injected by
    /// composition via `setOpenVadSettingsAction` AFTER the unified-window
    /// host exists — the host is constructed later than `PillOverlayController`
    /// in `PersonalScribeAppMain`, so we can't pass it at init. The
    /// "Auto stopped" notification's link-tap routes through here.
    private var openVadSettingsAction: (@MainActor @Sendable () -> Void)?

    // Stage 2 compatibility bridge. Delete these public publisher-backed
    // initializers in the Stage 3 duplicate-observation cleanup pass.
    public convenience init(
        statePublisher: AnyPublisher<SessionState, Never>,
        preparationProgressPublisher: AnyPublisher<ModelDownloadProgress?, Never>,
        onTap: @escaping @MainActor () -> Void = {}
    ) {
        self.init(
            statePublisher: statePublisher,
            preparationProgressPublisher: preparationProgressPublisher,
            audioLevelPublisher: nil,
            visibilityMode: PillVisibilityMode.resolve(),
            onTap: onTap
        )
    }

    // Stage 2 compatibility bridge. Delete this once all legacy publisher
    // call sites are removed in Stage 3.
    public convenience init(
        statePublisher: AnyPublisher<SessionState, Never>,
        preparationProgressPublisher: AnyPublisher<ModelDownloadProgress?, Never>,
        audioLevelPublisher: AnyPublisher<Double, Never>?,
        visibilityMode: PillVisibilityMode = .autoShow,
        onTap: @escaping @MainActor () -> Void = {},
        openVadSettingsAction: (@MainActor @Sendable () -> Void)? = nil
    ) {
        let visibilityModeBridge = LegacyVisibilityModeBridge(initialMode: visibilityMode)
        let appStore = AppStore(
            session: LegacyPillOverlaySessionProvider(
                statePublisher: statePublisher,
                progressPublisher: preparationProgressPublisher
            ),
            permissions: LegacyPillOverlayPermissionService(),
            activeModeSource: LegacyPillOverlayActiveModeProvider(),
            visibilityModeSource: visibilityModeBridge
        )
        appStore.start()

        self.init(
            appStore: appStore,
            audioLevelPublisher: audioLevelPublisher,
            defaults: nil,
            legacyVisibilityModeBridge: visibilityModeBridge,
            onTap: onTap,
            panelBuilder: AppKitPillOverlayPanelBuilder(),
            openVadSettingsAction: openVadSettingsAction
        )
    }

    convenience init(
        appStore: AppStore,
        audioLevelPublisher: AnyPublisher<Double, Never>? = nil,
        defaults: UserDefaults = .standard,
        onTap: @escaping @MainActor () -> Void = {},
        panelBuilder: any PillOverlayPanelBuilding = AppKitPillOverlayPanelBuilder(),
        openVadSettingsAction: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.init(
            appStore: appStore,
            audioLevelPublisher: audioLevelPublisher,
            defaults: defaults,
            legacyVisibilityModeBridge: nil,
            onTap: onTap,
            panelBuilder: panelBuilder,
            openVadSettingsAction: openVadSettingsAction
        )
    }

    private init(
        appStore: AppStore,
        audioLevelPublisher: AnyPublisher<Double, Never>? = nil,
        defaults: UserDefaults?,
        legacyVisibilityModeBridge: LegacyVisibilityModeBridge?,
        onTap: @escaping @MainActor () -> Void = {},
        panelBuilder: any PillOverlayPanelBuilding = AppKitPillOverlayPanelBuilder(),
        openVadSettingsAction: (@MainActor @Sendable () -> Void)? = nil
    ) {
        let initialMode = legacyVisibilityModeBridge?.currentPillVisibilityMode()
            ?? PillVisibilityMode.resolve(from: defaults ?? .standard)

        self.appStore = appStore
        self.defaults = defaults
        self.legacyVisibilityModeBridge = legacyVisibilityModeBridge
        self.openVadSettingsAction = openVadSettingsAction

        let viewModel = PillOverlayViewModel(
            visibility: appStore.snapshot.pillVisibility,
            visibilityMode: initialMode
        )
        self.viewModel = viewModel
        self.presenter = PillOverlayPresenter(
            model: viewModel,
            onTap: onTap,
            panelBuilder: panelBuilder
        )

        applySnapshot(appStore.snapshot)

        appStore.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.applySnapshot(self.appStore.snapshot)
                }
            }
        }
        .store(in: &cancellables)

        if let audioLevelPublisher {
            audioLevelPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak viewModel] level in
                    MainActor.assumeIsolated {
                        viewModel?.audioLevel = level
                    }
                }
                .store(in: &cancellables)
        }
    }

    public func setVisibilityMode(
        _ mode: PillVisibilityMode,
        defaults: UserDefaults = .standard
    ) {
        viewModel.setVisibilityMode(mode)
        legacyVisibilityModeBridge?.set(mode)
        mode.persist(to: defaults)
    }

    public func showClipboardOnlyNotice() {
        presenter.showClipboardOnlyNotice()
    }

    /// Late-binding install for the Settings-deep-link closure. Called by
    /// `PersonalScribeAppMain` after `unifiedWindowControllerHost` exists
    /// (which is instantiated later in the composition flow than this
    /// controller). The closure is invoked when the user taps the
    /// "Update settings to change" link on the VAD auto-stopped notification.
    public func setOpenVadSettingsAction(_ action: @escaping @MainActor @Sendable () -> Void) {
        openVadSettingsAction = action
    }

    private func applySnapshot(_ snapshot: AppStoreSnapshot) {
        viewModel.apply(
            visibility: snapshot.pillVisibility,
            visibilityMode: currentVisibilityMode()
        )

        applyRecordingStatusCardState(
            sessionState: snapshot.sessionState,
            progress: snapshot.modelDownloadProgress,
            vadGracePending: snapshot.session.vadAutoStopGracePending,
            vadFireToken: snapshot.session.vadAutoStopFireToken
        )
    }

    /// Feeds the snapshot-derived inputs (plus the two Stage B VAD
    /// prefs, read fresh per update so mid-session toggles take effect
    /// on the next snapshot — see also `SessionPipelineOrchestrator`
    /// which freezes the prefs at session start for the actual
    /// grace/notify decisions) into `RecordingStatusCardDriver` and
    /// routes the result to the presenter. Tracks
    /// `lastSeenVadFireToken` locally so the notification renders
    /// exactly once per auto-stop fire.
    private func applyRecordingStatusCardState(
        sessionState: SessionState,
        progress: ModelDownloadProgress?,
        vadGracePending: Bool,
        vadFireToken: UUID?
    ) {
        let showStoppingWarning = VadShowStoppingWarningPreference.resolve(
            from: defaults ?? .standard
        )
        let showAutoStoppedNotification = VadShowAutoStoppedNotificationPreference.resolve(
            from: defaults ?? .standard
        )

        let nextContent = RecordingStatusCardDriver.statusContent(
            sessionState: sessionState,
            progress: progress,
            vadGracePending: vadGracePending,
            vadFireToken: vadFireToken,
            vadLastSeenFireToken: lastSeenVadFireToken,
            showStoppingWarning: showStoppingWarning,
            showAutoStoppedNotification: showAutoStoppedNotification
        )

        switch (recordingStatusCardContent, nextContent) {
        case (nil, let next?):
            presenter.showRecordingStatusCard(
                text: next.text,
                link: next.link,
                autoDismissAfter: autoDismissDuration(for: next),
                onLinkTap: linkTapHandler(for: next)
            )
            recordingStatusCardContent = next
            advanceLastSeenFireToken(renderedContent: next, snapshotToken: vadFireToken)
        case (let current?, let next?) where current != next:
            // When the new content only differs from the current card
            // in its text (no link on either side), keep using the
            // cheap `update(text:)` path so the record-without-
            // transcribe progress ticks don't flash the whole card in
            // and out. Any change that touches the link region (or
            // brings in a link where there was none) needs a full
            // `show(...)` so the link-tap gesture + auto-dismiss timer
            // are re-attached consistently. The notification contract
            // — "2.0s OR new session start, whichever first" — is
            // preserved because each notification token flip goes
            // through `show(...)` (either link: nil → link: some or
            // between two different link ranges).
            if current.link == nil && next.link == nil {
                presenter.updateRecordingStatusCard(text: next.text)
            } else {
                presenter.showRecordingStatusCard(
                    text: next.text,
                    link: next.link,
                    autoDismissAfter: autoDismissDuration(for: next),
                    onLinkTap: linkTapHandler(for: next)
                )
            }
            recordingStatusCardContent = next
            advanceLastSeenFireToken(renderedContent: next, snapshotToken: vadFireToken)
        case (let current?, nil):
            // Notifications self-dismiss via the ResponseCard's 2.0s timer
            // (installed in `show(...)`). If we hide here, the card vanishes
            // the instant the driver returns nil — which happens as soon as
            // the snapshot transitions to `.transcribing` (fireToken has been
            // seen, driver's token gate drops it). Let the timer finish;
            // clear local tracking so subsequent content flows normally.
            // Any non-notification content (warning, error, record-without-
            // transcribe) still gets an explicit hide.
            if current.link?.action == .openVadSettings {
                recordingStatusCardContent = nil
            } else {
                presenter.hideRecordingStatusCard()
                recordingStatusCardContent = nil
            }
        default:
            break
        }
    }

    /// The "Auto stopped. Update settings to change." notification
    /// auto-dismisses after 2.0s per the locked Stage B spec. Every
    /// other message (error, warning, record-without-transcribe)
    /// sticks until the next state change hides or replaces it.
    private func autoDismissDuration(for content: StatusCardContent) -> TimeInterval? {
        content.link?.action == .openVadSettings ? 2.0 : nil
    }

    /// Builds a link-tap callback that invokes `openVadSettingsAction`
    /// on the main actor when the rendered content carries a link.
    /// Returns nil for link-less content so `ResponseCardView` skips
    /// the gesture recognizer entirely.
    private func linkTapHandler(
        for content: StatusCardContent
    ) -> (@Sendable @MainActor (StatusCardLinkAction) -> Void)? {
        guard content.link != nil,
              let openVadSettingsAction
        else {
            return nil
        }

        return { @Sendable @MainActor action in
            switch action {
            case .openVadSettings:
                openVadSettingsAction()
            }
        }
    }

    /// Advances `lastSeenVadFireToken` to the snapshot's fire-token
    /// after the notification renders so the driver returns nil on the
    /// next snapshot carrying the same token. Only fires after the
    /// notification branch (link present) actually rendered — the
    /// warning and error branches must not eat the token.
    private func advanceLastSeenFireToken(
        renderedContent: StatusCardContent,
        snapshotToken: UUID?
    ) {
        guard renderedContent.link?.action == .openVadSettings else {
            return
        }
        lastSeenVadFireToken = snapshotToken
    }

    private func currentVisibilityMode() -> PillVisibilityMode {
        if let legacyVisibilityModeBridge {
            return legacyVisibilityModeBridge.currentPillVisibilityMode()
        }

        return PillVisibilityMode.resolve(from: defaults ?? .standard)
    }
}

private final class LegacyVisibilityModeBridge: @unchecked Sendable, AppStoreVisibilityModeProviding {
    private let lock = NSLock()
    private var mode: PillVisibilityMode
    private var continuations: [UUID: AsyncStream<AppStoreVisibilityMode>.Continuation] = [:]

    init(initialMode: PillVisibilityMode) {
        mode = initialMode
    }

    func currentPillVisibilityMode() -> PillVisibilityMode {
        lock.lock()
        defer { lock.unlock() }
        return mode
    }

    func set(_ mode: PillVisibilityMode) {
        lock.lock()
        self.mode = mode
        let mappedMode = Self.map(mode)
        for continuation in continuations.values {
            continuation.yield(mappedMode)
        }
        lock.unlock()
    }

    func currentVisibilityMode() -> AppStoreVisibilityMode {
        Self.map(currentPillVisibilityMode())
    }

    func visibilityModeStream() -> AsyncStream<AppStoreVisibilityMode> {
        let id = UUID()

        return AsyncStream { continuation in
            lock.lock()
            continuations[id] = continuation
            continuation.yield(Self.map(mode))
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id: id)
            }
        }
    }

    private func removeContinuation(id: UUID) {
        lock.lock()
        continuations[id] = nil
        lock.unlock()
    }

    private static func map(_ mode: PillVisibilityMode) -> AppStoreVisibilityMode {
        switch mode {
        case .alwaysOn:
            return .alwaysOn
        case .autoShow:
            return .autoShow
        case .hidden:
            return .hidden
        }
    }
}

private final class LegacyPillOverlaySessionProvider: @unchecked Sendable, AppStoreSessionProviding {
    private let statePublisher: AnyPublisher<SessionState, Never>
    private let progressPublisher: AnyPublisher<ModelDownloadProgress?, Never>

    init(
        statePublisher: AnyPublisher<SessionState, Never>,
        progressPublisher: AnyPublisher<ModelDownloadProgress?, Never>
    ) {
        self.statePublisher = statePublisher
        self.progressPublisher = progressPublisher
    }

    func snapshotStream() -> AsyncStream<SessionSnapshot> {
        AsyncStream { continuation in
            let box = LegacySnapshotStreamBox()
            box.cancellables = [
                statePublisher
                    .receive(on: DispatchQueue.main)
                    .sink { state in
                        box.currentState = state
                        continuation.yield(
                            SessionSnapshot(
                                sessionState: state,
                                modelDownloadProgress: box.currentProgress
                            )
                        )
                    },
                progressPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { progress in
                        box.currentProgress = progress
                        continuation.yield(
                            SessionSnapshot(
                                sessionState: box.currentState,
                                modelDownloadProgress: progress
                            )
                        )
                    }
            ]
            continuation.onTermination = { _ in
                box.cancellables.forEach { $0.cancel() }
            }
        }
    }
}

private final class LegacySnapshotStreamBox: @unchecked Sendable {
    var cancellables: [AnyCancellable] = []
    var currentState: SessionState = .idle
    var currentProgress: ModelDownloadProgress?
}

@MainActor
private final class LegacyPillOverlayPermissionService: PermissionService, @unchecked Sendable {
    @Published private(set) var statuses: [Permission: PermissionStatus] = [:]

    func status(for permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .pending
    }

    func request(_ permission: Permission) async -> RequestOutcome {
        RequestOutcome(
            prompted: false,
            openedSettings: false,
            requiresRelaunch: false,
            finalStatus: status(for: permission)
        )
    }

    func statusSnapshot() -> [Permission: PermissionStatus] {
        statuses
    }

    func refresh() {}

    func systemSettingsDeepLink(for permission: Permission) -> URL {
        URL(string: "about:blank")!
    }
}

private struct LegacyPillOverlayActiveModeProvider: AppStoreActiveModeProviding {
    func currentActiveMode() -> ModeDescriptor? {
        nil
    }

    func activeModeStream() -> AsyncStream<ModeDescriptor?> {
        AsyncStream { continuation in
            continuation.yield(nil)
            continuation.finish()
        }
    }
}
