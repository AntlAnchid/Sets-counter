import SwiftUI

struct ContentView: View {
    @EnvironmentObject var m: WorkoutManager
    @Environment(\.scenePhase) private var phase

    var body: some View {
        TabView {
            WorkoutTab().tabItem { Label("Тренування", systemImage: "dumbbell.fill") }
            HistoryTab().tabItem { Label("Історія", systemImage: "clock.arrow.circlepath") }
        }
        .onChange(of: phase) { _, new in
            if new == .active { Task { await m.startIfPending(); await m.refresh() } }
        }
        .task { await m.startIfPending() }
    }
}
