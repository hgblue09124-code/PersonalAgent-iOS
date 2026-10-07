import SwiftUI
import PAKernel
import PARuntime

struct AgentScreen: View {
    @ObservedObject var session: KernelSession
    @Binding var showWorkspace: Bool
    @State private var task = ""
    @State private var showActivity = false
    @State private var showAgentPanel = false
    @FocusState private var focused: Bool

    private var working: Bool { session.executionProgress != nil }
    private var running: Bool { session.state.lifecycle.rawValue.lowercased() == "running" }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.11, blue: 0.34), Color(red: 0.025, green: 0.035, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            Circle().fill(AgentDesign.accent.opacity(0.22)).frame(width: 300).blur(radius: 90).offset(x: 130, y: -250)
            ScrollView {
                VStack(spacing: 0) {
                    header
                    hero
                    composer
                    liveState
                    openBeta
                }
                .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 28)
            }.scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showActivity) { ActivitySheet(session: session).presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
        .sheet(isPresented: $showAgentPanel) { AgentContextSheet(session: session).presentationDetents([.fraction(0.42), .large]).presentationDragIndicator(.visible) }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Button { showAgentPanel = true } label: {
                HStack(spacing: 8) {
                    AgentOrb(isActive: running, isThinking: working).frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("PERSONAL AGENT").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.1)
                        Text(working ? "Working now" : "Ready").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.55))
                    }
                }.foregroundStyle(.white)
            }.buttonStyle(.plain)
            Spacer()
            Button { showActivity = true } label: { headerButton("waveform.path.ecg") }
            Button { showWorkspace = true } label: { headerButton("circle.hexagongrid.fill") }
            Menu {
                Button("Start") { Task { await session.start() } }
                Button("Pause") { Task { await session.pause() } }
                Button("Resume") { Task { await session.resume() } }
                Button("Stop", role: .destructive) { Task { await session.stop() } }
            } label: { headerButton("ellipsis") }
        }
    }

    private func headerButton(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            .frame(width: 36, height: 36).background(.white.opacity(0.09), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
    }

    private var hero: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 34)
            Button { showAgentPanel = true } label: { AgentOrb(isActive: running, isThinking: working).frame(width: 92, height: 92) }.buttonStyle(.plain)
            Text(greeting).font(.system(size: 38, weight: .black, design: .rounded)).tracking(-1.4).foregroundStyle(.white).multilineTextAlignment(.center)
            HStack(spacing: 7) {
                Circle().fill(working ? .white : .white.opacity(0.68)).frame(width: 6, height: 6)
                Text(subtitle).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.68))
            }
            Spacer().frame(height: 20)
        }.frame(maxWidth: .infinity)
    }

    private var composer: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles").foregroundStyle(.white.opacity(0.45))
            TextField("Ask your Agent…", text: $task, axis: .vertical).textFieldStyle(.plain).foregroundStyle(.white).tint(.white).lineLimit(1...4).focused($focused).submitLabel(.send).onSubmit(run)
            Button(action: run) {
                Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold)).foregroundStyle(.black).frame(width: 40, height: 40).background(.white, in: Circle())
            }.disabled(task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isSubmitting)
        }
        .padding(7).padding(.leading, 10).background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
    }

    @ViewBuilder private var liveState: some View {
        if let p = session.executionProgress { state("WORKING", p.title, p.detail, "sparkles") }
        else if let r = session.executionResult { state("COMPLETED", "Latest result", r, "checkmark.circle.fill") }
        else if let e = session.lastError { state("NEEDS ATTENTION", "The Agent could not complete the request", e, "exclamationmark.triangle.fill") }
    }

    private func state(_ eyebrow: String, _ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol).foregroundStyle(.white).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.white.opacity(0.5))
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.66)).lineLimit(5)
            }
            Spacer()
        }
        .padding(14).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 1)).padding(.top, 14)
    }

    private var openBeta: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("OPEN BETA").font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button("Workspace") { showWorkspace = true }.font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
            }
            HStack(spacing: 8) {
                tile("Chat", "bubble.left.and.bubble.right")
                tile("Models", "cube.box")
                tile("Memory", "brain")
                tile("Skills", "puzzlepiece")
            }
        }.padding(.top, 24)
    }

    private func tile(_ title: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Image(systemName: symbol).font(.subheadline.bold()); Text(title).font(.caption.weight(.semibold)) }
            .foregroundStyle(.white.opacity(0.82)).padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var greeting: String {
        switch session.state.lifecycle.rawValue.lowercased() {
        case "running": return working ? "I’m on it." : "Ready to work."
        case "paused": return "I’m paused."
        default: return "What can I do?"
        }
    }

    private var subtitle: String {
        if working { return "Working through your request." }
        if session.executionResult != nil { return "Done. What’s next?" }
        return "One thought in. One useful action out."
    }

    private func run() {
        let value = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !session.isSubmitting else { return }
        task = ""; focused = false
        Task { await session.submitGoal(value) }
    }
}

