import SwiftUI
import Foundation

struct ResolveRow: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let candidates: [MatchCandidateSnapshot]
    var selectedTrackID: String?
    var selectedCatalogSongID: String?
    var selectedLibrarySongID: String?
    var status: MatchStatus
}

struct ResolveMatchesView: View {
    @Binding var session: ImportSession?
    @State private var unresolvedRows: [ResolveRow]

    init(session: Binding<ImportSession?>) {
        _session = session
        _unresolvedRows = State(initialValue: Self.buildRows(from: session.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resolve Unmatched Tracks")
                .font(.title2)

            Table(unresolvedRows) {
                TableColumn("Title") { row in
                    Text(row.title)
                }
                TableColumn("Artist") { row in
                    Text(row.artist)
                }
                TableColumn("Candidates") { row in
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(row.candidates) { candidate in
                            HStack(spacing: 8) {
                                AsyncImage(url: candidate.artworkURL) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.2))
                                }
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.title)
                                    Text("\(candidate.artist) • \(candidate.album ?? "-")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(formatDuration(candidate.durationSeconds))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                TableColumn("Status") { row in
                    Text(row.status.rawValue)
                }
                TableColumn("Action") { row in
                    HStack(spacing: 8) {
                        Button("Accept First") {
                            applyFirstCandidate(for: row.id)
                        }
                        Button("Skip") {
                            skip(rowID: row.id)
                        }
                    }
                }
            }
        }
        .padding(16)
        .onChange(of: session) { _, newSession in
            unresolvedRows = Self.buildRows(from: newSession)
        }
    }

    static func buildRows(from session: ImportSession?) -> [ResolveRow] {
        guard let session else { return [] }
        let sourceByID = Dictionary(uniqueKeysWithValues: session.importedRows.map { ($0.id, $0) })

        return session.decisions.compactMap { snapshot in
            guard snapshot.status == .unmatched,
                  let source = sourceByID[snapshot.rowID] else {
                return nil
            }

            return ResolveRow(
                id: snapshot.rowID,
                title: source.title,
                artist: source.artist,
                candidates: snapshot.candidates,
                selectedTrackID: snapshot.selectedTrackID,
                selectedCatalogSongID: snapshot.catalogSongID,
                selectedLibrarySongID: snapshot.librarySongID,
                status: snapshot.status
            )
        }
    }

    private func applyFirstCandidate(for rowID: String) {
        guard let index = unresolvedRows.firstIndex(where: { $0.id == rowID }),
              let first = unresolvedRows[index].candidates.first else {
            return
        }

        unresolvedRows[index].selectedTrackID = first.id
        unresolvedRows[index].selectedCatalogSongID = first.catalogSongID
        unresolvedRows[index].selectedLibrarySongID = first.librarySongID
        unresolvedRows[index].status = .userMatched
        syncSession(
            rowID: rowID,
            status: .userMatched,
            selectedTrackID: first.id,
            catalogSongID: first.catalogSongID,
            librarySongID: first.librarySongID
        )
    }

    private func skip(rowID: String) {
        guard let index = unresolvedRows.firstIndex(where: { $0.id == rowID }) else {
            return
        }

        unresolvedRows[index].status = .skipped
        syncSession(rowID: rowID, status: .skipped, selectedTrackID: nil, catalogSongID: nil, librarySongID: nil)
    }

    private func syncSession(
        rowID: String,
        status: MatchStatus,
        selectedTrackID: String?,
        catalogSongID: String?,
        librarySongID: String?
    ) {
        guard var current = session else { return }

        let updatedDecisions = current.decisions.map { snapshot -> MatchDecisionSnapshot in
            guard snapshot.rowID == rowID else { return snapshot }
            return MatchDecisionSnapshot(
                rowID: snapshot.rowID,
                status: status,
                selectedTrackID: selectedTrackID,
                catalogSongID: catalogSongID,
                librarySongID: librarySongID,
                candidateTrackIDs: snapshot.candidateTrackIDs,
                candidates: snapshot.candidates,
                confidence: snapshot.confidence,
                rationale: snapshot.rationale
            )
        }

        let autoMatched = updatedDecisions.filter { $0.status == .autoMatched || $0.status == .userMatched }.count
        let unmatched = updatedDecisions.filter { $0.status == .unmatched }.count

        current = ImportSession(
            format: current.format,
            options: current.options,
            importedRows: current.importedRows,
            decisions: updatedDecisions,
            summary: ImportSummary(totalRows: current.summary.totalRows, autoMatched: autoMatched, unmatched: unmatched),
            createdAt: current.createdAt
        )

        session = current
    }

    private func formatDuration(_ durationSeconds: Int?) -> String {
        guard let durationSeconds else { return "--:--" }
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return "\(minutes):" + String(format: "%02d", seconds)
    }
}
