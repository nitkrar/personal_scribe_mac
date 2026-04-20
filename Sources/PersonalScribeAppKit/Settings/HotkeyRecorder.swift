import AppKit
import SwiftUI
import PersonalScribeCore

@MainActor
public struct HotkeyRecorder: View {
    @StateObject private var model: HotkeyRecorderModel

    private let currentPreference: HotkeyPreference

    public init(
        currentPreference: HotkeyPreference,
        onConfirm: @escaping @MainActor (HotkeyPreference) -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        self.currentPreference = currentPreference
        _model = StateObject(
            wrappedValue: HotkeyRecorderModel(
                onConfirm: onConfirm,
                onCancel: onCancel
            )
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Change Recording Shortcut")
                    .font(PersonalScribeTheme.Typography.display.font)

                Text("Press the new shortcut. Escape cancels; Set confirms the latest valid capture.")
                    .font(PersonalScribeTheme.Typography.body.font)
                    .foregroundStyle(.secondary)
            }

            SettingsCard {
                SettingsMetadataRow(
                    title: "Current",
                    value: HotkeyShortcutFormatter.displayString(for: currentPreference),
                    monospaced: true
                )

                Divider()

                SettingsMetadataRow(
                    title: "Captured",
                    value: model.captureSummary,
                    monospaced: true
                )

                if let rejectionMessage = model.rejectionMessage {
                    Divider()

                    Label(rejectionMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: SettingsLayout.inlineSpacing) {
                Spacer(minLength: 0)

                Button("Cancel") {
                    model.cancel()
                }

                Button("Set") {
                    model.confirm()
                }
                .disabled(model.canConfirm == false)
            }
        }
        .padding(PersonalScribeTheme.Spacing.windowPadding)
        .frame(minWidth: 420, alignment: .leading)
        .background(
            HotkeyRecorderEventMonitor { event in
                (try? model.handle(event: event)) ?? false
            }
        )
    }
}

@MainActor
final class HotkeyRecorderModel: ObservableObject {
    enum CaptureResult: Equatable {
        case idle
        case captured(HotkeyPreference)
        case rejected(reason: String)
    }

    private static let modifierMask: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option,
        .shift,
    ]
    private static let escapeKeyCode: UInt16 = 53
    private static let spaceKeyCode: UInt16 = 49
    private static let tabKeyCode: UInt16 = 48

    @Published private(set) var captureResult: CaptureResult = .idle

    private let onConfirm: @MainActor (HotkeyPreference) -> Void
    private let onCancel: @MainActor () -> Void

