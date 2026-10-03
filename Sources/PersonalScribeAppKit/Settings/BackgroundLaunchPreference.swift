import Foundation
import PersonalScribeCore

/// User-selectable "Background mode" preference. When `true`, the app
/// runs as a menu-bar-only accessory (`.accessory` activation policy) —
/// no Dock icon, no Cmd+Tab entry, no Force Quit entry. The pill
/// overlay and any explicitly-opened windows (Settings, Transcriptions)
/// still render normally. When `false` (default), the app is a regular
/// macOS app present in the Dock / Cmd+Tab / Force Quit alongside its
/// menu-bar icon.
///
/// Replaced the earlier `ShowInDockPreference` on 2026-04-24 after the
/// prior default (`LSUIElement: true` in `Info.plist`, never flipped at
/// startup) produced a state where a fresh install launched with no
/// Dock icon, no Cmd+Tab entry, and was only reachable via the menu bar.
/// Users who hide the menu bar could not find the app at all.
///
/// Semantic changes vs. `ShowInDockPreference`:
/// - Default is `false` (shown in Dock by default) — fresh installs are
///   always discoverable.
/// - The setter does NOT apply the activation policy live. Changing the
///   toggle displays a "Restart required" note; the policy is applied at
///   the NEXT app launch from this preference. This avoids mid-session
///   weirdness (Dock icon appearing/disappearing while a window is open).
/// - Read at app startup in `PersonalScribeAppMain` and applied via
///   `NSApp.setActivationPolicy(.accessory)` if true. Not applied if
///   false — the default activation policy from `Info.plist` is
///   `.regular`.
public enum BackgroundLaunchPreference: StoredPreference {
    public static let setting = SettingKey<Bool>(key: "BackgroundMode", default: false)
}
