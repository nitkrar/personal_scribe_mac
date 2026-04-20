import Foundation

/// UserDefaults-backed first-run onboarding completion state.
///
/// Stored under `UserDefaults["SeshatOnboardingCompleted"]`. Default is
/// `.incomplete` so first launch presents onboarding until the app records
/// that the window has been dismissed once.
public struct OnboardingState: RawRepresentable, Sendable, Equatable {
    public let rawValue: Bool

    public init(rawValue: Bool) {
        self.rawValue = rawValue
    }

    public static let incomplete = OnboardingState(rawValue: false)
    public static let completed = OnboardingState(rawValue: true)

    public static let `default`: OnboardingState = .incomplete
    public static let userDefaultsKey = "SeshatOnboardingCompleted"

    public static func resolve(from defaults: UserDefaults = .standard) -> OnboardingState {
        guard let value = defaults.object(forKey: userDefaultsKey) as? Bool else {
            return .default
        }

        return value ? .completed : .incomplete
    }

    public func persist(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.userDefaultsKey)
    }
}

public typealias PersonalScribeOnboardingCompleted = OnboardingState
