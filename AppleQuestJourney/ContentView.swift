import SwiftUI

struct ContentView: View {
    var body: some View {
        #if os(macOS)
        MentorDashboardView()
        #else
        Text("Apple Quest Journey — Mentor Studio (macOS)")
        #endif
    }
}

#Preview {
    ContentView()
}
