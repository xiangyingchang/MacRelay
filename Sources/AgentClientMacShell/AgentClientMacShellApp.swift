import SwiftUI

@main
struct AgentClientMacShellApp: App {
    var body: some Scene {
        WindowGroup {
            MacShellView()
                .frame(minWidth: 1240, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
