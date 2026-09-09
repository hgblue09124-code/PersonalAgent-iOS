import SwiftUI
import PAMemory

struct MemoryScreen: View {
    var body: some View {
        ScreenScaffold(title: "Memory", systemImage: "brain") {
            MilestoneBanner()
            ForEach(MemoryKind.allCases, id: \.self) { kind in
                StatusRow(title: kind.rawValue, value: "contract only")
            }
        }
    }
}
