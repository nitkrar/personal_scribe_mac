import AppKit
import Combine
import SwiftUI
import SeshatCore

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let onFinish: @MainActor () -> Void
    private var completionCancellable: AnyCancellable?
    private var shouldNotifyOnClose = false

    init(
        viewModel: OnboardingViewModel = OnboardingViewModel(),
        onFinish: @escaping @MainActor () -> Void = {}
    ) {
        self.onFinish = onFinish

        let hostingController = NSHostingController(rootView: OnboardingView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 520, height: 360))
        window.styleMask = [.titled, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.title = "Welcome to Seshat"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: window)

        window.delegate = self
        completionCancellable = viewModel.$isOnboardingComplete
            .removeDuplicates()
            .sink { [weak self] isComplete in
                guard isComplete else { return }
                self?.shouldNotifyOnClose = true
                self?.close()
            }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        guard let window else { return }

        if !window.isVisible {
            window.center()
        }

        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard shouldNotifyOnClose else { return }
        shouldNotifyOnClose = false
        onFinish()
    }
}

@MainActor
final class OnboardingWindowControllerHost: ObservableObject {
    private let defaults: UserDefaults
    private let startupCoordinator: AppStartupCoordinator
    private let microphoneStateProvider: @MainActor () -> MicrophonePermissionState
    private let inputMonitoringProbe: any PermissionProbing
    private let isAccessibilityTrusted: @MainActor () -> Bool
    private let controllerFactory: @MainActor (_ onFinish: @escaping @MainActor () -> Void) -> OnboardingWindowController

    private var controller: OnboardingWindowController?
    private var didStartStartupCoordinator = false
    private var hasCompletedFirstRunOnboarding: Bool

    init(
        defaults: UserDefaults = .standard,
        startupCoordinator: AppStartupCoordinator,
        microphoneStateProvider: @escaping @MainActor () -> MicrophonePermissionState,
        inputMonitoringProbe: any PermissionProbing = IOHIDPermissionProbe(),
        isAccessibilityTrusted: @escaping @MainActor () -> Bool,
        controllerFactory: @escaping @MainActor (
            _ onFinish: @escaping @MainActor () -> Void
        ) -> OnboardingWindowController = { OnboardingWindowController(onFinish: $0) }
    ) {
        self.defaults = defaults
        self.startupCoordinator = startupCoordinator
        self.microphoneStateProvider = microphoneStateProvider
        self.inputMonitoringProbe = inputMonitoringProbe
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.controllerFactory = controllerFactory
        self.hasCompletedFirstRunOnboarding = SeshatOnboardingCompleted.resolve(from: defaults).rawValue
    }

    var areCriticalPermissionsGranted: Bool {
        guard hasCompletedFirstRunOnboarding else { return false }
        guard microphoneStateProvider() == .granted else { return false }
        guard inputMonitoringProbe.checkInputMonitoring() == .granted else { return false }
        return isAccessibilityTrusted()
    }

    func start() {
        if hasCompletedFirstRunOnboarding {
            startStartupCoordinatorIfNeeded()
            return
        }

        presentOnboarding(persistCompletionOnFinish: true)
    }

    @discardableResult
    func requestInteractionAccess() -> Bool {
        guard areCriticalPermissionsGranted else {
            presentOnboarding(persistCompletionOnFinish: !hasCompletedFirstRunOnboarding)
            return false
        }

        return true
    }

    func presentPermissionsFallback() {
        presentOnboarding(persistCompletionOnFinish: !hasCompletedFirstRunOnboarding)
    }

    private func presentOnboarding(persistCompletionOnFinish: Bool) {
        if let controller {
            controller.present()
            return
        }

        let controller = controllerFactory { [weak self] in
            self?.handleOnboardingFinish(persistCompletionOnFinish: persistCompletionOnFinish)
        }
        self.controller = controller
        controller.present()
    }

    private func handleOnboardingFinish(persistCompletionOnFinish: Bool) {
        controller = nil

        guard persistCompletionOnFinish else { return }

        OnboardingState.completed.persist(to: defaults)
        hasCompletedFirstRunOnboarding = true
        startStartupCoordinatorIfNeeded()
    }

    private func startStartupCoordinatorIfNeeded() {
        guard !didStartStartupCoordinator else { return }
        didStartStartupCoordinator = true
        startupCoordinator.start()
    }
}
