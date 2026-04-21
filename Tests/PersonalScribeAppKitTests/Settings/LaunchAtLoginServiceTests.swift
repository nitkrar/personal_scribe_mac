import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

// Tests for #005 — Launch-at-Login status feedback.
//
// Rationale: SMAppService.mainApp cannot be exercised directly from
// XCTest (it would mutate the real login-items registry and in a bundle
// that isn't the signed .app it throws). Instead, GeneralTabViewModel
// takes `LaunchAtLoginServicing`, and these tests drive a fake to prove:
//
//   * init seeds launchAtLogin from the service
//   * setLaunchAtLogin(true)  → register()
//   * setLaunchAtLogin(false) → unregister()
//   * a throwing register() snaps launchAtLogin back to the service's
//     real `isEnabled` (which will be false since the registration
//     didn't take) — this is what drives the red dot in the UI
//   * refreshLaunchAtLoginStatus() re-reads the service (GeneralTab
//     calls this on appear so the dot picks up out-of-band changes)
@MainActor
final class LaunchAtLoginServiceTests: XCTestCase {
    private let suiteName = "LaunchAtLoginServiceTests"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testViewModelSeedsFromService() {
        let fake = FakeLaunchAtLoginService()
        fake.isEnabled = true

        let viewModel = GeneralTabViewModel(
            defaults: isolatedDefaults(),
            launchAtLoginService: fake
        )

        XCTAssertTrue(viewModel.launchAtLogin)
    }

    func testViewModelSeedsFromServiceWhenDisabled() {
        let fake = FakeLaunchAtLoginService()
        fake.isEnabled = false

        let viewModel = GeneralTabViewModel(
            defaults: isolatedDefaults(),
            launchAtLoginService: fake
        )

        XCTAssertFalse(viewModel.launchAtLogin)
    }

    func testSetLaunchAtLoginTrueCallsRegister() {
        let fake = FakeLaunchAtLoginService()
        fake.isEnabled = false
        let viewModel = GeneralTabViewModel(
            defaults: isolatedDefaults(),
            launchAtLoginService: fake
        )

        // Register flips fake to enabled, mirroring the real service's
        // behavior after a successful SMAppService.mainApp.register().
        fake.registerBehavior = { [weak fake] in fake?.isEnabled = true }

        viewModel.setLaunchAtLogin(true)

        XCTAssertEqual(fake.registerCallCount, 1)
        XCTAssertEqual(fake.unregisterCallCount, 0)
        XCTAssertTrue(viewModel.launchAtLogin)
    }

    func testSetLaunchAtLoginFalseCallsUnregister() {
        let fake = FakeLaunchAtLoginService()
        fake.isEnabled = true
        let viewModel = GeneralTabViewModel(
            defaults: isolatedDefaults(),
            launchAtLoginService: fake
        )

        fake.unregisterBehavior = { [weak fake] in fake?.isEnabled = false }

        viewModel.setLaunchAtLogin(false)

        XCTAssertEqual(fake.unregisterCallCount, 1)
        XCTAssertEqual(fake.registerCallCount, 0)
        XCTAssertFalse(viewModel.launchAtLogin)
    }

    func testRegisterThrowingSnapsBackToCurrentStatus() {
        let fake = FakeLaunchAtLoginService()
        fake.isEnabled = false
        let viewModel = GeneralTabViewModel(
            defaults: isolatedDefaults(),
            launchAtLoginService: fake
        )
        fake.shouldThrowOnRegister = true

        viewModel.setLaunchAtLogin(true)

        // The throw is swallowed and the view model re-reads the
        // service's real status. Since register() didn't take effect,
        // isEnabled stays false → the UI dot will render red.
        XCTAssertEqual(fake.registerCallCount, 1)
        XCTAssertFalse(viewModel.launchAtLogin)
    }

    func testUnregisterThrowingSnapsBackToCurrentStatus() {
        let fake = FakeLaunchAtLoginService()
        fake.isEnabled = true
        let viewModel = GeneralTabViewModel(
            defaults: isolatedDefaults(),
            launchAtLoginService: fake
        )
        fake.shouldThrowOnUnregister = true

        viewModel.setLaunchAtLogin(false)

        XCTAssertEqual(fake.unregisterCallCount, 1)
        // unregister threw so isEnabled stays true → dot stays green.
        XCTAssertTrue(viewModel.launchAtLogin)
    }

    func testRefreshReadsServiceIsEnabled() {
        let fake = FakeLaunchAtLoginService()
        fake.isEnabled = false
        let viewModel = GeneralTabViewModel(
            defaults: isolatedDefaults(),
            launchAtLoginService: fake
        )
        XCTAssertFalse(viewModel.launchAtLogin)

        // Simulate the user toggling Login Items in System Settings
        // while the Settings window was hidden.
        fake.isEnabled = true

        viewModel.refreshLaunchAtLoginStatus()

        XCTAssertTrue(viewModel.launchAtLogin)
    }

    func testDefaultInitCompilesWithoutExplicitService() {
        // Belt-and-braces — the `launchAtLoginService:` parameter has
        // a default, so existing call sites that don't pass a service
        // (GeneralTabViewModelTests, GeneralTabViewModelThemeTests)
        // keep compiling. Also covered implicitly by those suites, but
        // asserted here so a future breaking change shows up in the
        // #005 test file.
        let viewModel = GeneralTabViewModel(defaults: isolatedDefaults())
        // launchAtLogin reflects whatever SMAppService.mainApp reports
        // in the test host — either value is acceptable, just assert
        // the init didn't crash and the property is readable.
        _ = viewModel.launchAtLogin
    }
}

// MARK: - Fake

@MainActor
final class FakeLaunchAtLoginService: LaunchAtLoginServicing {
    var isEnabled: Bool = false
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    var shouldThrowOnRegister = false
    var shouldThrowOnUnregister = false
    // Optional side-effects for the success path — lets tests simulate
    // the real SMAppService.mainApp behavior (flipping isEnabled after
    // register/unregister returns).
    var registerBehavior: (() -> Void)?
    var unregisterBehavior: (() -> Void)?

    struct FakeFailure: Error {}

    func register() throws {
        registerCallCount += 1
        if shouldThrowOnRegister {
            throw FakeFailure()
        }
        registerBehavior?()
    }

    func unregister() throws {
        unregisterCallCount += 1
        if shouldThrowOnUnregister {
            throw FakeFailure()
        }
        unregisterBehavior?()
    }
}
