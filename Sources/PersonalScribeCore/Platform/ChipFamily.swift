import Darwin
import Foundation

public enum ChipFamily: String, Sendable, Equatable, CaseIterable, Codable {
    case m1
    case m2OrLater

    public static func current() -> ChipFamily {
        guard let brandString = currentBrandString(), !brandString.isEmpty else {
            // Fail closed so unsupported models stay hidden if chip
            // detection breaks on a future platform.
            return .m1
        }

        return detect(from: brandString)
    }

    static func detect(from brandString: String) -> ChipFamily {
        if brandString.range(
            of: #"(^|\s)M1(\s|$)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return .m1
        }

        return .m2OrLater
    }

    private static func currentBrandString() -> String? {
        var size: size_t = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: Int(size))
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else {
            return nil
        }

        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
