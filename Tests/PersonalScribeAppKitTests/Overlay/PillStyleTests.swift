import XCTest
@testable import PersonalScribeAppKit

/// Tests for `PillStyle` — the user-selectable pill shape preference
/// (Classic / Mini / None). Follows the `PillAppearanceTests.swift`
/// pattern verbatim (resolve/persist round-trip, fallback, no-prefix
/// UserDefaults key).
final class PillStyleTests: XCTestCase {
    // MARK: - Cases + UserDefaults round-trip

    func testCasesInclude_Classic_Mini_None() {
        XCTAssertEqual(PillStyle.allCases, [.classic, .mini, .none])
    }

    func testDefaultResolvesToClassic() {
        let defaults = Self.isolatedDefaults()
        XCTAssertEqual(PillStyle.resolve(from: defaults), .classic)
    }

    func testResolveReadsPersistedMini() {
        let defaults = Self.isolatedDefaults()
        PillStyle.mini.persist(to: defaults)
        XCTAssertEqual(PillStyle.resolve(from: defaults), .mini)
    }

    func testResolveReadsPersistedNone() {
        let defaults = Self.isolatedDefaults()
        PillStyle.none.persist(to: defaults)
        XCTAssertEqual(PillStyle.resolve(from: defaults), .none)
    }

    func testResolveFallsBackToClassicOnInvalidValue() {
        let defaults = Self.isolatedDefaults()
        defaults.set("NotAStyle", forKey: PillStyle.userDefaultsKey)
        XCTAssertEqual(PillStyle.resolve(from: defaults), .classic)
    }

    func testPersistWritesRawValue() {
        let defaults = Self.isolatedDefaults()
        PillStyle.mini.persist(to: defaults)
        XCTAssertEqual(
            defaults.string(forKey: PillStyle.userDefaultsKey),
            "Mini"
        )
    }

    func testUserDefaultsKeyHasNoPrefix() {
        XCTAssertEqual(PillStyle.userDefaultsKey, "PillStyle")
    }

    // MARK: - Helpers

    private static func isolatedDefaults() -> UserDefaults {
        let suiteName = "PillStyleTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated UserDefaults for test")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
