import SwiftUI

@main
struct CoolapkMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 980, minHeight: 660)
        }
        .windowResizability(.contentMinSize)
    }
}
