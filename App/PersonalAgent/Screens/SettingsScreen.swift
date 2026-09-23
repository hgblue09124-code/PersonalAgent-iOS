import SwiftUI

struct SettingsScreen: View {
    var body: some View {
        ScreenScaffold(title: "Settings", systemImage: "gear") {
            settingsContent
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        MilestoneBanner()
        statusRows
        footerNote
    }

    @ViewBuilder
    private var statusRows: some View {
        StatusRow(title: "Secrets", value: "Keychain contract (M0)")
        StatusRow(title: "Target", value: "iPhone 12 Pro Max")
        StatusRow(title: "UI", value: "SwiftUI, local-first")
    }

    private var footerNote: some View {
        Text("API keys will never be stored in SwiftData or UserDefaults.")
            .foregroundStyle(.secondary)
    }
}
