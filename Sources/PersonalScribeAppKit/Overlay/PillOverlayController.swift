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
    private var recordingStatusCardText: String?

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
        onTap: @escaping @MainActor () -> Void = {}
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
            panelBuilder: AppKitPillOverlayPanelBuilder()
        )
    }

    convenience init(
        appStore: AppStore,
        audioLevelPublisher: AnyPublisher<Double, Never>? = nil,
        defaults: UserDefaults = .standard,
        onTap: @escaping @MainActor () -> Void = {},
        panelBuilder: any PillOverlayPanelBuilding = AppKitPillOverlayPanelBuilder()
    ) {
        self.init(
            appStore: appStore,
            audioLevelPublisher: audioLevelPublisher,
            defaults: defaults,
            legacyVisibilityModeBridge: nil,
            onTap: onTap,
            panelBuilder: panelBuilder
        )
    }

    private init(
        appStore: AppStore,
        audioLevelPublisher: AnyPublisher<Double, Never>? = nil,
        defaults: UserDefaults?,
        legacyVisibilityModeBridge: LegacyVisibilityModeBridge?,
        onTap: @escaping @MainActor () -> Void = {},
        panelBuilder: any PillOverlayPanelBuilding = AppKitPillOverlayPanelBuilder()
    ) {
        let initialMode = legacyVisibilityModeBridge?.currentPillVisibilityMode()
            ?? PillVisibilityMode.resolve(from: defaults ?? .standard)

        self.appStore = appStore
        self.defaults = defaults
        self.legacyVisibilityModeBridge = legacyVisibilityModeBridge

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

    private func applySnapshot(_ snapshot: AppStoreSnapshot) {
        viewModel.apply(
            visibility: snapshot.pillVisibility,
            visibilityMode: currentVisibilityMode()
        )

        applyRecordingStatusCardState(
            sessionState: snapshot.sessionState,
            progress: snapshot.modelDownloadProgress
        )
    }

    private func applyRecordingStatusCardState(
        sessionState: SessionState,
        progress: ModelDownloadProgress?
    ) {
        let nextText = RecordingStatusCardDriver.statusText(
            sessionState: sessionState,
            progress: progress
        )

        switch (recordingStatusCardText, nextText) {
        case (nil, let next?):
            presenter.showRecordingStatusCard(text: next)
            recordingStatusCardText = next
        case (let current?, let next?) where current != next:
            presenter.updateRecordingStatusCard(text: next)
            recordingStatusCardText = next
        case (_?, nil):
            presenter.hideRecordingStatusCard()
            recordingStatusCardText = nil
        default:
            break
        }
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
