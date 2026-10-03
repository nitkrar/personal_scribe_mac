import Foundation

/// UserDefaults-backed first-run onboarding completion state.
///
/// Stored under `UserDefaults["OnboardingCompleted"]`. Default is
/// `.incomplete` so first launch presents onboarding until the app records
/// that the window has been dismissed once.
public struct OnboardingState: RawRepresentable, Sendable, Equatable {
    public let rawValue: Bool

    public init(rawValue: Bool) {
        self.rawValue = rawValue
    }

    public static let incomplete = OnboardingState(rawValue: false)
    public static let completed = OnboardingState(rawValue: true)

    public static let setting = SettingKey<Bool>(key: "OnboardingCompleted", default: false)
    public static let `default` = OnboardingState(rawValue: setting.default)
    public static let userDefaultsKey = setting.key

    public static func resolve(from defaults: UserDefaults = .standard) -> OnboardingState {
        OnboardingState(rawValue: setting.resolve(from: defaults))
    }

    public func persist(to defaults: UserDefaults = .standard) {
        Self.setting.persist(rawValue, to: defaults)
    }
}

public typealias PersonalScribeOnboardingCompleted = OnboardingState