    init(
        onConfirm: @escaping @MainActor (HotkeyPreference) -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var canConfirm: Bool {
        if case .captured = captureResult {
            return true
        }
        return false
    }

    var captureSummary: String {
        switch captureResult {
        case .idle:
            return "Press a shortcut"
        case let .captured(preference):
            return HotkeyShortcutFormatter.displayString(for: preference)
        case .rejected:
            return "No valid shortcut captured"
        }
    }

    var rejectionMessage: String? {
        guard case let .rejected(reason) = captureResult else {
            return nil
        }
        return reason
    }

    @discardableResult
    func handle(event: NSEvent) throws -> Bool {
        switch event.type {
        case .flagsChanged:
            captureModifierChange(event)
            return true
        case .keyDown:
            if event.keyCode == Self.escapeKeyCode {
                cancel()
                return true
            }

            captureKeyPress(event)
            return true
        default:
            return false
        }
    }

    func confirm() {
        guard case let .captured(preference) = captureResult else {
            return
        }

        onConfirm(preference)
    }

    func cancel() {
        onCancel()
    }

    private func captureModifierChange(_ event: NSEvent) {
        let modifiers = normalizedModifierFlags(event.modifierFlags)
        guard modifiers.isEmpty == false else {
            return
        }

        if modifiers == [.shift] {
            captureResult = .rejected(
                reason: "Modifier-only shortcuts are not supported; plain Shift cannot be used."
            )
            return
        }

        captureResult = .rejected(reason: "Modifier-only shortcuts are not supported.")
    }

    private func captureKeyPress(_ event: NSEvent) {
        let preference = HotkeyPreference(
            keyCode: event.keyCode,
            tapCount: 1,
            modifiers: normalizedModifierFlags(event.modifierFlags).rawValue
        )

        if let rejectionReason = Self.rejectionReason(
            for: preference,
            charactersIgnoringModifiers: normalizedCharacters(for: event)
        ) {
            captureResult = .rejected(reason: rejectionReason)
            return
        }

        captureResult = .captured(preference)
    }

    private func normalizedModifierFlags(_ modifierFlags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        modifierFlags.intersection(Self.modifierMask)
    }

    private func normalizedCharacters(for event: NSEvent) -> String {
        (event.charactersIgnoringModifiers ?? event.characters ?? "").lowercased()
    }

    private static func rejectionReason(
        for preference: HotkeyPreference,
        charactersIgnoringModifiers: String
    ) -> String? {
        let modifiers = preference.modifierFlags

        if modifiers == [.command], preference.keyCode == spaceKeyCode {
            return "Cmd+Space is reserved by macOS and cannot be overridden here."
        }

        if modifiers == [.command], preference.keyCode == tabKeyCode {
            return "Cmd+Tab is reserved by the app switcher and cannot be used."
        }

        if modifiers == [.command, .shift], preference.keyCode == spaceKeyCode {
            return "Cmd+Shift+Space is reserved by macOS and cannot be used."
        }

        if modifiers == [.command], charactersIgnoringModifiers == "q" {
            return "Cmd+Q is reserved by Quit."
        }

        if modifiers == [.command], charactersIgnoringModifiers == "w" {
            return "Cmd+W is reserved by Close Window."
        }

        if modifiers == [.command], charactersIgnoringModifiers == "c" {
            return "Cmd+C is reserved by Copy."
        }

        if modifiers == [.command], charactersIgnoringModifiers == "v" {
            return "Cmd+V is reserved by Paste."
        }

        if modifiers == [.command], charactersIgnoringModifiers == "x" {
            return "Cmd+X is reserved by Cut."
        }

        return nil
    }
}

enum HotkeyShortcutFormatter {
    private static let displayKeyLabels: [UInt16: String] = [
        0: "A",
        1: "S",
        2: "D",
        3: "F",
        4: "H",
        5: "G",
        6: "Z",
        7: "X",
        8: "C",
        9: "V",
        11: "B",
        12: "Q",
        13: "W",
        14: "E",
        15: "R",
        16: "Y",
        17: "T",
        18: "1",
        19: "2",
        20: "3",
        21: "4",
        22: "6",
        23: "5",
        24: "=",
        25: "9",
        26: "7",
        27: "-",
        28: "8",
        29: "0",
        30: "]",
        31: "O",
        32: "U",
        33: "[",
        34: "I",
        35: "P",
        36: "Return",
        37: "L",
        38: "J",
        39: "'",
        40: "K",
        41: ";",
        42: "\\",
        43: ",",
        44: "/",
        45: "N",
        46: "M",
        47: ".",
        48: "Tab",
        49: "Space",
        50: "`",
        51: "Delete",
        53: "Esc",
        58: "⌥",
        61: "⌥",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        105: "F13",
        106: "F16",
        107: "F14",
        109: "F10",
        111: "F12",
        113: "F15",
        114: "Help",
        115: "Home",
        116: "Page Up",
        117: "Forward Delete",
        118: "F4",
        119: "End",
        120: "F2",
        121: "Page Down",
        122: "F1",
        123: "Left Arrow",
        124: "Right Arrow",
        125: "Down Arrow",
        126: "Up Arrow",
    ]

    static func displayString(for preference: HotkeyPreference) -> String {
        if
            preference.tapCount == 2,
            preference.modifierFlags.isEmpty,
            isOptionKeyCode(preference.keyCode)
        {
            return "Double-tap ⌥"
        }

        let modifiers = modifierString(for: preference.modifierFlags)
        let keyLabel = displayKeyLabels[preference.keyCode] ?? "Key \(preference.keyCode)"

        if preference.tapCount > 1 {
            let prefix = "\(preference.tapCount)x "
            return prefix + (modifiers.isEmpty ? keyLabel : modifiers + keyLabel)
        }

        return modifiers.isEmpty ? keyLabel : modifiers + keyLabel
    }

    private static func modifierString(for modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""

        if modifiers.contains(.command) {
            result += "⌘"
        }
        if modifiers.contains(.option) {
            result += "⌥"
        }
        if modifiers.contains(.control) {
            result += "⌃"
        }
        if modifiers.contains(.shift) {
            result += "⇧"
        }

        return result
    }

    private static func isOptionKeyCode(_ keyCode: UInt16) -> Bool {
        keyCode == 58 || keyCode == 61
    }
}

private struct HotkeyRecorderEventMonitor: View {
    let onEvent: (NSEvent) -> Bool

    @State private var monitor: Any?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                guard monitor == nil else {
                    return
                }

                monitor = NSEvent.addLocalMonitorForEvents(
                    matching: [.flagsChanged, .keyDown]
                ) { event in
                    onEvent(event) ? nil : event
                }
            }
            .onDisappear {
                guard let monitor else {
                    return
                }

                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
    }
}
