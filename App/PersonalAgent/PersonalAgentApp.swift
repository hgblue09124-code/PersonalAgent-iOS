import SwiftUI
import PAComposition
import PAKernel

@main
struct PersonalAgentApp: App {
    @State private var session: KernelSession?
    @State private var initializationError: String?
    @AppStorage("app.language") private var appLanguage = "vi"

    var body: some Scene {
        WindowGroup {
            Group {
                if let session {
                    RootView(session: session)
                } else if let initializationError {
                    VStack(spacing: 12) {
                        Text("Initialization failed: \(initializationError)")
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task {
                                await initialize()
                            }
                        }
                    }
                    .padding()
                } else {
                    ProgressView("Starting kernel")
                        .task {
                            await initialize()
                        }
                }
            }
            .dynamicTypeSize(.xSmall ... .accessibility3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.all)
            .environment(\.locale, Locale(identifier: appLanguage))
            .id(appLanguage)
            .onAppear {
                if !UserDefaults.standard.bool(forKey: "app.language.vi-migrated-v1") {
                    appLanguage = "vi"
                    UserDefaults.standard.set(true, forKey: "app.language.vi-migrated-v1")
                }
            }
        }
    }

    private func initialize() async {
        initializationError = nil
        do {
            let root = try await M8CompositionRoot()
            let state = await root.session.currentState()
            let newSession = KernelSession(composition: root, state: state)
            session = newSession
            await newSession.refresh()
            await newSession.prepareActiveModel()
        } catch {
            initializationError = String(describing: error)
        }
    }
}
