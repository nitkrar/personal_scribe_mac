import Foundation
import PersonalScribeCore

@MainActor
final class AppStartupCoordinator {
    typealias Sleep = @Sendable (Duration) async throws -> Void
    typealias HotkeyStarter = @MainActor @Sendable () -> Void

    private let hotkeyDelay: Duration
    private let prepareDelay: Duration
    private let startHotkeyMonitor: HotkeyStarter
    private let prepareTranscriber: @Sendable () async -> Void
    private let sleep: Sleep
    private let logger: PersonalScribeLogger

    private var startupTask: Task<Void, Never>?

    init(
        hotkeyDelay: Duration = .milliseconds(250),
        prepareDelay: Duration = .seconds(1),
        startHotkeyMonitor: @escaping HotkeyStarter,
        prepareTranscriber: @escaping @Sendable () async -> Void,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.app)
    ) {
        self.hotkeyDelay = hotkeyDelay
        self.prepareDelay = prepareDelay
        self.startHotkeyMonitor = startHotkeyMonitor
        self.prepareTranscriber = prepareTranscriber
        self.sleep = sleep
        self.logger = logger
    }

    func start() {
        guard startupTask == nil else {
            return
        }

        let startHotkeyMonitor = self.startHotkeyMonitor
        // `.userInitiated` (was `.background`) so the eager prefetch of
        // the voice model gets scheduler priority comparable to app
        // launch. At `.background`, prefetch would often not progress
        // until the user had already hit the hotkey, defeating the
        // purpose. See `plans/backlog/model-download-ux-bug-research.md`
        // (session-start race).
        startupTask = Task(priority: .userInitiated) { [hotkeyDelay, prepareDelay, sleep, prepareTranscriber, logger] in
            do {
                try await sleep(hotkeyDelay)
            } catch is CancellationError {
                return
            } catch {
                logger.error("Hotkey startup delay failed", error: error)
                return
            }

            await MainActor.run {
                startHotkeyMonitor()
            }

            do {
                try await sleep(prepareDelay)
            } catch is CancellationError {
                return
            } catch {
                logger.error("Model preparation delay failed", error: error)
                return
            }

            await prepareTranscriber()
        }
    }

    deinit {
        startupTask?.cancel()
    }
}