private struct AgentContextSheet: View {
    @ObservedObject var session: KernelSession
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        AgentOrb(isActive: session.state.lifecycle.rawValue.lowercased() == "running", isThinking: session.executionProgress != nil).frame(width: 58, height: 58)
                        VStack(alignment: .leading, spacing: 3) { Text("Personal Agent").font(.title2.bold()); Text(session.executionProgress == nil ? "Ready for your next instruction." : "Working on the current request.").font(.subheadline).foregroundStyle(.secondary) }
                    }.padding(.vertical, 6)
                }
                Section("Live") {
                    StatusRow(title: "Lifecycle", value: session.state.lifecycle.rawValue.capitalized)
                    StatusRow(title: "Provider", value: session.providerLifecycle)
                    StatusRow(title: "Models", value: "\(session.installedModels.count)")
                    StatusRow(title: "Memory", value: "\(session.memoryRecords.count) records")
                }
            }.navigationTitle("Agent").navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ActivitySheet: View {
    @ObservedObject var session: KernelSession
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { VStack(alignment: .leading, spacing: 3) { Text("Activity").font(.largeTitle.bold()); Text("A live view of what the Agent is doing.").font(.subheadline).foregroundStyle(.secondary) }; Spacer(); StatusBadge(title: session.executionProgress == nil ? "Idle" : "Working", tint: session.executionProgress == nil ? .secondary : AgentDesign.accent) }
                    if let p = session.executionProgress { GlassPanel { Label(p.title, systemImage: "sparkles").font(.headline); Text(p.detail).foregroundStyle(.secondary) } }
                    else if let r = session.executionResult { GlassPanel { Label("Latest result", systemImage: "checkmark.circle.fill").font(.headline); Text(r).foregroundStyle(.secondary).textSelection(.enabled) } }
                    else { GlassPanel { Label("Quiet", systemImage: "moon.stars.fill").font(.headline); Text("The Agent is ready for your next instruction.").foregroundStyle(.secondary) } }
                    if !session.chatHistory.isEmpty {
                        GlassPanel {
                            HStack { Text("Recent conversation").font(.headline); Spacer(); Text("\(session.chatHistory.count) turns").font(.caption).foregroundStyle(.secondary) }
                            ForEach(session.chatHistory.suffix(8)) { turn in VStack(alignment: .leading, spacing: 3) { Text(turn.role == .user ? "You" : "Agent").font(.caption.weight(.bold)).foregroundStyle(.secondary); Text(turn.content).font(.subheadline) }.padding(.vertical, 4) }
                        }
                    }
                }.padding(18)
            }.background(Color(.systemGroupedBackground)).navigationTitle("Activity").navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct AgentOrb: View {
    let isActive: Bool
    let isThinking: Bool
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [.white.opacity(0.9), Color(red: 0.58, green: 0.66, blue: 1).opacity(0.76), Color(red: 0.16, green: 0.25, blue: 0.91).opacity(0.98)], center: UnitPoint(x: 0.34, y: 0.28), startRadius: 2, endRadius: 48))
            Circle().stroke(.white.opacity(0.34), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
        .scaleEffect(pulse ? (isThinking ? 1.07 : isActive ? 1.035 : 1) : 1)
        .animation(.easeInOut(duration: isThinking ? 0.58 : 1.8).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }
        .accessibilityLabel(isThinking ? "Agent thinking" : isActive ? "Agent active" : "Agent idle")
    }
}
