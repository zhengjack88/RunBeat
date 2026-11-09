import SwiftUI

@main
struct RunBeatApp: App {
    @State private var model = MetronomeModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
    }
}
