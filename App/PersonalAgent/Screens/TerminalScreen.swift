import SwiftUI
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
    @State private var transcript: [TerminalLine] = []
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
                    transcript.removeAll()
                } label: {
                    Image(systemName: "trash").frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
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
                    .disabled(terminal == nil)
                Button {
                    Task { await executeCommand() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
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
    private func executeCommand() async {
        guard let terminal, !isExecuting else { return }
        let input = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        isExecuting = true
        defer { isExecuting = false }
        command = ""
        let priorOutputCount = await terminal.outputs().count
        appendTranscript(TerminalLine(text: "$ " + input, kind: .command))
        do {
            _ = try await terminal.execute(input, registry: registry)
            let outputs = await terminal.outputs()
            if input == "clear" {
                transcript.removeAll()
            } else {
                for item in outputs.dropFirst(priorOutputCount) {
                    let kind: TerminalLine.Kind = item.stream == .stderr ? .error : .output
                    appendTranscript(TerminalLine(text: item.text, kind: kind))
                }
            }
        } catch {
            appendTranscript(TerminalLine(text: "error: \(error.localizedDescription)", kind: .error))
        }
    }
    private func makeRuntimeRegistry(session: KernelSession?) -> CommandRegistry {
        var commands = BuiltinCommandRegistry.make()
        guard let session else { return commands }

        commands = commands.registering("help") { command, _ in
            guard command.arguments.isEmpty else { throw CommandError.invalidArguments("help") }
            return CommandResult(stdout: "pwd ls cd cat head tail mkdir touch cp mv rm find grep workspace status agent run <request> model status provider status skills list memory status sync status|now clear help\\n")
        }
        commands = commands.registering("status") { command, _ in
            guard command.arguments.isEmpty else { throw CommandError.invalidArguments("status") }
            return CommandResult(stdout: await session.terminalStatus())
        }
        commands = commands.registering("agent") { command, _ in
            guard command.arguments.first == "run", command.arguments.count >= 2 else {
                throw CommandError.invalidArguments("agent run <request>")
            }
            let request = command.arguments.dropFirst().joined(separator: " ")
            return CommandResult(stdout: await session.runFromTerminal(request))
        }
        commands = commands.registering("skills") { command, _ in
            guard command.arguments == ["list"] else { throw CommandError.invalidArguments("skills list") }
            return CommandResult(stdout: await session.terminalSkillsList())
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
            guard command.arguments == ["status"] || command.arguments == ["now"] else {
                throw CommandError.invalidArguments("sync status|now")
            }
            if command.arguments[0] == "now" {
                return CommandResult(stdout: await session.syncGitHubWorkspace())
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
