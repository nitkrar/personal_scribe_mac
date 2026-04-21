import Combine
import Foundation
import PersonalScribeCore

/// View model for the sidebar microphone footer (`#008`).
///
/// Renders the currently-configured input device name in the
/// unified-window sidebar footer — e.g. "MacBook Pro Microphone",
/// "AirPods Pro" — with live updates when the user changes the
/// default input via the menu-bar Microphone submenu or when the
/// selected device is unplugged.
///
/// Design notes
/// ------------
/// The `AudioInputDeviceProviding` protocol is deliberately pull-based
/// (`Sources/PersonalScribeCore/Audio/AudioInputDevice.swift:43`): its
/// docstring says "callers are expected to re-query `availableDevices()`
/// on each menu open … no observer plumbing required." The menu-bar
/// Microphone submenu (`StatusItemController.rebuildMenu`) honors that
/// by re-querying inside `menuNeedsUpdate(_:)`.
///
/// The sidebar footer cannot rely on a re-query trigger the same way
/// a menu-open event fires, so this view model layers a thin
/// observation on top of the pull protocol:
///
///   1. `UserDefaults.didChangeNotification` on the same defaults
///      instance the menu-bar submenu writes into. When the user picks
///      a device from the submenu (`AVFoundationInputDeviceProvider
///      .selectDevice(id:)` writes `SelectedAudioInputDeviceID`), the
///      defaults system posts the notification and the footer
///      re-reads the provider — matching the pattern
///      `UnifiedWindowController` already uses for WindowTint.
///
///   2. A public `refresh()` call, invoked by
///      `UnifiedWindowController` on window show / key-state changes,
///      which covers hotplug (USB unplug) without requiring the view
///      model to import AVFoundation just for the
///      `AVCaptureDeviceWasDisconnectedNotification` name.
///
/// The provider is not consulted on every render; the published
/// `currentDeviceName` is the cached result of the last pull and is
/// only republished when the value actually changes (Combine drops
/// duplicates via the `didSet` guard).
@MainActor
public final class MicrophoneFooterViewModel: ObservableObject {
    /// Human-readable device name to render, or `nil` when there is no
    /// persisted selection or the previously-selected device has
    /// disappeared from `availableDevices()`. The view falls back to a
    /// generic placeholder ("No input device") in the nil case.
    @Published public private(set) var currentDeviceName: String?

    private let provider: any AudioInputDeviceProviding
    private let defaults: UserDefaults
    private var defaultsObserver: NSObjectProtocol?

    public init(
        provider: any AudioInputDeviceProviding,
        defaults: UserDefaults = .standard
    ) {
        self.provider = provider
        self.defaults = defaults
        self.currentDeviceName = Self.resolveCurrentDeviceName(provider: provider)

        // Observe the menu-bar submenu writing a new selection into
        // `SelectedAudioInputDeviceID` on the same defaults instance.
        // `UserDefaults.didChangeNotification` fires synchronously on
        // `set(_:forKey:)` for in-process changes, so the sidebar
        // reflects the new device within a run-loop turn.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            // The `queue: .main` argument guarantees the observer
            // block runs on the main queue, so MainActor isolation is
            // satisfied at runtime. Hopping via `Task { @MainActor }`
            // gives the compiler explicit evidence without changing
            // dispatch semantics.
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    isolated deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    /// Re-pull the provider and republish `currentDeviceName` if the
    /// resolved name differs from the currently-published value.
    /// Callers invoke this on any external trigger that might have
    /// changed the device landscape — window did-become-key, periodic
    /// polling, or a hotplug notification forwarded by the caller.
    public func refresh() {
        let resolved = Self.resolveCurrentDeviceName(provider: provider)
        if resolved != currentDeviceName {
            currentDeviceName = resolved
        }
    }

    // MARK: - Resolution

    /// Returns the display name of the currently-selected device if it
    /// is still present in `availableDevices()`; returns `nil` when
    /// there is no selection or the previously-selected device has
    /// disappeared (e.g. unplugged USB mic). Mirrors
    /// `StatusItemMenuModel.currentInputDeviceName(in:selectedID:)`.
    private static func resolveCurrentDeviceName(
        provider: any AudioInputDeviceProviding
    ) -> String? {
        guard let selectedID = provider.selectedDeviceID else { return nil }
        let devices = provider.availableDevices()
        return devices.first(where: { $0.id == selectedID })?.name
    }
}
