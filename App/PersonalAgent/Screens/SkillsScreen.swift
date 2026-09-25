import SwiftUI
import PAArchitecture

struct SkillsScreen: View {
    @ObservedObject var session: KernelSession

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "puzzlepiece")
                            .font(.title2)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Agent capabilities")
                                .font(.headline)
                            Text("\(session.moduleIDs.count) available")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Available") {
                    if session.moduleIDs.isEmpty {
                        ContentUnavailableView(
                            "No Skills",
                            systemImage: "puzzlepiece",
                            description: Text("Agent capabilities will appear here when available.")
                        )
                    } else {
                        ForEach(session.moduleIDs, id: \.self) { id in
                            Label(id, systemImage: "checkmark.circle")
                        }
                    }
                }

                Section {
                    Text("Skills represent capabilities the Agent can use. Detailed permissions and actions can be revealed when a capability is selected.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlassScreenBackground())
            .navigationTitle("Skills")
        }
    }
}