import AppKit
import Combine
import PersonalScribeAudio
import PersonalScribeCore
import PersonalScribeSession
import SwiftUI
import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class SetupViewRenderTests: XCTestCase {
    func testRenderOnboardingStates() async throws {
        guard let outputPath = ProcessInfo.processInfo.environment["NINIMMA_ONBOARDING_RENDER_DIR"],
              !outputPath.isEmpty else {
            throw XCTSkip("Set NINIMMA_ONBOARDING_RENDER_DIR to render onboarding PNGs")
        }
        let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        for scheme in [("dark", ColorScheme.dark), ("light", .light)] {
            for scenario in Scenario.allCases {
                let rootView = makeView(scenario: scenario, colorScheme: scheme.1)
                    .environment(\.colorScheme, scheme.1)
                    .windowTint(.warm)
                    .padding(32)
                    .frame(width: 1_000, height: 760, alignment: .topLeading)
                    .background(
                        PersonalScribeTheme.Palette.for(scheme: scheme.1).appBackground
                    )
                let hostingView = NSHostingView(rootView: rootView)
                let size = CGSize(width: 1_000, height: 760)
                hostingView.frame = NSRect(origin: .zero, size: size)
                hostingView.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(40))
                hostingView.layoutSubtreeIfNeeded()
                let png = try renderPNG(view: hostingView, size: size)
                try png.write(
                    to: outputDirectory.appendingPathComponent(
                        "onboarding-\(scheme.0)-\(scenario.rawValue).png"
                    )
                )
            }
        }
    }

    private func makeView(scenario: Scenario, colorScheme: ColorScheme) -> AnyView {
        let suite = "SetupViewRenderTests.\(scenario.rawValue).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let checklist = HomeChecklistState(defaults: defaults)
        var renderNow = Date(timeIntervalSince1970: 100)
        let flow = SetupFlowState(
            defaults: defaults,
            checklist: checklist,
            now: { renderNow }
        )
        let ready = scenario != .voiceModel
        let service = makeModelService(defaults: defaults, ready: ready)
        let permissions = PermissionsSubTabViewModel(
            permissionService: RenderPermissionService()
        )
        let deviceProvider = RenderInputDeviceProvider()
        let microphone = SetupMicrophoneViewModel(
            inputDeviceProvider: deviceProvider,
            levelMonitor: RenderAudioLevelMonitor(),
            initialSessionSnapshot: scenario == .tryShortcutRecording
                ? SessionSnapshot(sessionState: .capturing, recordingDuration: .seconds(3))
                : SessionSnapshot()
        )
        let model = SetupModelViewModel(
            service: service,
            prepareActiveModel: {},
            showAllModels: {}
        )

        let destinationStep: SetupStep = switch scenario {
        case .permissions, .permissionsSidebar: .permissions
        case .microphone: .microphone
        case .voiceModel: .voiceModel
        case .tryShortcut, .tryShortcutRecording, .tryShortcutSuccess: .tryShortcut
        case .done: .done
        }
        while flow.isOpen && flow.step.rawValue < destinationStep.rawValue {
            flow.advance(satisfaction: .allSatisfied)
        }

        if scenario == .voiceModel,
           let descriptor = service.activeDescriptor(for: .asr) {
            service.updatePreparationProgress(
                ModelDownloadProgress(
                    phase: .downloading,
                    fractionCompleted: 0.46,
                    receivedBytes: 214,
                    expectedBytes: 464
                ),
                for: descriptor
            )
        }
        if scenario == .tryShortcutSuccess {
            flow.beginPractice()
            renderNow = Date(timeIntervalSince1970: 101)
            flow.recordPracticeStopped()
            renderNow = Date(timeIntervalSince1970: 101.8)
            flow.recordPracticePaste("Hello Ninimma, this is my first dictation.")
        }
        if scenario == .done {
            return AnyView(makeDoneView(defaults: defaults, flow: flow, checklist: checklist))
        }

        let setup = SetupView(
            flow: flow,
            permissions: permissions,
            microphone: microphone,
            model: model,
            checklist: checklist,
            onOpenShortcuts: {},
            onClose: {}
        )
        if scenario == .permissionsSidebar {
            return AnyView(
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            PersonalScribeLogoView().frame(width: 24, height: 24)
                            Text(AppBrand.displayName)
                                .font(PersonalScribeTheme.Typography.title.font)
                        }
                        SetupSidebarRow(
                            isActive: true,
                            completedStepCount: flow.completedStepCount,
                            windowTint: .warm,
                            action: {}
                        )
                        Spacer()
                    }
                    .padding(16)
                    .frame(width: PersonalScribeTheme.Layout.sidebarWidth)
                    .background(UnifiedWindowChrome.sidebarBackground(scheme: colorScheme, tint: .warm))
                    setup
                        .padding(32)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            )
        }
        return AnyView(setup)
    }

    private func makeDoneView(
        defaults: UserDefaults,
        flow: SetupFlowState,
        checklist: HomeChecklistState
    ) -> HomeTab {
        let window = MetricsRange.allTime.window(
            anchoredAt: Date(),
            calendar: Calendar(identifier: .gregorian)
        )
        let store = MetricsSnapshotStore(
            reader: SetupRenderMetricsReader(
                snapshot: MetricsSnapshot(
                    rollups: .empty(window: window),
                    recentTranscriptions: [],
                    lastUpdatedAt: Date(),
                    lastRefreshReason: .initialLoad
                )
            ),
            defaults: defaults,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui)
        )
        return HomeTab(
            viewModel: HomeTabViewModel(
                metrics: store,
                defaults: defaults,
                checklist: checklist,
                setupFlow: flow
            )
        )
    }

    private func makeModelService(
        defaults: UserDefaults,
        ready: Bool
    ) -> ActiveModelService {
        let descriptor = BuiltInModelCatalog.parakeetTDT06Bv2
        return ActiveModelService(
            activeIDsPreference: Preference(
                key: ActiveModelService.preferenceKey,
                default: [.asr: descriptor.id],
                defaults: defaults
            ),
            isDownloaded: { $0.id == descriptor.id && ready },
            download: { _, _ in },
            recommendedModels: [.asr: descriptor],
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )
    }

    private func renderPNG(view: NSView, size: CGSize) throws -> Data {
        let scale = 2
        let representation = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width) * scale,
                pixelsHigh: Int(size.height) * scale,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        representation.size = size
        view.cacheDisplay(in: view.bounds, to: representation)
        return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    }

    private enum Scenario: String, CaseIterable {
        case permissions
        case permissionsSidebar = "permissions-sidebar"
        case microphone
        case voiceModel = "voice-model"
        case tryShortcut = "try-shortcut"
        case tryShortcutRecording = "try-shortcut-recording"
        case tryShortcutSuccess = "try-shortcut-success"
        case done
    }
}

