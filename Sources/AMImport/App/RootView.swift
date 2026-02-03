import SwiftUI

struct RootView: View {
    var body: some View {
        ImportView(
            viewModel: ImportSessionViewModel(
                authorizer: DevelopmentAuthorizer(),
                snapshotter: LibrarySnapshotService(provider: EmptyLibraryProvider())
            )
        )
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
