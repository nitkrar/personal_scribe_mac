import Foundation

public actor ModelLanguagePreference {
    public static let userDefaultsKey = "ModelLanguageHints"

    private let suiteName: String?
    private let logger: PersonalScribeLogger?
    private var catalogByID: [String: ModelDescriptor]

    public init(
        suiteName: String? = nil,
        registeredModels: [ModelDescriptor] = BuiltInModelCatalog.registeredModels,
        logger: PersonalScribeLogger? = nil
    ) {
        self.suiteName = suiteName
        self.logger = logger
        self.catalogByID = Self.catalogDictionary(from: registeredModels)
        Self.persistSanitizedHints(
            to: Self.resolveDefaults(suiteName: suiteName),
            catalogByID: self.catalogByID,
            logger: logger
        )
    }

    public func hint(for descriptorID: String) async -> String? {
        guard
            let descriptor = catalogByID[descriptorID],
            let supportedLanguages = descriptor.supportedLanguages,
            let language = storedHints()[descriptorID],
            !language.isEmpty,
            supportedLanguages.contains(language)
        else {
            return nil
        }

        return language
    }

    public func setHint(_ language: String?, for descriptorID: String) async {
        var hints = storedHints()

        guard
            let descriptor = catalogByID[descriptorID],
            let supportedLanguages = descriptor.supportedLanguages,
            let language,
            !language.isEmpty,
            supportedLanguages.contains(language)
        else {
            hints.removeValue(forKey: descriptorID)
            persist(hints)
            return
        }

        hints[descriptorID] = language
        persist(hints)
    }

    public func validate(against catalog: [ModelDescriptor]) async {
        catalogByID = Self.catalogDictionary(from: catalog)
        Self.persistSanitizedHints(
            to: Self.resolveDefaults(suiteName: suiteName),
            catalogByID: catalogByID,
            logger: logger
        )
    }

    private func storedHints() -> [String: String] {
        Preference<[String: String]>(
            key: Self.userDefaultsKey,
            default: [:],
            defaults: Self.resolveDefaults(suiteName: suiteName)
        ).resolve()
    }

    private func persist(_ hints: [String: String]) {
        Preference<[String: String]>(
            key: Self.userDefaultsKey,
            default: [:],
            defaults: Self.resolveDefaults(suiteName: suiteName)
        ).persist(hints)
    }

    private static func persistSanitizedHints(
        to defaults: UserDefaults,
        catalogByID: [String: ModelDescriptor],
        logger: PersonalScribeLogger?
    ) {
        let preference = Preference<[String: String]>(
            key: userDefaultsKey,
            default: [:],
            defaults: defaults
        )
        let current = preference.resolve()
        let sanitized = sanitizedHints(current, catalogByID: catalogByID, logger: logger)

        guard sanitized != current else {
            return
        }

        preference.persist(sanitized)
    }

    private static func sanitizedHints(
        _ hints: [String: String],
        catalogByID: [String: ModelDescriptor],
        logger: PersonalScribeLogger?
    ) -> [String: String] {
        var sanitized: [String: String] = [:]
        sanitized.reserveCapacity(hints.count)

        for (descriptorID, language) in hints {
            guard let descriptor = catalogByID[descriptorID] else {
                logger?.info(
                    "Dropping model language hint for removed descriptor",
                    metadata: ["descriptorID": descriptorID, "language": language]
                )
                continue
            }

            guard let supportedLanguages = descriptor.supportedLanguages else {
                logger?.info(
                    "Dropping model language hint for descriptor without picker support",
                    metadata: ["descriptorID": descriptorID, "language": language]
                )
                continue
            }

            guard !language.isEmpty, supportedLanguages.contains(language) else {
                logger?.info(
                    "Dropping invalid model language hint",
                    metadata: ["descriptorID": descriptorID, "language": language]
                )
                continue
            }

            sanitized[descriptorID] = language
        }

        return sanitized
    }

    private static func catalogDictionary(
        from registeredModels: [ModelDescriptor]
    ) -> [String: ModelDescriptor] {
        Dictionary(uniqueKeysWithValues: registeredModels.map { ($0.id, $0) })
    }

    private static func resolveDefaults(suiteName: String?) -> UserDefaults {
        guard let suiteName else {
            return .standard
        }

        return UserDefaults(suiteName: suiteName) ?? .standard
    }
}
