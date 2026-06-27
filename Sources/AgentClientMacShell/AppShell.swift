import SwiftUI

struct MacShellView: View {
    @StateObject private var viewModel = MacShellViewModel()
    @State private var sidebarVisible = true

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                Sidebar(viewModel: viewModel, toggleSidebar: { sidebarVisible.toggle() })
                    .frame(width: 286)
                Rule()
            } else {
                CollapsedSidebar(toggleSidebar: { sidebarVisible.toggle() })
            }
            MainWorkspace(viewModel: viewModel)
        }
        .background(Theme.canvas)
    }
}

struct MainWorkspace: View {
    @ObservedObject var viewModel: MacShellViewModel

    var body: some View {
        Group {
            if viewModel.activeNav == "Settings" {
                SettingsWorkspace(viewModel: viewModel)
            } else {
                ChatWorkspace(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
