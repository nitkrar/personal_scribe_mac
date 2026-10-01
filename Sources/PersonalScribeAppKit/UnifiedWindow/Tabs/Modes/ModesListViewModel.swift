import Combine
import Foundation
import PersonalScribeCore
import PersonalScribeSession

/// View-model for the modes editor list (#089). Subscribes to the
/// registry's broadcast streams + `ActiveModelService.downloadStates`
/// and republishes a flat snapshot the SwiftUI list renders against.
@MainActor
final class ModesListViewModel: ObservableObject {
    @Published private(set) var customModes: [WorkflowMode] = []
    @Published private(set) var defaultModeID: String? = nil
    @Published private(set) var currentModeID: String? = nil
    @Published private(set) var validityByID: [String: ModeRowValidity] = [:]
    @Published var lastError: String? = nil

    private let registry: WorkflowModeRegistry
    private let modelService: ActiveModelService
    private var customModesTask: Task<Void, Never>?
    private var defaultModeTask: Task<Void, Never>?
    private var currentModeTask: Task<Void, Never>?
    private var modelStateCancellable: AnyCancellable?

    init(
        registry: WorkflowModeRegistry,
        modelService: ActiveModelService
    ) {
        self.registry = registry
        self.modelService = modelService
        self.customModes = registry.customModes
        self.defaultModeID = registry.defaultMode.id == WorkflowMode.dictation.id
            ? nil
            : registry.defaultMode.id
        self.currentModeID = registry.currentMode.id
        recomputeValidity()
    }

    func startObserving() {
        guard customModesTask == nil else { return }

        let registry = self.registry
        customModesTask = Task { @MainActor in
            for await modes in registry.customModesStream() {
                self.customModes = modes
                self.recomputeValidity()
            }
        }
        defaultModeTask = Task { @MainActor in
            for await mode in registry.defaultModeStream() {
                // Only treat as a real default if it resolves to a
                // custom mode; the dictation fallback shows as no
                // default selected (no star filled).
                self.defaultModeID = mode.id == WorkflowMode.dictation.id
                    ? nil
                    : mode.id
            }
        }
        currentModeTask = Task { @MainActor in
            for await mode in registry.currentModeStream() {
                self.currentModeID = mode.id
            }
        }
        modelStateCancellable = modelService.objectWillChange.sink { [weak self] _ in
            // `objectWillChange` fires before mutation; defer the
            // recompute to next runloop so reads see the new state.
            DispatchQueue.main.async {
                self?.recomputeValidity()
            }
        }
    }

    func stopObserving() {
        customModesTask?.cancel(); customModesTask = nil
        defaultModeTask?.cancel(); defaultModeTask = nil
        currentModeTask?.cancel(); currentModeTask = nil
        modelStateCancellable = nil
    }

    deinit {
        customModesTask?.cancel()
        defaultModeTask?.cancel()
        currentModeTask?.cancel()
    }

    func setDefault(_ mode: WorkflowMode) {
        do {
            try registry.setDefault(id: mode.id)
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    func delete(_ mode: WorkflowMode) {
        do {
            try registry.deleteCustom(id: mode.id)
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    func reorder(from source: IndexSet, to destination: Int) {
        guard let firstSource = source.first else { return }
        let dest: Int = {
            // SwiftUI passes a destination one past the moved item;
            // convert to the registry's "to" index.
            return destination > firstSource ? destination - 1 : destination
        }()
        do {
            try registry.reorderCustom(from: firstSource, to: dest)
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    @discardableResult
    func create(preset: Preset) -> WorkflowMode? {
        let name = registry.nextAvailableName(preset.displayName)
        let mode = preset.materialize(name: name)
        do {
            try registry.saveCustom(mode)
            lastError = nil
            return mode
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return nil
        }
    }

    private func recomputeValidity() {
        let kinds = modelService.availableKinds()
        let descriptors = modelService.registeredModels
        var next: [String: ModeRowValidity] = [:]
        for mode in customModes {
            do {
                try WorkflowModeValidator.validate(
                    mode,
                    availableKinds: kinds,
                    registeredDescriptors: descriptors
                )
                next[mode.id] = .valid
            } catch {
                next[mode.id] = .invalid(reason: message(for: error))
            }
        }
        validityByID = next
    }

    private func message(for error: Error) -> String {
        WorkflowModeValidationMessage.text(for: error) { [modelService] kind in
            modelService.hasDownloadedModel(for: kind)
        }
    }
}
