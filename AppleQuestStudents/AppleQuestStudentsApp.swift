import SwiftData
import SwiftUI

@main
struct AppleQuestStudentsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: SavedQuest.self)
    }
}
