import SwiftUI
import PAComposition
import PAArchitecture
import PAFoundation

struct RootView: View {
    let composition: M0CompositionRoot

    var body: some View {
        TabView {
            ChatScreen()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
            AgentScreen(gate: composition.milestone)
                .tabItem { Label("Agent", systemImage: "cpu") }
            TasksScreen()
                .tabItem { Label("Tasks", systemImage: "checklist") }
            MemoryScreen()
                .tabItem { Label("Memory", systemImage: "brain") }
            SkillsScreen()
                .tabItem { Label("Skills", systemImage: "puzzlepiece") }
            ProvidersScreen()
                .tabItem { Label("Providers", systemImage: "server.rack") }
            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .environment(\.milestoneGate, composition.milestone)
    }
}

private struct MilestoneKey: EnvironmentKey {
    static let defaultValue: MilestoneGate = .m0
}

extension EnvironmentValues {
    var milestoneGate: MilestoneGate {
        get { self[MilestoneKey.self] }
        set { self[MilestoneKey.self] = newValue }
    }
}
