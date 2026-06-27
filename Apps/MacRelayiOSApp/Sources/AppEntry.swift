import AgentClientiOS
import SwiftUI

@main
struct MacRelayiOSAppEntry: App {
    @StateObject private var viewModel = RelayClientViewModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                PairingView(viewModel: viewModel)
                    .tabItem { Label("Pair", systemImage: "link") }

                SessionWorkspaceView(viewModel: viewModel)
                    .tabItem { Label("Session", systemImage: "rectangle.3.group") }

                ConnectionStatusView(viewModel: viewModel)
                    .tabItem { Label("Net", systemImage: "antenna.radiowaves.left.and.right") }
            }
            .onOpenURL { url in
                Task {
                    try? await viewModel.claimFromURL(url)
                }
            }
        }
    }
}
