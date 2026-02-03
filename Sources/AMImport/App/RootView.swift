import SwiftUI

struct RootView: View {
    @StateObject private var importViewModel = ImportSessionViewModel(
        authorizer: DevelopmentAuthorizer(),
        snapshotter: LibrarySnapshotService(provider: EmptyLibraryProvider())
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

private struct DevelopmentAuthorizer: MusicAuthorizing {
    @MainActor
    func currentStatus() -> MusicAuthorizationStatus { .authorized }
    @MainActor
    func request() async -> MusicAuthorizationStatus { .authorized }
}

private struct EmptyLibraryProvider: LibrarySongProviding {
    @MainActor
    func fetchPage(offset: Int, limit: Int) async throws -> [LibraryTrack] { [] }
}
