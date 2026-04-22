import Foundation

/// Predicate used to flip the `OnboardingCompleted` first-run flag.
///
/// Ticket #015 (minimal scope): an app that can't hear you (Mic) or
/// receive your global hotkey (Input Monitoring) can't do its job, so
/// both are required before onboarding is considered complete.
/// Accessibility enables paste-at-cursor; without it, transcripts
/// still land on the clipboard — so Accessibility is optional per
/// the ticket body ("optional Accessibility step").
///
/// Pure function by design: no side effects, no dependencies. Callers
/// wire it to a `PermissionService` observer and a UserDefaults-backed
/// `OnboardingState` writer.
public enum OnboardingCompletionPolicy {
    public static func shouldMarkComplete(
        statuses: [Permission: PermissionStatus]
    ) -> Bool {
        statuses[.microphone] == .granted
            && statuses[.inputMonitoring] == .granted
    }
}
