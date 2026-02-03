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
            candidates: [
                MatchCandidateSnapshot(
                    id: "sel-1",
                    catalogSongID: "cat-1",
                    librarySongID: "lib-1",
                    title: "Track",
                    artist: "Artist",
                    album: "Album",
                    artworkURL: URL(string: "https://example.com/art.jpg"),
                    durationSeconds: 222
                )
            ],
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
    func test_refreshConnectionStatus_reportsConnectionFailure() async {
        let importViewModel = ImportSessionViewModel(
            authorizer: AuthorizedAuthorizer(),
            resolver: StubResolver(libraryTracks: []),
            snapshotter: FailingSnapshotter(error: StubFailure(message: "Connection failed."))
        )

        await importViewModel.refreshConnectionStatus(requestIfNeeded: true)

        XCTAssertFalse(importViewModel.isConnectionHealthy)
        XCTAssertTrue(importViewModel.connectionStatusText.contains("Connection failed"))
    }

    func test_resolveRows_includeCandidatePreviewFields() {
        let session = ImportSession(
            format: .csv,
            options: .default,
            importedRows: [ImportTrackRow(sourceLine: 1, title: "Track One", artist: "Artist A")],
            decisions: [
                MatchDecisionSnapshot(
                    rowID: "row-1",
                    status: .unmatched,
                    selectedTrackID: nil,
                    catalogSongID: nil,
                    librarySongID: nil,
                    candidateTrackIDs: ["c1"],
                    candidates: [
                        MatchCandidateSnapshot(
                            id: "c1",
                            catalogSongID: "cat-1",
                            librarySongID: "lib-1",
                            title: "Track One",
                            artist: "Artist A",
                            album: "Album A",
                            artworkURL: URL(string: "https://example.com/a.jpg"),
                            durationSeconds: 222
                        )
                    ],
                    confidence: 0.8,
                    rationale: "candidate"
                )
            ],
            summary: ImportSummary(totalRows: 1, autoMatched: 0, unmatched: 1),
            createdAt: Date()
        )

        let rows = ResolveMatchesView.buildRows(from: session)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].candidates.first?.title, "Track One")
        XCTAssertEqual(rows[0].candidates.first?.album, "Album A")
        XCTAssertEqual(rows[0].candidates.first?.durationSeconds, 222)
    }

    func test_resolveRows_keepMissingPreviewFieldsAsNil() {
        let session = ImportSession(
            format: .csv,
            options: .default,
            importedRows: [ImportTrackRow(sourceLine: 1, title: "Track One", artist: "Artist A")],
            decisions: [
                MatchDecisionSnapshot(
                    rowID: "row-1",
                    status: .unmatched,
                    selectedTrackID: nil,
                    catalogSongID: nil,
                    librarySongID: nil,
                    candidateTrackIDs: ["c1"],
                    candidates: [
                        MatchCandidateSnapshot(
                            id: "c1",
                            catalogSongID: nil,
                            librarySongID: nil,
                            title: "Track One",
                            artist: "Artist A",
                            album: nil,
                            artworkURL: nil,
                            durationSeconds: nil
                        )
                    ],
                    confidence: 0.8,
                    rationale: "candidate"
                )
            ],
            summary: ImportSummary(totalRows: 1, autoMatched: 0, unmatched: 1),
            createdAt: Date()
        )

        let rows = ResolveMatchesView.buildRows(from: session)
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0].candidates.first?.album)
        XCTAssertNil(rows[0].candidates.first?.artworkURL)
        XCTAssertNil(rows[0].candidates.first?.durationSeconds)
    }

    @MainActor
    func test_export_enqueue_skipsUnavailableTracksAndContinues() async {
        let session = ImportSession(
            format: .csv,
            options: .default,
            importedRows: [
                ImportTrackRow(sourceLine: 1, title: "A", artist: "A"),
                ImportTrackRow(sourceLine: 2, title: "B", artist: "B"),
                ImportTrackRow(sourceLine: 3, title: "C", artist: "C")
            ],
            decisions: [
                MatchDecisionSnapshot(
                    rowID: "row-1",
                    status: .autoMatched,
                    selectedTrackID: "lib-1",
                    catalogSongID: "cat-1",
                    librarySongID: "lib-1",
                    candidateTrackIDs: ["lib-1"],
                    candidates: [],
                    confidence: 1.0,
                    rationale: "ok"
                ),
                MatchDecisionSnapshot(
                    rowID: "row-2",
                    status: .autoMatched,
                    selectedTrackID: "lib-2",
                    catalogSongID: "cat-2",
                    librarySongID: "lib-2",
                    candidateTrackIDs: ["lib-2"],
                    candidates: [],
                    confidence: 1.0,
                    rationale: "ok"
                ),
                MatchDecisionSnapshot(
                    rowID: "row-3",
                    status: .autoMatched,
                    selectedTrackID: "lib-3",
                    catalogSongID: "cat-3",
                    librarySongID: "lib-3",
                    candidateTrackIDs: ["lib-3"],
                    candidates: [],
                    confidence: 1.0,
                    rationale: "ok"
                )
            ],
            summary: ImportSummary(totalRows: 3, autoMatched: 3, unmatched: 0),
            createdAt: Date()
        )

        let exporter = PartialSuccessExporter(
            summary: ExportExecutionSummary(requested: 3, succeeded: 2, skipped: 1)
        )
        let viewModel = ExportViewModel(exporter: exporter)
        viewModel.mode = .enqueue

        await viewModel.export(session: session)

        XCTAssertEqual(exporter.lastEnqueueIDs, ["cat-1", "cat-2", "cat-3"])
        XCTAssertTrue(viewModel.statusMessage.contains("2/3"))
        XCTAssertTrue(viewModel.statusMessage.contains("Skipped 1"))
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
            candidates: decision.result.candidates.map { candidate in
                MatchCandidateSnapshot(
                    id: candidate.track.id,
                    catalogSongID: candidate.track.id,
                    librarySongID: candidate.track.id,
                    title: candidate.track.title,
                    artist: candidate.track.artist,
                    album: candidate.track.album,
                    artworkURL: nil,
                    durationSeconds: candidate.track.durationSeconds
                )
            },
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

private final class CapturingExporter: MusicKitExporting {
    var enqueuedTrackIDs: [String] = []

    @MainActor
    func createPlaylist(name: String, catalogSongIDs: [String]) async throws -> ExportExecutionSummary {
        enqueuedTrackIDs = catalogSongIDs
        return ExportExecutionSummary(requested: catalogSongIDs.count, succeeded: catalogSongIDs.count, skipped: 0)
    }

    @MainActor
    func enqueueAndPlay(catalogSongIDs: [String]) async throws -> ExportExecutionSummary {
        enqueuedTrackIDs = catalogSongIDs
        return ExportExecutionSummary(requested: catalogSongIDs.count, succeeded: catalogSongIDs.count, skipped: 0)
    }
}

private final class PartialSuccessExporter: MusicKitExporting {
    let summary: ExportExecutionSummary
    var lastEnqueueIDs: [String] = []

    init(summary: ExportExecutionSummary) {
        self.summary = summary
    }

    @MainActor
    func createPlaylist(name: String, catalogSongIDs: [String]) async throws -> ExportExecutionSummary {
        summary
    }

    @MainActor
    func enqueueAndPlay(catalogSongIDs: [String]) async throws -> ExportExecutionSummary {
        lastEnqueueIDs = catalogSongIDs
        return summary
    }
}
