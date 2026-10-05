import Foundation

/// Predicate used to flip the `OnboardingCompleted` first-run flag.
///
/// Microphone is the only required permission. Without Accessibility,
/// transcript delivery falls back to the clipboard and remains usable.
///
/// Pure function by design: no side effects, no dependencies. Callers
/// wire it to a `PermissionService` observer and a UserDefaults-backed
/// `OnboardingState` writer.
public enum OnboardingCompletionPolicy {
    public static func shouldMarkComplete(
        statuses: [Permission: PermissionStatus]
    ) -> Bool {
        statuses[.microphone] == .granted
    }
}
