import AgentClientiOS
import SwiftUI

@main
struct MacRelayiOSApp: App {
    @StateObject private var viewModel = RelayClientViewModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                PairingView(viewModel: viewModel)
                    .tabItem { Label("Pairing", systemImage: "link") }

                VStack {
                    ConnectionStatusView(viewModel: viewModel)
                    ScrollView {
                        SessionSnapshotView(viewModel: viewModel)
                        EventReplayListView(viewModel: viewModel)
                    }
                }
                .tabItem { Label("Session", systemImage: "rectangle.split.2x1") }
            }
            .onOpenURL { url in
                Task { try? await viewModel.claimFromURL(url) }
            }
        }
    }
}
