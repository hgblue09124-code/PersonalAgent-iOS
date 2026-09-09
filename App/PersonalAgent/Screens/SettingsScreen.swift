import SwiftUI

struct SettingsScreen: View {
    var body: some View {
        ScreenScaffold(title: "Settings", systemImage: "gear") {
            MilestoneBanner()
            StatusRow(title: "Secrets", value: "Keychain contract (M0)")
            StatusRow(title: "Target", value: "iPhone 12 Pro Max")
            StatusRow(title: "UI", value: "SwiftUI, local-first")
            Text("API keys will never be stored in SwiftData or UserDefaults.")
                .foregroundStyle(.secondary)
        }
    }
}
