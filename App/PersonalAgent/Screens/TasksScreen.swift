import SwiftUI

struct TasksScreen: View {
    var body: some View {
        ScreenScaffold(title: "Tasks", systemImage: "checklist") {
            MilestoneBanner()
            Text("Agency loop and task progress land in M7 / M9.")
                .foregroundStyle(.secondary)
        }
    }
}
