import Foundation

protocol SessionStoring {
    func save(_ session: ImportSession) throws
    func loadLatest() throws -> ImportSession?
}

struct SessionStore: SessionStoring {
    private let fileManager: FileManager
    private let baseURL: URL

    init(
        fileManager: FileManager = .default,
        baseURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.baseURL = baseURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AMImport", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    func save(_ session: ImportSession) throws {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let envelope = SessionEnvelope(schemaVersion: 1, session: session)
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: latestFileURL(), options: .atomic)
    }

    func loadLatest() throws -> ImportSession? {
        let url = latestFileURL()
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let data = try Data(contentsOf: url)
        let envelope = try JSONDecoder().decode(SessionEnvelope.self, from: data)
        return envelope.session
    }

    private func latestFileURL() -> URL {
        baseURL.appendingPathComponent("latest.json", isDirectory: false)
    }
}

private struct SessionEnvelope: Codable {
    let schemaVersion: Int
    let session: ImportSession
}
