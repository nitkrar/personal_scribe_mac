import Foundation
import SeshatCore

internal struct PrivateModelDownloader: ModelDownloading {
    private let descriptor: ModelDescriptor
    private let session: URLSession = .shared
    private let clock = ContinuousClock()

    init(descriptor: ModelDescriptor) {
        self.descriptor = descriptor
    }

    func ensureModelAvailable(
        at directory: URL,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> URL {
        let fileManager = FileManager.default
        let baseDirectory = directory.deletingLastPathComponent()
        let stagingDirectory = FluidAudioTranscriber.stagingDirectory(
            base: baseDirectory,
            descriptor: descriptor
        )

        try? fileManager.removeItem(at: stagingDirectory)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        do {
            var completedBytes: Int64 = 0

            for (index, relativePath) in descriptor.requiredRelativePaths.enumerated() {
                let destinationURL = stagingDirectory.appendingPathComponent(relativePath, isDirectory: false)
                try fileManager.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let request = URLRequest(url: descriptor.resolveURL(for: relativePath))
                let (bytes, response) = try await session.bytes(for: request)

                guard
                    let httpResponse = response as? HTTPURLResponse,
                    (200..<300).contains(httpResponse.statusCode)
                else {
                    throw URLError(.badServerResponse)
                }

                let expectedBytes = response.expectedContentLength > 0 ? response.expectedContentLength : nil
                var receivedForFile: Int64 = 0
                var lastEmission = clock.now
                var data = Data()
                var iterator = bytes.makeAsyncIterator()

                while let byte = try await iterator.next() {
                    data.append(contentsOf: [byte])
                    receivedForFile += 1
                    let now = clock.now
                    let fileFraction = expectedBytes.map {
                        min(Double(receivedForFile) / Double($0), 1)
                    } ?? 0
                    let overallFraction = min(
                        (Double(index) + fileFraction) / Double(descriptor.requiredRelativePaths.count),
                        1
                    )

                    if receivedForFile == 1 || lastEmission.duration(to: now) >= .milliseconds(500) {
                        progress(
                            .init(
                                phase: .downloading,
                                fractionCompleted: overallFraction,
                                receivedBytes: completedBytes + receivedForFile,
                                expectedBytes: expectedBytes
                            )
                        )
                        lastEmission = now
                    }
                }

                try data.write(to: destinationURL, options: .atomic)
                completedBytes += receivedForFile
                progress(
                    .init(
                        phase: .downloading,
                        fractionCompleted: Double(index + 1) / Double(descriptor.requiredRelativePaths.count),
                        receivedBytes: completedBytes,
                        expectedBytes: expectedBytes
                    )
                )
            }

            try? fileManager.removeItem(at: directory)
            try fileManager.moveItem(at: stagingDirectory, to: directory)
            return directory
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            throw error
        }
    }
}
