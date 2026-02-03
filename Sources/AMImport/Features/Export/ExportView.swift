import SwiftUI

@MainActor
final class ExportViewModel: ObservableObject {
    @Published var mode: ExportMode = .newPlaylist
    @Published var playlistName = "AMImport Results"
    @Published var statusMessage = ""
    @Published var isExporting = false

    private let exporter: MusicAppControlling

    init(exporter: MusicAppControlling) {
        self.exporter = exporter
    }

    func export(session: ImportSession) async {
        let trackIDs = session.decisions.compactMap { snapshot -> String? in
            switch snapshot.status {
            case .autoMatched, .userMatched:
                return snapshot.selectedTrackID
            case .unmatched, .skipped:
                return nil
            }
        }

        guard !trackIDs.isEmpty else {
            statusMessage = "No resolved tracks to export."
            return
        }

        isExporting = true
        defer { isExporting = false }

        do {
            switch mode {
            case .newPlaylist:
                let name = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else {
                    statusMessage = "Playlist name is required."
                    return
                }
                try await exporter.createPlaylist(name: name, trackIDs: trackIDs)
                statusMessage = "Created playlist '\(name)' with \(trackIDs.count) tracks."
            case .enqueue:
                try await exporter.enqueue(trackIDs: trackIDs)
                statusMessage = "Enqueued \(trackIDs.count) tracks."
            }
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}

struct ExportView: View {
    @StateObject private var viewModel: ExportViewModel
    let session: ImportSession?

    init(session: ImportSession?, viewModel: @autoclosure @escaping () -> ExportViewModel) {
        self.session = session
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export")
                .font(.title2)

            Picker("Output", selection: $viewModel.mode) {
                Text("New Playlist").tag(ExportMode.newPlaylist)
                Text("Enqueue Tracks").tag(ExportMode.enqueue)
            }
            .pickerStyle(.segmented)

            if viewModel.mode == .newPlaylist {
                TextField("Playlist name", text: $viewModel.playlistName)
                    .textFieldStyle(.roundedBorder)
            }

            Button(viewModel.isExporting ? "Exporting..." : "Run Export") {
                guard let session else { return }
                Task {
                    await viewModel.export(session: session)
                }
            }
            .disabled(viewModel.isExporting || session == nil)

            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
    }
}
