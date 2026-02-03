import XCTest
@testable import AMImport

final class ImportToExportFlowTests: XCTestCase {
    @MainActor
    func test_importToExport_passesOrderedTrackIDsToExporter() async {
        let rawCSV = """
        title,artist
        Track One,Artist A
        Track Two,Artist B
        """

        let libraryTracks = [
            LibraryTrack(id: "id1", title: "Track One", artist: "Artist A", album: nil, durationSeconds: nil, isrc: nil),
            LibraryTrack(id: "id2", title: "Track Two", artist: "Artist B", album: nil, durationSeconds: nil, isrc: nil),
        ]

        let importViewModel = ImportSessionViewModel(
            authorizer: AuthorizedAuthorizer(),
            snapshotter: StubSnapshotter(libraryTracks: libraryTracks)
        )

        await importViewModel.runImport(rawInput: rawCSV, format: .csv, options: .default)

        guard let session = importViewModel.session else {
            XCTFail("Expected session after import")
            return
        }

        let exporter = CapturingExporter()
        let exportViewModel = ExportViewModel(exporter: exporter)
        exportViewModel.mode = .enqueue

        await exportViewModel.export(session: session)

        XCTAssertEqual(exporter.enqueuedTrackIDs, ["id1", "id2"])
    }
}

private struct AuthorizedAuthorizer: MusicAuthorizing {
    @MainActor
    func currentStatus() -> MusicAuthorizationStatus { .authorized }

    @MainActor
    func request() async -> MusicAuthorizationStatus { .authorized }
}

private struct StubSnapshotter: LibrarySnapshotting {
    let libraryTracks: [LibraryTrack]

    @MainActor
    func fetchAll(progress: @escaping (Int) -> Void) async throws -> [LibraryTrack] {
        progress(libraryTracks.count)
        return libraryTracks
    }
}

private final class CapturingExporter: MusicAppControlling {
    var enqueuedTrackIDs: [String] = []

    @MainActor
    func createPlaylist(name: String, trackIDs: [String]) async throws {
        enqueuedTrackIDs = trackIDs
    }

    @MainActor
    func enqueue(trackIDs: [String]) async throws {
        enqueuedTrackIDs = trackIDs
    }
}
