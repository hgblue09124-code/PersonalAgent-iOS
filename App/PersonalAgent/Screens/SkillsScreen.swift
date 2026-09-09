import SwiftUI

struct SkillsScreen: View {
    var body: some View {
        ScreenScaffold(title: "Skills", systemImage: "puzzlepiece") {
            MilestoneBanner()
            Text("Skill store and execution are M5. No hardcoded production skills.")
                .foregroundStyle(.secondary)
        }
    }
}
