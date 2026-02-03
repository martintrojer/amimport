import XCTest
@testable import AMImport

final class ImportToExportFlowTests: XCTestCase {
    func test_matchSnapshot_roundTripsCatalogAndLibraryIDs() throws {
        let snapshot = MatchDecisionSnapshot(
            rowID: "row-1",
            status: .autoMatched,
            selectedTrackID: "sel-1",
            catalogSongID: "cat-1",
            librarySongID: "lib-1",
            candidateTrackIDs: ["sel-1"],
            confidence: 0.98,
            rationale: "exact"
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(MatchDecisionSnapshot.self, from: data)

        XCTAssertEqual(decoded.catalogSongID, "cat-1")
        XCTAssertEqual(decoded.librarySongID, "lib-1")
    }

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
            resolver: StubResolver(libraryTracks: libraryTracks),
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

    @MainActor
    func test_runImport_failsWithHelpfulMessageWhenLibraryIsEmpty() async {
        let rawCSV = """
        title,artist
        Track One,Artist A
        """

        let importViewModel = ImportSessionViewModel(
            authorizer: AuthorizedAuthorizer(),
            resolver: ThrowingResolver(error: StubFailure(message: "Search unavailable."))
        )

        await importViewModel.runImport(rawInput: rawCSV, format: .csv, options: .default)

        guard case let .failed(message) = importViewModel.state else {
            XCTFail("Expected failed state")
            return
        }
        XCTAssertTrue(message.contains("Search unavailable"))
    }

    @MainActor
    func test_refreshConnectionStatus_reportsPermissionFailure() async {
        let importViewModel = ImportSessionViewModel(
            authorizer: DeniedAuthorizer(),
            resolver: StubResolver(libraryTracks: []),
            snapshotter: StubSnapshotter(libraryTracks: [])
        )

        await importViewModel.refreshConnectionStatus()

        XCTAssertFalse(importViewModel.isConnectionHealthy)
        XCTAssertTrue(importViewModel.connectionStatusText.contains("denied"))
        XCTAssertTrue(importViewModel.shouldShowOpenSettingsShortcut)
    }

    @MainActor
    func test_refreshConnectionStatus_flagsAutomationPermissionFailure() async {
        let importViewModel = ImportSessionViewModel(
            authorizer: AuthorizedAuthorizer(),
            resolver: StubResolver(libraryTracks: []),
            snapshotter: FailingSnapshotter(
                error: StubFailure(message: "Not authorized to send Apple events to Music.")
            )
        )

        await importViewModel.refreshConnectionStatus(requestIfNeeded: true)

        XCTAssertFalse(importViewModel.isConnectionHealthy)
        XCTAssertTrue(importViewModel.connectionNeedsAutomationPermission)
    }
}

private struct StubResolver: TrackResolving {
    let libraryTracks: [LibraryTrack]
    private let matcher = MatcherPipeline()

    @MainActor
    func resolve(row: ImportTrackRow, options: MatchingOptions) async throws -> MatchDecisionSnapshot {
        let decision = matcher.match(row: row, in: libraryTracks, options: options)
        return MatchDecisionSnapshot(
            rowID: row.id,
            status: decision.result.status,
            selectedTrackID: decision.result.selectedTrack?.id,
            catalogSongID: decision.result.selectedTrack?.id,
            librarySongID: decision.result.selectedTrack?.id,
            candidateTrackIDs: decision.result.candidates.map(\.track.id),
            confidence: decision.confidence,
            rationale: decision.rationale
        )
    }
}

private struct ThrowingResolver: TrackResolving {
    let error: Error

    @MainActor
    func resolve(row: ImportTrackRow, options: MatchingOptions) async throws -> MatchDecisionSnapshot {
        throw error
    }
}

private struct AuthorizedAuthorizer: MusicAuthorizing {
    @MainActor
    func currentStatus() -> MusicAuthorizationStatus { .authorized }

    @MainActor
    func request() async -> MusicAuthorizationStatus { .authorized }
}

private struct DeniedAuthorizer: MusicAuthorizing {
    @MainActor
    func currentStatus() -> MusicAuthorizationStatus { .denied }

    @MainActor
    func request() async -> MusicAuthorizationStatus { .denied }
}

private struct StubSnapshotter: LibrarySnapshotting {
    let libraryTracks: [LibraryTrack]

    @MainActor
    func fetchAll(progress: @escaping (Int) -> Void) async throws -> [LibraryTrack] {
        progress(libraryTracks.count)
        return libraryTracks
    }
}

private struct FailingSnapshotter: LibrarySnapshotting {
    let error: Error

    @MainActor
    func fetchAll(progress: @escaping (Int) -> Void) async throws -> [LibraryTrack] {
        throw error
    }
}

private struct StubFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
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
