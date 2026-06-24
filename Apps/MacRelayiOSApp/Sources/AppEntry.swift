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
                ConnectionStatusView(viewModel: viewModel)
                    .tabItem { Label("Net", systemImage: "antenna.radiowaves.left.and.right") }
                SessionSnapshotView(viewModel: viewModel)
                    .tabItem { Label("Sess", systemImage: "rectangle.3.group") }
                EventReplayListView(viewModel: viewModel)
                    .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
            }
            .onOpenURL { url in
                Task {
                    try? await viewModel.claimFromURL(url)
                }
            }
        }
    }
}
