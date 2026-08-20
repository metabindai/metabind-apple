import SwiftUI

@main
struct MetabindFinanceDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 480, height: 720)
        #endif
    }
}
