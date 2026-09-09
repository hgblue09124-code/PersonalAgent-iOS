import SwiftUI

struct MemoryScreen: View {
    /// Names from the M0 memory contract. The app does not import PAMemory.
    private let reservedKinds = [
        "working", "episodic", "semantic", "preference", "procedural",
    ]

    var body: some View {
        ScreenScaffold(title: "Memory", systemImage: "brain") {
            MilestoneBanner()
            ForEach(reservedKinds, id: \.self) { kind in
                StatusRow(title: kind, value: "contract only · M4")
            }
        }
    }
}
