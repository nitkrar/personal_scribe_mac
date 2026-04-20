import AppKit
import Combine
import SwiftUI
import PersonalScribeCore

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
        window.title = "Welcome to \(AppBrand.displayName)"
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
    private let startupCoordinator: AppStartupCoordinator
    private let permissionService: any PermissionService
    private let isOnboardingCompleteProvider: @MainActor () -> Bool
    private let persistOnboardingCompletion: @MainActor () -> Void
    private let controllerFactory: @MainActor (
        _ viewModel: OnboardingViewModel,
        _ onFinish: @escaping @MainActor () -> Void
    ) -> OnboardingWindowController

    private var controller: OnboardingWindowController?
    private var didStartStartupCoordinator = false
    private var hasCompletedFirstRunOnboarding: Bool

    init(
        defaults: UserDefaults = .standard,
        startupCoordinator: AppStartupCoordinator,
        permissionService: (any PermissionService)? = nil,
        isOnboardingCompleteProvider: (@MainActor () -> Bool)? = nil,
        persistOnboardingCompletion: (@MainActor () -> Void)? = nil,
        controllerFactory: @escaping @MainActor (
            _ viewModel: OnboardingViewModel,
            _ onFinish: @escaping @MainActor () -> Void
        ) -> OnboardingWindowController = { viewModel, onFinish in
            OnboardingWindowController(viewModel: viewModel, onFinish: onFinish)
        }
    ) {
        let onboardingCompletionPreference = Self.onboardingCompletionPreference(defaults: defaults)
        self.startupCoordinator = startupCoordinator
        self.permissionService = permissionService ?? AppKitPermissionService()
        self.isOnboardingCompleteProvider = isOnboardingCompleteProvider ?? {
            onboardingCompletionPreference.resolve()
        }
        self.persistOnboardingCompletion = persistOnboardingCompletion ?? {
            onboardingCompletionPreference.persist(true)
        }
        self.controllerFactory = controllerFactory
        self.hasCompletedFirstRunOnboarding = self.isOnboardingCompleteProvider()
    }

    var areCriticalPermissionsGranted: Bool {
        guard hasCompletedFirstRunOnboarding else { return false }
        guard permissionService.status(for: .microphone) == .granted else { return false }
        return permissionService.status(for: .inputMonitoring) == .granted
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

        let viewModel = OnboardingViewModel(permissionService: permissionService)
        let controller = controllerFactory(viewModel) { [weak self] in
            self?.handleOnboardingFinish(persistCompletionOnFinish: persistCompletionOnFinish)
        }
        self.controller = controller
        controller.present()
    }

    private func handleOnboardingFinish(persistCompletionOnFinish: Bool) {
        controller = nil

        guard persistCompletionOnFinish else { return }

        persistOnboardingCompletion()
        hasCompletedFirstRunOnboarding = true
        startStartupCoordinatorIfNeeded()
    }

    private func startStartupCoordinatorIfNeeded() {
        guard !didStartStartupCoordinator else { return }
        didStartStartupCoordinator = true
        startupCoordinator.start()
    }

    private static func onboardingCompletionPreference(defaults: UserDefaults) -> Preference<Bool> {
        Preference(
            key: "OnboardingCompleted",
            default: false,
            defaults: defaults
        )
    }
}
