import SwiftUI

struct TasksScreen: View {
    @ObservedObject var session: KernelSession

    var body: some View {
        ScreenScaffold(title: "Tasks", systemImage: "checklist") {
            GlassPanel {
                HStack(spacing: 12) {
                    Image(systemName: session.executionProgress != nil ? "sparkles" : "checklist")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.executionProgress != nil ? "Agent is working" : "Task surface")
                            .font(.headline)
                        Text(session.executionProgress?.detail ?? "Live execution state is reflected here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            if let progress = session.executionProgress {
                GlassPanel {
                    HStack(spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 3) {
                            Text(progress.title).font(.headline)
                            Text(progress.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            } else if let result = session.executionResult {
                GlassPanel {
                    Label("Latest result", systemImage: "checkmark.circle.fill").font(.headline)
                    Text(result).textSelection(.enabled)
                }
            } else if let error = session.lastError {
                GlassPanel {
                    Label("Execution needs attention", systemImage: "exclamationmark.triangle.fill").font(.headline)
                    Text(error).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }

            GlassPanel {
                StatusRow(title: "Agent", value: session.state.lifecycle.rawValue)
                StatusRow(title: "Provider", value: session.providerID)
                StatusRow(title: "Skills", value: "\(session.skillManifests.count)")
                StatusRow(title: "Memory", value: "\(session.memoryRecords.count)")
            }
        }
    }
}
