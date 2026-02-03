import SwiftUI
import AppKit

@main
struct AMImportApp: App {
    private var isHeadlessTestMode: Bool {
        ProcessInfo.processInfo.environment["AMIMPORT_HEADLESS_TEST_MODE"] == "1"
    }

    var body: some Scene {
        WindowGroup {
            if isHeadlessTestMode {
                EmptyView()
                    .frame(width: 1, height: 1)
                    .onAppear {
                        NSApp.setActivationPolicy(.prohibited)
                        for window in NSApp.windows {
                            window.orderOut(nil)
                        }
                    }
            } else {
                RootView()
            }
        }
    }
}
