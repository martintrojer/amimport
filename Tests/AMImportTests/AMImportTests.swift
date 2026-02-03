import XCTest
@testable import AMImport

final class AMImportTests: XCTestCase {
    @MainActor
    func testAppModuleLoads() {
        _ = RootView()
    }
}
