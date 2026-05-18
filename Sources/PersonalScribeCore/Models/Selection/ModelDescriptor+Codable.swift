import Foundation

extension ModelDescriptor: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case repoFolderName
        // `kind` removed from stored fields per #078.37 (L2). Decoder
        // ignores it on read for back-compat with persisted blobs;
        // encoder never emits it. The computed `kind: engine.kind`
        // accessor on `ModelDescriptor` is the single source of truth.
        case shortDescription
        case architecture
        case repository
        case revision
        case requiredRelativePaths
        case approximateSizeBytes
        case isEnabled
        case engine
        case performance
        case tokenizerSource
        case requiredChipFamily
        case supportedLanguages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        self.init(
            id: id,
            displayName: try container.decode(String.self, forKey: .displayName),
            // Defensive defaults — `ActiveModelDescriptor` persists a
            // `ModelDescriptor` blob in `UserDefaults`, but
            // `DefaultModelService.resolveInitialDescriptor` immediately
            // substitutes the catalog's canonical entry by id, so any
            // fallback here is discarded before reaching the UI.
            // `repoFolderName` defaults to `id` to preserve old persisted
            // blobs; canonical override happens via the catalog lookup.
            repoFolderName: try container.decodeIfPresent(String.self, forKey: .repoFolderName) ?? id,
            shortDescription: try container.decodeIfPresent(String.self, forKey: .shortDescription) ?? "",
            architecture: try container.decodeIfPresent(String.self, forKey: .architecture) ?? "",
            repository: try container.decode(String.self, forKey: .repository),
            revision: try container.decode(String.self, forKey: .revision),
            requiredRelativePaths: try container.decode([String].self, forKey: .requiredRelativePaths),
            approximateSizeBytes: try container.decode(Int64.self, forKey: .approximateSizeBytes),
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            engine: try container.decode(TranscriptionEngine.self, forKey: .engine),
            performance: try container.decodeIfPresent(ModelPerformance.self, forKey: .performance) ?? ModelPerformance(),
            tokenizerSource: try container.decodeIfPresent(String.self, forKey: .tokenizerSource),
            requiredChipFamily: try container.decodeIfPresent(ChipFamily.self, forKey: .requiredChipFamily),
            supportedLanguages: try container.decodeIfPresent([String].self, forKey: .supportedLanguages)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(repoFolderName, forKey: .repoFolderName)
        try container.encode(shortDescription, forKey: .shortDescription)
        try container.encode(architecture, forKey: .architecture)
        try container.encode(repository, forKey: .repository)
        try container.encode(revision, forKey: .revision)
        try container.encode(requiredRelativePaths, forKey: .requiredRelativePaths)
        try container.encode(approximateSizeBytes, forKey: .approximateSizeBytes)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(engine, forKey: .engine)
        try container.encode(performance, forKey: .performance)
        try container.encodeIfPresent(tokenizerSource, forKey: .tokenizerSource)
        try container.encodeIfPresent(requiredChipFamily, forKey: .requiredChipFamily)
        try container.encodeIfPresent(supportedLanguages, forKey: .supportedLanguages)
    }
}
