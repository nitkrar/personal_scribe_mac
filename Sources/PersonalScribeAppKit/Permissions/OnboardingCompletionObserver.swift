import Combine
import Foundation
import PersonalScribeCore

/// Watches a `PermissionService` and flips the `OnboardingCompleted`
/// UserDefault to `true` the first time the permission snapshot
/// satisfies `OnboardingCompletionPolicy`. After the flip, the
/// observer stops and further permission changes never re-write the
/// default — so a later revoke in System Settings doesn't re-trigger
/// the first-run auto-open flow.
///
/// Ticket #015 (minimal scope): fills the gap where `OnboardingCompleted`
/// was read but never written. Users who granted perms via the
/// Settings → Permissions deep-link stayed stuck in "fresh install"
/// mode forever; the unified window auto-opened to Settings on every
/// launch. This observer closes the loop.
///
/// Lifetime: owned by `PersonalScribeAppMain`. Start is called at
/// init; there's no stop — the observer self-terminates on first
/// completion.
@MainActor
public final class OnboardingCompletionObserver {
    private let snapshotProvider: @MainActor () -> [Permission: PermissionStatus]
    private let subscribe: (@escaping @MainActor () -> Void) -> AnyCancellable
    private let defaults: UserDefaults
    private var observation: AnyCancellable?

    public init<Service: PermissionService>(
        permissionService: Service,
        defaults: UserDefaults = .standard
    ) {
        // Capture generic `objectWillChange` at construction time so
        // downstream logic doesn't need to reason about the erased
        // `any PermissionService` publisher type. `PermissionsSubTabViewModel`
        // uses the same generic-capture pattern for the same reason.
        self.snapshotProvider = { permissionService.statusSnapshot() }
        self.subscribe = { handler in
            permissionService.objectWillChange.sink { _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        handler()
                    }
                }
            }
        }
        self.defaults = defaults
    }

    public func start() {
        // Check the current snapshot first — covers the re-install /
        // "perms granted before launch" case without needing a
        // published update to fire.
        if evaluateAndFlipIfNeeded() {
            return
        }

        // Subscribe to future updates. `objectWillChange` fires before
        // `statuses` mutates; defer the snapshot read to the next
        // runloop tick to pick up the post-change value (same pattern
        // as PermissionsSubTabViewModel + PermissionServiceAdapter).
        observation = subscribe { [weak self] in
            self?.evaluateAndFlipIfNeeded()
        }
    }

    /// Returns `true` when the flag was flipped (or was already
    /// `completed` on entry — either way, observation can stop).
    @discardableResult
    private func evaluateAndFlipIfNeeded() -> Bool {
        // If the flag is already completed, drop the subscription so
        // subsequent revokes don't churn the default.
        if OnboardingState.resolve(from: defaults) == .completed {
            observation = nil
            return true
        }

        let snapshot = snapshotProvider()
        guard OnboardingCompletionPolicy.shouldMarkComplete(statuses: snapshot) else {
            return false
        }

        OnboardingState.completed.persist(to: defaults)
        observation = nil
        return true
    }
}
