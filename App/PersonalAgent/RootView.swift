import SwiftUI
import PAArchitecture

struct RootView: View {
    @ObservedObject var session: KernelSession

    var body: some View {
        TabView {
            AgentScreen(session: session)
                .tabItem { Label("Agent", systemImage: "sparkles") }
            ModelsScreen(session: session)
                .tabItem { Label("Models", systemImage: "cube.box") }
            ProvidersScreen(session: session)
                .tabItem { Label("Providers", systemImage: "server.rack") }
            SkillsScreen(session: session)
                .tabItem { Label("Skills", systemImage: "puzzlepiece") }
            SettingsScreen(session: session)
                .tabItem { Label("Settings", systemImage: "gearshape") }
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
