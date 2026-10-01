import Foundation

/// Predicate used to flip the `OnboardingCompleted` first-run flag.
///
/// An app that can't hear you (Mic) or receive your global hotkey
/// (Accessibility — the active CGEventTap receives keyboard events with
/// Accessibility alone; Input Monitoring is not used) can't do its job,
/// so both are required before onboarding is considered complete.
///
/// Pure function by design: no side effects, no dependencies. Callers
/// wire it to a `PermissionService` observer and a UserDefaults-backed
/// `OnboardingState` writer.
public enum OnboardingCompletionPolicy {
    public static func shouldMarkComplete(
        statuses: [Permission: PermissionStatus]
    ) -> Bool {
        statuses[.microphone] == .granted
            && statuses[.accessibility] == .granted
    }
}
