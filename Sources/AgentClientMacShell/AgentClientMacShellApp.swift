import SwiftUI

@main
struct AgentClientMacShellApp: App {
    var body: some Scene {
        WindowGroup {
            MacShellView()
                .frame(minWidth: 1240, minHeight: 760)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
