import SwiftUI

@main
struct SetsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(WorkoutManager.shared)
        }
    }
}
