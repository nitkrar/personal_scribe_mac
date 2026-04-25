import Foundation
import PersonalScribeCore

public final class AppKitVisibilityModeProvider: @unchecked Sendable, AppStoreVisibilityModeProviding {
    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter

    public init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    public func currentVisibilityMode() -> AppStoreVisibilityMode {
        Self.map(PillVisibility.resolve(from: defaults))
    }

    public func visibilityModeStream() -> AsyncStream<AppStoreVisibilityMode> {
        let notificationCenter = self.notificationCenter

        return AsyncStream { continuation in
            continuation.yield(currentVisibilityMode())
            let observerToken = ObserverToken(notificationCenter.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: defaults,
                queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                continuation.yield(self.currentVisibilityMode())
            })

            continuation.onTermination = { _ in
                notificationCenter.removeObserver(observerToken.value)
            }
        }
    }

    private static func map(_ mode: PillVisibility) -> AppStoreVisibilityMode {
        switch mode {
        case .alwaysOn:
            return .alwaysOn
        case .autoShow:
            return .autoShow
        case .hidden:
            return .hidden
        }
    }
}

private final class ObserverToken: @unchecked Sendable {
    let value: NSObjectProtocol

    init(_ value: NSObjectProtocol) {
        self.value = value
    }
}
