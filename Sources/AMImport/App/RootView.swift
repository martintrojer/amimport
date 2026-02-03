import SwiftUI

struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("AMImport")
                .font(.largeTitle)
            Text("CSV import support coming first")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 400)
    }
}
