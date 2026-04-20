import Combine
import Foundation
import PersonalScribeCore
import PersonalScribeSession

public struct AppKitActiveModeProvider: AppStoreActiveModeProviding, @unchecked Sendable {
    private let state: StateBox

    @MainActor
    public init() {
        self.init(modelService: AppComposition.modelService)
    }

    @MainActor
    public init(modelService: DefaultModelService) {
        let state = StateBox(
            currentMode: Self.modeDescriptor(for: modelService.activeDescriptor)
        )
        let observation = modelService.$activeDescriptor.sink { [weak state] descriptor in
            state?.publish(Self.modeDescriptor(for: descriptor))
        }
        state.storeObservation(observation)
        self.state = state
    }

    public func currentActiveMode() -> ModeDescriptor? {
        state.loadCurrentMode()
    }

    public func activeModeStream() -> AsyncStream<ModeDescriptor?> {
        let state = self.state
        let id = UUID()

        return AsyncStream { continuation in
            state.register(continuation, id: id)
            continuation.onTermination = { _ in
                state.removeContinuation(id: id)
            }
        }
    }

    private static func modeDescriptor(
        for activeDescriptor: ActiveModelDescriptor
    ) -> ModeDescriptor? {
        ModeRegistry.all.first {
            $0.voiceModelID == activeDescriptor.voiceModel.id &&
            $0.aiModelID == activeDescriptor.aiModelID
        }
    }
}

private final class StateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var currentMode: ModeDescriptor?
    private var continuations: [UUID: AsyncStream<ModeDescriptor?>.Continuation] = [:]
    private var observation: AnyCancellable?

    init(currentMode: ModeDescriptor?) {
        self.currentMode = currentMode
    }

    func loadCurrentMode() -> ModeDescriptor? {
        lock.lock()
        defer { lock.unlock() }
        return currentMode
    }

    func register(
        _ continuation: AsyncStream<ModeDescriptor?>.Continuation,
        id: UUID
    ) {
        lock.lock()
        continuations[id] = continuation
        continuation.yield(currentMode)
        lock.unlock()
    }

    func removeContinuation(id: UUID) {
        lock.lock()
        continuations[id] = nil
        lock.unlock()
    }

    func publish(_ mode: ModeDescriptor?) {
        lock.lock()
        currentMode = mode
        for continuation in continuations.values {
            continuation.yield(mode)
        }
        lock.unlock()
    }

    func storeObservation(_ observation: AnyCancellable) {
        lock.lock()
        self.observation = observation
        lock.unlock()
    }

    deinit {
        lock.lock()
        let continuations = Array(continuations.values)
        let observation = self.observation
        lock.unlock()

        observation?.cancel()
        for continuation in continuations {
            continuation.finish()
        }
    }
}