@MainActor
private final class RenderPermissionService: PermissionService {
    @Published private(set) var statuses: [Permission: PermissionStatus] = [
        .microphone: .granted,
        .accessibility: .pending,
    ]
    func status(for permission: Permission) -> PermissionStatus { statuses[permission] ?? .pending }
    func request(_ permission: Permission) async -> RequestOutcome {
        RequestOutcome(prompted: false, openedSettings: false, requiresRelaunch: false, finalStatus: status(for: permission))
    }
    func statusSnapshot() -> [Permission: PermissionStatus] { statuses }
    func refresh() {}
    func systemSettingsDeepLink(for permission: Permission) -> URL {
        PermissionServiceAdapter.defaultSystemSettingsDeepLink(for: permission)
    }
}

private final class RenderInputDeviceProvider: AudioInputDeviceProviding, @unchecked Sendable {
    let device = AudioInputDevice(id: "built-in", name: "MacBook Pro Microphone")
    var selectedDeviceID: String? { device.id }
    var systemDefaultDeviceID: String? { device.id }
    func availableDevices() -> [AudioInputDevice] { [device] }
    func selectDevice(id: String?) {}
}

private actor RenderAudioLevelMonitor: AudioLevelMonitoring {
    func start() async throws -> AsyncStream<Float> {
        AsyncStream { $0.yield(0.55) }
    }
    func stop() async {}
}

private struct SetupRenderMetricsReader: MetricsReading {
    let snapshot: MetricsSnapshot
    func loadSnapshot(window: MetricsWindow, recentLimit: Int) async throws -> MetricsSnapshot { snapshot }
    func recentTranscriptions(limit: Int) async throws -> [TranscriptEntry] { [] }
}
