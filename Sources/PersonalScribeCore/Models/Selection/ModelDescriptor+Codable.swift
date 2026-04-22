import Foundation

extension ModelDescriptor: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case shortDescription
        case repository
        case revision
        case requiredRelativePaths
        case approximateSizeBytes
        case engine
        case speedRating
        case accuracyRating
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            displayName: try container.decode(String.self, forKey: .displayName),
            // `shortDescription`, `speedRating`, `accuracyRating` are all
            // decoded defensively. `ActiveModelDescriptor` persists a
            // `ModelDescriptor` blob in `UserDefaults`, but
            // `DefaultModelService.resolveInitialDescriptor` immediately
            // substitutes the catalog's canonical entry by id — so any
            // fallback here is discarded before reaching the UI.
            shortDescription: try container.decodeIfPresent(String.self, forKey: .shortDescription) ?? "",
            repository: try container.decode(String.self, forKey: .repository),
            revision: try container.decode(String.self, forKey: .revision),
            requiredRelativePaths: try container.decode([String].self, forKey: .requiredRelativePaths),
            approximateSizeBytes: try container.decode(Int64.self, forKey: .approximateSizeBytes),
            engine: try container.decode(TranscriptionEngine.self, forKey: .engine),
            speedRating: try container.decodeIfPresent(RelativeRating.self, forKey: .speedRating),
            accuracyRating: try container.decodeIfPresent(RelativeRating.self, forKey: .accuracyRating)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(shortDescription, forKey: .shortDescription)
        try container.encode(repository, forKey: .repository)
        try container.encode(revision, forKey: .revision)
        try container.encode(requiredRelativePaths, forKey: .requiredRelativePaths)
        try container.encode(approximateSizeBytes, forKey: .approximateSizeBytes)
        try container.encode(engine, forKey: .engine)
        try container.encodeIfPresent(speedRating, forKey: .speedRating)
        try container.encodeIfPresent(accuracyRating, forKey: .accuracyRating)
    }
}

