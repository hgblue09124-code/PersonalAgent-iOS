import SwiftUI
import UIKit
import Foundation
import PAKernel
import PASkills
import PAWorkspace
import PATerminal

private struct TerminalLine: Identifiable {
    enum Kind { case command, output, error }
    let id = UUID()
    let text: String
    let kind: Kind
}

struct TerminalScreen: View {
    @State private var workspace: LocalAgentWorkspace?
    @State private var terminal: TerminalSession?
    @State private var registry = BuiltinCommandRegistry.make()
    @Environment(\.kernelSession) private var kernelSession
    @State private var command = ""
    @State private var isExecuting = false
    @State private var pendingDestructiveCommand: String?
    @State private var showDestructiveConfirmation = false
    @State private var transcript: [TerminalLine] = []
    @State private var transcriptCopied = false
    private let maximumTranscriptLines = 500
    private let maximumTranscriptBytes = 256 * 1024
    @State private var status = "Preparing sandbox…"
    @FocusState private var commandFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(terminal == nil ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AgentOS Terminal").font(.headline)
                    Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = transcript.map(\.text).joined(separator: "\n")
                    transcriptCopied = true
                } label: {
                    Image(systemName: transcriptCopied ? "checkmark" : "doc.on.doc").frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
                .disabled(transcript.isEmpty)
                .accessibilityLabel("Copy terminal output")
                Button {
                    transcript.removeAll()
                    transcriptCopied = false
                } label: {
                    Image(systemName: "trash").frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
                .disabled(transcript.isEmpty || isExecuting)
                .accessibilityLabel("Clear terminal output")
            }
            .padding()

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(transcript) { line in
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(color(for: line.kind))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: transcript.count) { _, _ in
                    guard let last = transcript.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                Text("›").font(.system(.title2, design: .monospaced, weight: .bold)).foregroundStyle(.green)
                TextField("help, status, agent run…, skills list…", text: $command, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...4)
                    .focused($commandFocused)
                    .submitLabel(.send)
                    .onSubmit { Task { await executeCommand() } }
                    .disabled(terminal == nil || isExecuting)
                Button {
                    Task { await executeCommand() }
                } label: {
                    if isExecuting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                }
                .disabled(terminal == nil || isExecuting || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Run terminal command")
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle("Terminal")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepareSandbox() }
        .confirmationDialog(
            "Confirm destructive command",
            isPresented: $showDestructiveConfirmation,
            titleVisibility: .visible
        ) {
            if let pendingDestructiveCommand {
                Button("Run command", role: .destructive) {
                    Task { await executeCommand(confirmed: true, commandToExecute: pendingDestructiveCommand) }
                }
            }
            Button("Cancel", role: .cancel) { pendingDestructiveCommand = nil }
        } message: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Command to run:")
                Text(pendingDestructiveCommand ?? "").font(.caption.monospaced())
                Text("This command may move, overwrite, delete workspace files, or apply remote changes. Review it before continuing.")
            }
        }
    }

    private func color(for kind: TerminalLine.Kind) -> Color {
        switch kind {
        case .command: return .green
        case .output: return .primary
        case .error: return .red
        }
    }

    @MainActor
    private func prepareSandbox() async {
        guard terminal == nil else { return }
        do {
            let workspace = try LocalAgentWorkspace.documents()
            try await workspace.prepare()
            self.workspace = workspace
            terminal = TerminalSession(context: CommandContext(workspace: workspace))
            registry = makeRuntimeRegistry(session: kernelSession)
            let rootName = await workspace.rootURL.lastPathComponent
            status = "Sandbox ready · \(rootName)"
            appendTranscript(TerminalLine(text: "Workspace and Agent Runtime connected. Type help to list commands.", kind: .output))
        } catch {
            status = "Sandbox unavailable"
            appendTranscript(TerminalLine(text: error.localizedDescription, kind: .error))
        }
    }

    @MainActor
    private func executeCommand(confirmed: Bool = false, commandToExecute: String? = nil) async {
        guard let terminal, !isExecuting else { return }
        let input = (commandToExecute ?? command).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        isExecuting = true
        defer { isExecuting = false }
        if commandToExecute == nil { command = "" }
        if confirmed { pendingDestructiveCommand = nil }
        let priorOutputCount = await terminal.outputs().count
        do {
            _ = try await terminal.execute(input, registry: registry, confirmationGranted: confirmed)
            appendTranscript(TerminalLine(text: "$ " + input, kind: .command))
            let outputs = await terminal.outputs()
            if input == "clear" {
                transcript.removeAll()
            } else {
                for item in outputs.dropFirst(priorOutputCount) {
                    let kind: TerminalLine.Kind = item.stream == .stderr ? .error : .output
                    appendTranscript(TerminalLine(text: item.text, kind: kind))
                }
            }
            pendingDestructiveCommand = nil
        } catch let error as CommandError {
            if case .confirmationRequired(_) = error {
                pendingDestructiveCommand = input
                showDestructiveConfirmation = true
                return
            }
            appendTranscript(TerminalLine(text: "$ " + input, kind: .command))
            appendTranscript(TerminalLine(text: "error: \(error.localizedDescription)", kind: .error))
        } catch {
            appendTranscript(TerminalLine(text: "$ " + input, kind: .command))
            appendTranscript(TerminalLine(text: "error: \(error.localizedDescription)", kind: .error))
        }
    }

    private func makeRuntimeRegistry(session: KernelSession?) -> CommandRegistry {
        let authorizer = SettingsTerminalCommandAuthorizer()
        guard let session else {
            return BuiltinCommandRegistry.make(authorizer: authorizer)
        }
        let skillRuntime = session.composition.skillRuntime
        let skillPolicy = UserConfiguredPolicyEvaluator()
        var commands = BuiltinCommandRegistry.make(
            skillRuntime: skillRuntime,
            authorizer: authorizer,
            executeSkill: { request in
                let inputJSON: String
                if let data = request.input.data(using: .utf8),
                   (try? JSONSerialization.jsonObject(with: data)) is [String: Any] {
                    inputJSON = request.input
                } else {
                    let data = try JSONSerialization.data(withJSONObject: ["text": request.input], options: [.sortedKeys])
                    inputJSON = String(decoding: data, as: UTF8.self)
                }
                let skillID = SkillID(rawValue: request.skillID)
                let output = try await skillRuntime.execute(
                    id: skillID,
                    inputJSON: inputJSON,
                    policy: skillPolicy
                )
                guard try await skillRuntime.verify(id: skillID, outputJSON: output) else {
                    throw SkillExecutionError.malformedSkill
                }
                return output
            }
        )

        commands = commands.registering("help") { command, _ in
            guard command.arguments.isEmpty else { throw CommandError.invalidArguments("help") }
            return CommandResult(stdout: "pwd ls cd cat head tail mkdir touch cp mv rm find grep workspace status agent list [query]|show <id>|use <id>|status|run <request> model status provider status skills list [query] skill list [query]|run <id> <JSON input> memory status sync status|preview|now clear help" + "\n")
        }
        commands = commands.registering("status") { command, _ in
            guard command.arguments.isEmpty else { throw CommandError.invalidArguments("status") }
            return CommandResult(stdout: await session.terminalStatus())
        }
        commands = commands.registering("agent") { command, _ in
            guard let action = command.arguments.first else {
                throw CommandError.invalidArguments("agent list [query]|show <id>|use <id>|status|run <request>")
            }
            let args = Array(command.arguments.dropFirst())
            switch action {
            case "list":
                guard args.count <= 1 else { throw CommandError.invalidArguments("agent list [query]") }
                let output = await MainActor.run {
                    let needle = (args.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let matches = session.agentManifests
                        .filter {
                            needle.isEmpty ||
                            $0.id.lowercased().contains(needle) ||
                            $0.name.lowercased().contains(needle) ||
                            $0.description.lowercased().contains(needle)
                        }
                        .sorted { $0.id < $1.id }
                    guard !matches.isEmpty else { return "No Agent profiles found.\n" }
                    return matches.map { agent in
                        let active = agent.id == session.selectedAgentID ? " [ACTIVE]" : ""
                        return "\(agent.id)\(active)\tv\(agent.version.major).\(agent.version.minor).\(agent.version.patch)\t\(agent.name) · \(agent.skillIDs.count) Skills"
                    }.joined(separator: "\n") + "\n"
                }
                return CommandResult(stdout: output)
            case "show":
                guard args.count == 1 else { throw CommandError.invalidArguments("agent show <id>") }
                let output = await MainActor.run {
                    guard let agent = session.agentManifests.first(where: { $0.id == args[0] }) else {
                        return "Agent not found: \(args[0])\n"
                    }
                    let skills = agent.skillIDs.map(\.rawValue).sorted()
                    return [
                        "ID: \(agent.id)",
                        "Name: \(agent.name)",
                        "Version: \(agent.version.major).\(agent.version.minor).\(agent.version.patch)",
                        "Description: \(agent.description)",
                        "Allowed Skills: \(skills.isEmpty ? "none" : skills.joined(separator: ", "))",
                        "Rule: \(agent.instructions.isEmpty ? "none" : agent.instructions)"
                    ].joined(separator: "\n") + "\n"
                }
                return CommandResult(stdout: output)
            case "use":
                guard args.count == 1 else { throw CommandError.invalidArguments("agent use <id>") }
                return await MainActor.run {
                    guard session.agentManifests.contains(where: { $0.id == args[0] }) else {
                        return CommandResult(stderr: "Agent not found: \(args[0])\n", exitCode: 1)
                    }
                    session.selectAgent(id: args[0])
                    guard session.selectedAgentID == args[0] else {
                        return CommandResult(stderr: "Agent is busy; selection was not changed.\n", exitCode: 1)
                    }
                    return CommandResult(stdout: "Active Agent set to \(args[0]).\n")
                }
            case "status":
                guard args.isEmpty else { throw CommandError.invalidArguments("agent status") }
                let status = await MainActor.run {
                    "Active Agent: \(session.selectedAgentID)\nTeam mode: \(session.teamModeEnabled ? "enabled" : "disabled")\n"
                }
                return CommandResult(stdout: status)
            case "run":
                guard !args.isEmpty else { throw CommandError.invalidArguments("agent run <request>") }
                return CommandResult(stdout: await session.runFromTerminal(args.joined(separator: " ")))
            default:
                throw CommandError.invalidArguments("agent list [query]|show <id>|use <id>|status|run <request>")
            }
        }
        commands = commands.registering("skills") { command, _ in
            guard command.arguments.first == "list", command.arguments.count <= 2 else {
                throw CommandError.invalidArguments("skills list [query]")
            }
            let query = command.arguments.dropFirst().first ?? ""
            return CommandResult(stdout: await session.terminalSkillsList(query: query))
        }
        commands = commands.registering("model") { command, _ in
            guard command.arguments == ["status"] else { throw CommandError.invalidArguments("model status") }
            return CommandResult(stdout: await session.terminalModelStatus())
        }
        commands = commands.registering("provider") { command, _ in
            guard command.arguments == ["status"] else { throw CommandError.invalidArguments("provider status") }
            return CommandResult(stdout: await session.terminalProviderStatus())
        }
        commands = commands.registering("memory") { command, _ in
            guard command.arguments == ["status"] else { throw CommandError.invalidArguments("memory status") }
            return CommandResult(stdout: await session.terminalMemoryStatus())
        }
        commands = commands.registering("sync") { command, _ in
            guard command.arguments == ["status"] || command.arguments == ["now"] || command.arguments == ["preview"] else {
                throw CommandError.invalidArguments("sync status|preview|now")
            }
            if command.arguments[0] == "now" {
                return CommandResult(stdout: await session.syncGitHubWorkspace())
            }
            if command.arguments[0] == "preview" {
                return CommandResult(stdout: await session.syncGitHubWorkspace(preview: true))
            }
            return CommandResult(stdout: await session.terminalSyncStatus())
        }
        return commands
    }

    private func appendTranscript(_ line: TerminalLine) {
        transcript.append(line)
        var retainedBytes = transcript.reduce(0) { $0 + $1.text.utf8.count }
        while transcript.count > maximumTranscriptLines || retainedBytes > maximumTranscriptBytes {
            let removed = transcript.removeFirst()
            retainedBytes -= removed.text.utf8.count
        }
    }

}
