import Foundation
import PersonalScribeAudio
import PersonalScribeCore

@MainActor
final class SetupMicrophoneViewModel: ObservableObject {
    @Published private(set) var devices: [AudioInputDevice] = []
    @Published private(set) var selectedDeviceID: String?
    @Published private(set) var level: Float = 0
    @Published private(set) var isMonitoring = false

    private let inputDeviceProvider: any AudioInputDeviceProviding
    private let levelMonitor: any AudioLevelMonitoring
    private var levelTask: Task<Void, Never>?

    init(
        inputDeviceProvider: any AudioInputDeviceProviding,
        levelMonitor: any AudioLevelMonitoring
    ) {
        self.inputDeviceProvider = inputDeviceProvider
        self.levelMonitor = levelMonitor
    }

    func appear() async {
        devices = inputDeviceProvider.availableDevices()
        selectedDeviceID = inputDeviceProvider.effectiveDeviceID
        await startMonitoring()
    }

    func disappear() async {
        levelTask?.cancel()
        levelTask = nil
        await levelMonitor.stop()
        isMonitoring = false
        level = 0
    }

    func recordingDidStart() async {
        await disappear()
    }

    func selectDevice(id: String?) async {
        inputDeviceProvider.selectDevice(id: id)
        selectedDeviceID = inputDeviceProvider.effectiveDeviceID
        await disappear()
        await startMonitoring()
    }

    private func startMonitoring() async {
        do {
            let stream = try await levelMonitor.start()
            isMonitoring = true
            levelTask = Task { @MainActor [weak self] in
                for await level in stream {
                    guard !Task.isCancelled else { return }
                    self?.level = level
                }
            }
        } catch {
            isMonitoring = false
            level = 0
        }
    }
}
