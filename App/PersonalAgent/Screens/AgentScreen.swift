import SwiftUI
import PAKernel

struct AgentScreen: View {
    @ObservedObject var session: KernelSession
    @State private var taskInput: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header / Title
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PERSONAL AGENT")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(session.state.identity.displayName)
                            .font(.title2.bold())
                    }

                    // Task Input & Control Area
                    VStack(alignment: .leading, spacing: 12) {
                        if session.executionState == .idle {
                            Text("What should I do?")
                                .font(.headline)

                            TextField("Enter a task for the agent...", text: $taskInput, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...5)

                            if let validationError = session.emptyTaskValidationError {
                                Text(validationError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            HStack {
                                Spacer()
                                Button {
                                    Task {
                                        await session.runTask(taskInput)
                                    }
                                } label: {
                                    Label("Run Agent", systemImage: "play.fill")
                                        .font(.subheadline.bold())
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(session.executionState == .running)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("TASK")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                                Text(session.currentTask)
                                    .font(.body.weight(.medium))
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(16)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                    // CURRENT TASK Execution Pipeline
                    if session.executionState != .idle {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("CURRENT TASK")
                                    .font(.headline)
                                Spacer()
                                if session.executionState == .running {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("Agent is working...")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } else if session.executionState == .completed {
                                    Text("Verified Success")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.2), in: Capsule())
                                        .foregroundStyle(.green)
                                } else if session.executionState == .failed {
                                    Text("Agent Stopped")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.red.opacity(0.2), in: Capsule())
                                        .foregroundStyle(.red)
                                }
                            }

                            Divider()

                            // Pipeline Steps
                            VStack(spacing: 12) {
                                PipelineStepRow(
                                    title: "Reasoning",
                                    status: session.reasoningStatus,
                                    summary: session.reasoningSummary
                                )
                                PipelineStepRow(
                                    title: "Action",
                                    status: session.actionStatus,
                                    summary: session.actionSummary
                                )
                                PipelineStepRow(
                                    title: "Observation",
                                    status: session.observationStatus,
                                    summary: session.observationSummary
                                )
                                PipelineStepRow(
                                    title: "Verification",
                                    status: session.verificationStatus,
                                    summary: session.verificationSummary
                                )
                            }

                            Divider()

                            // Result Section
                            if session.executionState == .completed {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Result")
                                        .font(.subheadline.bold())
                                    Text(session.resultSummary ?? "Task verified and completed successfully.")
                                        .font(.body)
                                        .foregroundStyle(.primary)

                                    HStack {
                                        Label("Verified", systemImage: "checkmark.seal.fill")
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.green)

                                        Spacer()

                                        Button("New Task") {
                                            taskInput = ""
                                            session.resetTask()
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    .padding(.top, 8)
                                }
                                .padding(12)
                                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            } else if session.executionState == .failed {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Agent stopped")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.red)

                                    Text("Reason")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)

                                    Text(session.userSafeFailureReason ?? session.lastError ?? "Execution failed or verification was rejected.")
                                        .font(.body)
                                        .foregroundStyle(.red)

                                    HStack {
                                        Spacer()
                                        Button("Retry") {
                                            Task {
                                                await session.retryTask()
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.red)

                                        Button("New Task") {
                                            taskInput = ""
                                            session.resetTask()
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    .padding(.top, 8)
                                }
                                .padding(12)
                                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(16)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }

                    // System Runtime Status Summary
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SYSTEM STATE")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)

                        HStack {
                            StatusRow(title: "Lifecycle", value: session.state.lifecycle.rawValue)
                            Spacer()
                            StatusRow(title: "Phase", value: session.state.phase.rawValue)
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(20)
            }
            .navigationTitle("Agent")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct PipelineStepRow: View {
    let title: String
    let status: ExecutionStepStatus
    let summary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.body)
                Spacer()
                Text(status.rawValue)
                    .font(.body.bold().monospaced())
                    .foregroundStyle(statusColor(status))
            }

            if let summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusColor(_ status: ExecutionStepStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .inProgress: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}
