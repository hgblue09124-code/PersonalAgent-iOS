import SwiftUI
import PAArchitecture

struct RootView: View {
    @ObservedObject var session: KernelSession

    var body: some View {
        TabView {
            ChatScreen(session: session)
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
            AgentScreen(session: session)
                .tabItem { Label("Agent", systemImage: "cpu") }
            TasksScreen()
                .tabItem { Label("Tasks", systemImage: "checklist") }
            MemoryScreen()
                .tabItem { Label("Memory", systemImage: "brain") }
            SkillsScreen(session: session)
                .tabItem { Label("Skills", systemImage: "puzzlepiece") }
            ProvidersScreen(session: session)
                .tabItem { Label("Providers", systemImage: "server.rack") }
            SettingsScreen(session: session)
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .environment(\.milestoneGate, session.milestone)
        .task { await session.refresh() }
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
