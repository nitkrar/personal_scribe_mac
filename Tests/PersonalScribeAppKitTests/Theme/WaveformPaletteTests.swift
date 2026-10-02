import XCTest
@testable import PersonalScribeAppKit

final class WaveformPaletteTests: XCTestCase {
    func testDefaultsToCurrentSiriPaletteWhenUnsetOrUnknown() {
        let defaults = UserDefaults(suiteName: "WaveformPaletteTests.\(UUID().uuidString)")!
        XCTAssertEqual(WaveformPalette.resolve(from: defaults), .siri)

        defaults.set("not-a-palette", forKey: WaveformPalette.userDefaultsKey)
        XCTAssertEqual(WaveformPalette.resolve(from: defaults), .siri)
    }

    /// The pill reads the key via `@AppStorage` as a plain string, so
    /// persistence must store the raw value, not JSON-encoded data.
    func testPersistStoresPlainRawStringReadableByAppStorage() {
        let defaults = UserDefaults(suiteName: "WaveformPaletteTests.\(UUID().uuidString)")!

        WaveformPalette.aurora.persist(to: defaults)

        XCTAssertEqual(defaults.string(forKey: WaveformPalette.userDefaultsKey), "aurora")
        XCTAssertEqual(WaveformPalette.resolve(from: defaults), .aurora)
    }

    func testEveryPaletteHasThreeStrandsAndDarkerShadesForLightBackground() {
        for palette in WaveformPalette.allCases {
            let dark = palette.strandRGB(onDarkBackground: true)
            let light = palette.strandRGB(onDarkBackground: false)
            XCTAssertEqual(dark.count, 3, "\(palette)")
            for (d, l) in zip(dark, light) {
                XCTAssertLessThan(l.red + l.green + l.blue, d.red + d.green + d.blue, "\(palette)")
            }
        }
    }
}
