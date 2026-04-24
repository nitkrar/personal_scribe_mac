import Foundation

extension ModelDescriptor: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case repoFolderName
        case kind
        case shortDescription
        case architecture
        case repository
        case revision
        case requiredRelativePaths
        case approximateSizeBytes
        case engine
        case performance
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
            kind: try container.decodeIfPresent(ModelKind.self, forKey: .kind) ?? .asr,
            shortDescription: try container.decodeIfPresent(String.self, forKey: .shortDescription) ?? "",
            architecture: try container.decodeIfPresent(String.self, forKey: .architecture) ?? "",
            repository: try container.decode(String.self, forKey: .repository),
            revision: try container.decode(String.self, forKey: .revision),
            requiredRelativePaths: try container.decode([String].self, forKey: .requiredRelativePaths),
            approximateSizeBytes: try container.decode(Int64.self, forKey: .approximateSizeBytes),
            engine: try container.decode(TranscriptionEngine.self, forKey: .engine),
            performance: try container.decodeIfPresent(ModelPerformance.self, forKey: .performance) ?? ModelPerformance()
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(repoFolderName, forKey: .repoFolderName)
        try container.encode(kind, forKey: .kind)
        try container.encode(shortDescription, forKey: .shortDescription)
        try container.encode(architecture, forKey: .architecture)
        try container.encode(repository, forKey: .repository)
        try container.encode(revision, forKey: .revision)
        try container.encode(requiredRelativePaths, forKey: .requiredRelativePaths)
        try container.encode(approximateSizeBytes, forKey: .approximateSizeBytes)
        try container.encode(engine, forKey: .engine)
        try container.encode(performance, forKey: .performance)
    }
}
