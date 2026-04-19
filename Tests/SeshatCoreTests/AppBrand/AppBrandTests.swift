import XCTest
@testable import SeshatCore

final class AppBrandTests: XCTestCase {
    func testStaticIdentityMatchesLayer9Contract() {
        XCTAssertEqual(AppBrand.displayName, "Seshat")
        XCTAssertEqual(AppBrand.bundleIdentifier, "com.nitkrar.seshat")
        XCTAssertEqual(AppBrand.logSubsystem, "com.nitkrar.seshat")
    }

    func testMarketingLinksDefaultToNil() {
        XCTAssertNil(AppBrand.websiteURL)
        XCTAssertNil(AppBrand.privacyURL)
        XCTAssertNil(AppBrand.termsURL)
    }

    func testVersionAndBuildNumberReadFromMainBundleInfoDictionary() {
        let infoDictionary = Bundle.main.infoDictionary ?? [:]

        XCTAssertEqual(AppBrand.version, AppBrand.resolvedVersion(in: infoDictionary))
        XCTAssertEqual(AppBrand.buildNumber, AppBrand.resolvedBuildNumber(in: infoDictionary))
    }

    func testVersionAndBuildNumberTrimWhitespace() {
        let infoDictionary: [String: Any] = [
            "CFBundleShortVersionString": " 1.2.3 \n",
            "CFBundleVersion": "\n 42 \t",
        ]

        XCTAssertEqual(AppBrand.resolvedVersion(in: infoDictionary), "1.2.3")
        XCTAssertEqual(AppBrand.resolvedBuildNumber(in: infoDictionary), "42")
    }

    func testMissingBundleMetadataFallsBackToDev() {
        XCTAssertEqual(AppBrand.resolvedVersion(in: [:]), "dev")
        XCTAssertEqual(AppBrand.resolvedBuildNumber(in: [:]), "dev")
    }

    func testEmptyBundleMetadataFallsBackToDev() {
        let infoDictionary: [String: Any] = [
            "CFBundleShortVersionString": " \n\t ",
            "CFBundleVersion": "   ",
        ]

        XCTAssertEqual(AppBrand.resolvedVersion(in: infoDictionary), "dev")
        XCTAssertEqual(AppBrand.resolvedBuildNumber(in: infoDictionary), "dev")
    }
}
