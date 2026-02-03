import XCTest
@testable import AMImport

final class MusicAuthorizationServiceTests: XCTestCase {
    @MainActor
    func test_permissionState_mapsDenied() {
        let viewModel = MusicAuthorizationViewModel(authorizer: StubAuthorizer(status: .denied))

        XCTAssertEqual(viewModel.permissionState, .denied)
        XCTAssertEqual(viewModel.userMessage, "Apple Music access is denied. Please enable it in System Settings.")
    }

    @MainActor
    func test_permissionState_mapsRestricted() {
        let viewModel = MusicAuthorizationViewModel(authorizer: StubAuthorizer(status: .restricted))

        XCTAssertEqual(viewModel.permissionState, .restricted)
        XCTAssertEqual(viewModel.userMessage, "Apple Music access is restricted on this device/account.")
    }

    @MainActor
    func test_permissionState_mapsNotDetermined() {
        let viewModel = MusicAuthorizationViewModel(authorizer: StubAuthorizer(status: .notDetermined))

        XCTAssertEqual(viewModel.permissionState, .notDetermined)
        XCTAssertEqual(viewModel.userMessage, "Apple Music access has not been requested yet.")
    }
}

private struct StubAuthorizer: MusicAuthorizing {
    let status: MusicAuthorizationStatus

    @MainActor
    func currentStatus() -> MusicAuthorizationStatus { status }
    @MainActor
    func request() async -> MusicAuthorizationStatus { status }
}
