import AppKit
import Foundation

typealias CGHotkeyEventTapCallback = @convention(c) (
    CGEventTapProxy,
    CGEventType,
    CGEvent,
    UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>?

internal struct CGHotkeyEventTapContext: Sendable {
    internal final class CallbackBox: @unchecked Sendable {
        let callback: @Sendable (CGEventTapProxy, CGEventType, CGEvent) -> Unmanaged<CGEvent>?

        init(
            callback: @escaping @Sendable (CGEventTapProxy, CGEventType, CGEvent) -> Unmanaged<CGEvent>?
        ) {
            self.callback = callback
        }
    }

    let callbackBox: CallbackBox

    init(
        callback: @escaping @Sendable (CGEventTapProxy, CGEventType, CGEvent) -> Unmanaged<CGEvent>?
    ) {
        self.callbackBox = CallbackBox(callback: callback)
    }

    func makeUserInfo() -> UnsafeMutableRawPointer {
        Unmanaged.passRetained(callbackBox).toOpaque()
    }

    static func releaseUserInfo(_ userInfo: UnsafeMutableRawPointer?) {
        guard let userInfo else {
            return
        }
        Unmanaged<CallbackBox>.fromOpaque(userInfo).release()
    }

    static let tapCallback: CGHotkeyEventTapCallback = { proxy, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let callbackBox = Unmanaged<CallbackBox>.fromOpaque(userInfo).takeUnretainedValue()
        return callbackBox.callback(proxy, type, event)
    }
}

internal enum CGHotkeyEventTapInstaller {
    static func createTap(context: CGHotkeyEventTapContext) -> CFMachPort? {
        _ = context
        return nil
    }
}
