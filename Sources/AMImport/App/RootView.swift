import SwiftUI
import Foundation

struct RootView: View {
    @StateObject private var importViewModel = ImportSessionViewModel(
        authorizer: MusicAuthorizationService(),
        snapshotter: LibrarySnapshotService(provider: MusicAppLibraryProvider())
    )
    @State private var session: ImportSession?
    @State private var selection: AppSection = .importFlow

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("AMImport")
        } detail: {
            switch selection {
            case .importFlow:
                ImportView(viewModel: importViewModel) { updated in
                    session = updated
                }
            case .resolveFlow:
                if session == nil {
                    ContentUnavailableView("No Import Session", systemImage: "magnifyingglass")
                } else {
                    ResolveMatchesView(session: $session)
                }
            case .exportFlow:
                ExportView(
                    session: session,
                    viewModel: ExportViewModel(exporter: MusicAppBridge())
                )
            }
        }
        .onChange(of: importViewModel.session) { _, newSession in
            session = newSession
            if newSession != nil {
                selection = .resolveFlow
            }
        }
    }
}

private enum AppSection: String, CaseIterable, Identifiable {
    case importFlow
    case resolveFlow
    case exportFlow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .importFlow:
            return "Import"
        case .resolveFlow:
            return "Resolve"
        case .exportFlow:
            return "Export"
        }
    }

    var icon: String {
        switch self {
        case .importFlow:
            return "tray.and.arrow.down"
        case .resolveFlow:
            return "checklist"
        case .exportFlow:
            return "square.and.arrow.up"
        }
    }
}

private struct MusicAppLibraryProvider: LibrarySongProviding {
    @MainActor
    func fetchPage(offset: Int, limit: Int) async throws -> [LibraryTrack] {
        guard offset == 0 else {
            return []
        }
        let allTracks = try fetchAllTracksWithAppleScript()
        return Array(allTracks.prefix(limit))
    }

    private func fetchAllTracksWithAppleScript() throws -> [LibraryTrack] {
        let separator = "\u{1F}"
        let escapedSeparator = separator.replacingOccurrences(of: "\\", with: "\\\\")
        let script = """
        tell application "Music"
            set outputLines to {}
            repeat with t in tracks of library playlist 1
                set trackID to persistent ID of t as string
                set trackName to ""
                set trackArtist to ""
                set trackAlbum to ""
                set trackDuration to ""

                try
                    set trackName to name of t as string
                end try
                try
                    set trackArtist to artist of t as string
                end try
                try
                    set trackAlbum to album of t as string
                end try
                try
                    set trackDuration to duration of t as string
                end try

                set end of outputLines to (trackID & "\(escapedSeparator)" & trackName & "\(escapedSeparator)" & trackArtist & "\(escapedSeparator)" & trackAlbum & "\(escapedSeparator)" & trackDuration)
            end repeat
            set AppleScript's text item delimiters to linefeed
            return outputLines as text
        end tell
        """

        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw MusicAppLibraryProviderError.compilationFailed
        }
        guard let output = appleScript.executeAndReturnError(&errorInfo).stringValue else {
            let message = (errorInfo?[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error."
            throw MusicAppLibraryProviderError.executionFailed(message)
        }

        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> LibraryTrack? in
                let parts = line.split(separator: Character(separator), omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 5 else { return nil }

                let id = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let artist = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
                let album = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
                let duration = Int(parts[4].trimmingCharacters(in: .whitespacesAndNewlines))

                guard !id.isEmpty, !title.isEmpty, !artist.isEmpty else { return nil }
                return LibraryTrack(
                    id: id,
                    title: title,
                    artist: artist,
                    album: album.isEmpty ? nil : album,
                    durationSeconds: duration,
                    isrc: nil
                )
            }
    }
}

private enum MusicAppLibraryProviderError: LocalizedError {
    case compilationFailed
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .compilationFailed:
            return "Unable to compile Music library query."
        case let .executionFailed(message):
            return "Unable to read tracks from Music app: \(message)"
        }
    }
}
