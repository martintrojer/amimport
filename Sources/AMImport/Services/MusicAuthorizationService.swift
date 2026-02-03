import Foundation

enum MusicAuthorizationStatus: Equatable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

enum MusicPermissionState: Equatable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

protocol MusicAuthorizing {
    @MainActor
    func currentStatus() -> MusicAuthorizationStatus
    @MainActor
    func request() async -> MusicAuthorizationStatus
}

struct MusicAuthorizationService: MusicAuthorizing {
    @MainActor
    func currentStatus() -> MusicAuthorizationStatus {
        .notDetermined
    }

    @MainActor
    func request() async -> MusicAuthorizationStatus {
        .notDetermined
    }
}

@MainActor
final class MusicAuthorizationViewModel {
    private let authorizer: MusicAuthorizing

    private(set) var permissionState: MusicPermissionState

    var userMessage: String {
        switch permissionState {
        case .denied:
            return "Apple Music access is denied. Please enable it in System Settings."
        case .restricted:
            return "Apple Music access is restricted on this device/account."
        case .notDetermined:
            return "Apple Music access has not been requested yet."
        case .authorized:
            return "Apple Music access is authorized."
        }
    }

    init(authorizer: MusicAuthorizing) {
        self.authorizer = authorizer
        self.permissionState = Self.map(authorizer.currentStatus())
    }

    func requestPermission() async {
        permissionState = Self.map(await authorizer.request())
    }

    private static func map(_ status: MusicAuthorizationStatus) -> MusicPermissionState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .authorized:
            return .authorized
        }
    }
}
