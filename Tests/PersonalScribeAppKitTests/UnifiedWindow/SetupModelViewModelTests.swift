import Foundation
import PersonalScribeCore
import PersonalScribeSession
import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class SetupModelViewModelTests: XCTestCase {
    func testRecommendationComesFromActiveModelService() throws {
        let suite = "SetupModelViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let active = BuiltInModelCatalog.parakeetTDTCTC110M
        let recommended = BuiltInModelCatalog.parakeetTDT06Bv2
        let service = ActiveModelService(
            activeIDsPreference: Preference(
                key: ActiveModelService.preferenceKey,
                default: [.asr: active.id],
                defaults: defaults
            ),
            isDownloaded: { _ in false },
            download: { _, _ in },
            recommendedModels: [.asr: recommended]
        )

        let viewModel = SetupModelViewModel(
            service: service,
            showAllModels: {}
        )

        XCTAssertEqual(viewModel.selectedModel.id, active.id)
        XCTAssertEqual(viewModel.recommendedModel.id, recommended.id)
    }

    func testAppearOnlyRefreshesObservedState() throws {
        let suite = "SetupModelViewModelTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let active = BuiltInModelCatalog.parakeetTDTCTC110M
        let service = ActiveModelService(
            activeIDsPreference: Preference(
                key: ActiveModelService.preferenceKey,
                default: [.asr: active.id],
                defaults: defaults
            ),
            isDownloaded: { _ in false },
            download: { _, _ in XCTFail("Model step must not start a download") },
            recommendedModels: [.asr: active]
        )
        let viewModel = SetupModelViewModel(service: service, showAllModels: {})

        viewModel.appear()

        XCTAssertEqual(viewModel.selectedState?.phase, .notDownloaded)
    }
}
