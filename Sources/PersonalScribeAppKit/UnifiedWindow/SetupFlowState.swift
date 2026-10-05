import Foundation
import PersonalScribeCore

enum SetupStep: Int, CaseIterable, Sendable {
    case permissions
    case microphone
    case voiceModel
    case tryShortcut
    case done

    var title: String {
        switch self {
        case .permissions: "Permissions"
        case .microphone: "Microphone"
        case .voiceModel: "Voice model"
        case .tryShortcut: "Try it"
        case .done: "Done"
        }
    }
}

struct SetupSatisfaction: Equatable, Sendable {
    var permissionsGranted: Bool
    var modelDownloaded: Bool
    var shortcutTried: Bool

    static let allSatisfied = SetupSatisfaction(
        permissionsGranted: true,
        modelDownloaded: true,
        shortcutTried: true
    )
}

struct SetupPracticeResult: Equatable, Sendable {
    let wordCount: Int
    let elapsedSeconds: TimeInterval
}

@MainActor
final class SetupFlowState: ObservableObject {
    @Published private(set) var isOpen: Bool
    @Published private(set) var step: SetupStep = .permissions
    @Published private(set) var isCompletionBannerVisible = false
    @Published private(set) var practiceResult: SetupPracticeResult?
    @Published private(set) var practiceText = ""
    @Published private(set) var satisfaction: SetupSatisfaction

    private static let shortcutTriedKey = "SetupShortcutTried"

    private let defaults: UserDefaults
    private let checklist: HomeChecklistState
    private let now: () -> Date
    private var practiceStoppedAt: Date?

    init(
        defaults: UserDefaults = .standard,
        checklist: HomeChecklistState? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.checklist = checklist ?? HomeChecklistState(defaults: defaults)
        self.now = now
        self.isOpen = OnboardingState.resolve(from: defaults) == .incomplete
        self.satisfaction = SetupSatisfaction(
            permissionsGranted: false,
            modelDownloaded: false,
            shortcutTried: defaults.bool(forKey: Self.shortcutTriedKey)
        )
    }

    var canGoBack: Bool {
        isOpen && step.rawValue > SetupStep.permissions.rawValue
    }

    var completedStepCount: Int {
        step.rawValue
    }

    func advance(satisfaction latest: SetupSatisfaction) {
        updateSatisfaction(latest)
        guard isOpen else { return }
        guard step != .tryShortcut else {
            closeSetup(showCompletionBanner: true)
            return
        }
        guard let next = SetupStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func goBack() {
        guard canGoBack,
              let previous = SetupStep(rawValue: step.rawValue - 1) else {
            return
        }
        step = previous
    }

    func skip(satisfaction latest: SetupSatisfaction) {
        updateSatisfaction(latest)
        closeSetup(showCompletionBanner: false)
    }

    func reopen(at step: SetupStep = .permissions) {
        guard step != .done else { return }
        self.step = step
        isOpen = true
    }

    func dismissCompletionBanner() {
        isCompletionBannerVisible = false
    }

    func beginPractice() {
        practiceStoppedAt = nil
        practiceText = ""
        practiceResult = nil
    }

    func updatePracticeText(_ text: String) {
        practiceText = text
    }

    func recordPracticeStopped() {
        practiceStoppedAt = now()
    }

    func recordPracticePaste(_ pastedText: String) {
        guard practiceResult == nil else { return }
        guard let practiceStoppedAt else { return }
        self.practiceStoppedAt = nil
        let words = pastedText.split(whereSeparator: \Character.isWhitespace)
        guard !words.isEmpty else { return }
        let elapsed = max(0, now().timeIntervalSince(practiceStoppedAt))
        practiceResult = SetupPracticeResult(
            wordCount: words.count,
            elapsedSeconds: elapsed
        )
        defaults.set(true, forKey: Self.shortcutTriedKey)
        satisfaction.shortcutTried = true
        checklist.complete(.tryShortcut)
    }

    func tryPracticeAgain() {
        beginPractice()
    }

    private func updateSatisfaction(_ latest: SetupSatisfaction) {
        satisfaction = SetupSatisfaction(
            permissionsGranted: latest.permissionsGranted,
            modelDownloaded: latest.modelDownloaded,
            shortcutTried: latest.shortcutTried || satisfaction.shortcutTried
        )
        checklist.refreshSetupSatisfaction(
            permissionsGranted: satisfaction.permissionsGranted,
            modelDownloaded: satisfaction.modelDownloaded,
            shortcutTried: satisfaction.shortcutTried
        )
    }

    private func closeSetup(showCompletionBanner: Bool) {
        if !satisfaction.permissionsGranted {
            checklist.markApplicable(.grantPermissions)
        }
        if !satisfaction.modelDownloaded {
            checklist.markApplicable(.downloadModel)
        }
        if !satisfaction.shortcutTried {
            checklist.markApplicable(.tryShortcut)
        }
        step = .done
        isOpen = false
        isCompletionBannerVisible = showCompletionBanner
    }
}
