import SwiftUI

struct ResolveRow: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let candidateTrackIDs: [String]
    var selectedTrackID: String?
    var status: MatchStatus
}

struct ResolveMatchesView: View {
    @State private var unresolvedRows: [ResolveRow]

    init(session: ImportSession) {
        _unresolvedRows = State(initialValue: Self.buildRows(from: session))
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
                    Text(row.candidateTrackIDs.joined(separator: ", "))
                        .foregroundStyle(.secondary)
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
    }

    private static func buildRows(from session: ImportSession) -> [ResolveRow] {
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
                candidateTrackIDs: snapshot.candidateTrackIDs,
                selectedTrackID: snapshot.selectedTrackID,
                status: snapshot.status
            )
        }
    }

    private func applyFirstCandidate(for rowID: String) {
        guard let index = unresolvedRows.firstIndex(where: { $0.id == rowID }),
              let first = unresolvedRows[index].candidateTrackIDs.first else {
            return
        }

        unresolvedRows[index].selectedTrackID = first
        unresolvedRows[index].status = .userMatched
    }

    private func skip(rowID: String) {
        guard let index = unresolvedRows.firstIndex(where: { $0.id == rowID }) else {
            return
        }

        unresolvedRows[index].status = .skipped
    }
}
