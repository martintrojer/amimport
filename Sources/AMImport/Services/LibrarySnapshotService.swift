import Foundation

protocol LibrarySnapshotting {
    func fetchAll(progress: @escaping (Int) -> Void) async throws -> [LibraryTrack]
}

protocol LibrarySongProviding {
    func fetchPage(offset: Int, limit: Int) async throws -> [LibraryTrack]
}

struct LibrarySnapshotService: LibrarySnapshotting {
    private let provider: LibrarySongProviding
    private let pageSize: Int

    init(provider: LibrarySongProviding, pageSize: Int = 200) {
        self.provider = provider
        self.pageSize = pageSize
    }

    func fetchAll(progress: @escaping (Int) -> Void) async throws -> [LibraryTrack] {
        var all: [LibraryTrack] = []
        var offset = 0

        while true {
            try Task.checkCancellation()

            let page = try await provider.fetchPage(offset: offset, limit: pageSize)
            if page.isEmpty {
                break
            }

            all.append(contentsOf: page)
            progress(all.count)

            if page.count < pageSize {
                break
            }

            offset += pageSize
        }

        return all
    }
}
