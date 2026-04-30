import SwiftUI
import PersonalScribeCore

/// Shared "Restart required" affordance for Settings sections whose
/// preference changes take effect only on the next launch.
///
/// Renders as an inline caption row (refresh icon + muted text) where
/// the entire row is a tappable button. Tapping invokes `onRelaunch`,
/// which defaults to `AppRelauncher.relaunch()` — the caller can
/// override for tests.
///
/// Intentionally kept trivial. Single caller today (Application card's
/// "Background mode"); the recording-hotkey card used to need it too
/// but live-apply under #017 removed that dependency. Any future
/// preference that requires a restart should set its own view-model
/// `*RestartRequired: Bool` flag and render this view conditionally
/// rather than inventing a one-off footnote.
struct RestartRequiredCaption: View {
    let message: String
    var onRelaunch: @MainActor () -> Void = {
        AppRelauncher.relaunch(
            logger: AppComposition.makeLogger(PersonalScribeLogCategory.app)
        )
    }

    var body: some View {
        Button(action: onRelaunch) {
            Label(message, systemImage: "arrow.clockwise")
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Restart \(AppBrand.displayName) now")
    }
}
