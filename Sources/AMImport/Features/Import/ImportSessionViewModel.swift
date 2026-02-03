import Foundation
import SwiftUI

enum ImportState: Equatable {
    case idle
    case requestingPermission
    case loadingLibrary
    case matching(progress: Int, total: Int)
    case completed(ImportSummary)
    case failed(String)
}

struct ImportSummary: Codable, Equatable {
    let totalRows: Int
    let autoMatched: Int
    let unmatched: Int
}

struct ImportSession: Codable, Equatable {
    let format: ImportFormat
    let options: MatchingOptions
    let importedRows: [ImportTrackRow]
    let decisions: [MatchDecisionSnapshot]
    let summary: ImportSummary
    let createdAt: Date
}

struct MatchDecisionSnapshot: Codable, Equatable {
    let rowID: String
    let status: MatchStatus
    let selectedTrackID: String?
    let candidateTrackIDs: [String]
    let confidence: Double
    let rationale: String
}

final class ImportSessionViewModel: ObservableObject {
    @Published var state: ImportState = .idle
    @Published var session: ImportSession?

    private let authorizer: MusicAuthorizing
    private let snapshotter: LibrarySnapshotting
    private let matcher: MatcherPipeline

    init(
        authorizer: MusicAuthorizing,
        snapshotter: LibrarySnapshotting,
        matcher: MatcherPipeline = MatcherPipeline()
    ) {
        self.authorizer = authorizer
        self.snapshotter = snapshotter
        self.matcher = matcher
    }

    func runImport(
        rawInput: String,
        format: ImportFormat = .csv,
        parser: ImportParsing = CSVImporter(),
        options: MatchingOptions = .default
    ) async {
        do {
            let rows = try parser.parse(rawInput)

            state = .requestingPermission
            let authorization = await resolveAuthorization()
            guard authorization == .authorized else {
                state = .failed(permissionMessage(for: authorization))
                return
            }

            state = .loadingLibrary
            let library = try await snapshotter.fetchAll { _ in }

            var snapshots: [MatchDecisionSnapshot] = []
            snapshots.reserveCapacity(rows.count)

            for (index, row) in rows.enumerated() {
                let decision = matcher.match(row: row, in: library, options: options)
                snapshots.append(
                    MatchDecisionSnapshot(
                        rowID: row.id,
                        status: decision.result.status,
                        selectedTrackID: decision.result.selectedTrack?.id,
                        candidateTrackIDs: decision.result.candidates.map(\.track.id),
                        confidence: decision.confidence,
                        rationale: decision.rationale
                    )
                )
                state = .matching(progress: index + 1, total: rows.count)
            }

            let autoMatched = snapshots.filter { $0.status == .autoMatched }.count
            let unmatched = snapshots.filter { $0.status == .unmatched }.count
            let summary = ImportSummary(totalRows: rows.count, autoMatched: autoMatched, unmatched: unmatched)

            session = ImportSession(
                format: format,
                options: options,
                importedRows: rows,
                decisions: snapshots,
                summary: summary,
                createdAt: Date()
            )
            state = .completed(summary)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func resolveAuthorization() async -> MusicAuthorizationStatus {
        let current = authorizer.currentStatus()
        if current == .notDetermined {
            return await authorizer.request()
        }
        return current
    }

    private func permissionMessage(for status: MusicAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return ""
        case .denied:
            return "Apple Music access is denied."
        case .restricted:
            return "Apple Music access is restricted."
        case .notDetermined:
            return "Apple Music access has not been granted."
        }
    }
}
