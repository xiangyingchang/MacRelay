import SwiftUI

struct MacShellView: View {
    @StateObject private var viewModel = MacShellViewModel()
    @State private var sidebarVisible = true
    @State private var showPhonePopover = false
    @State private var showSettingsPopover = false
    @AppStorage("themeMode") private var themeMode: String = "dark"
    private var isLightTheme: Bool { themeMode == "light" }

    var body: some View {
        HStack(spacing: 0) {
            if showSettingsPopover {
                SettingsPopover(
                    viewModel: viewModel,
                    isLightTheme: isLightTheme,
                    toggleTheme: { themeMode = isLightTheme ? "dark" : "light" },
                    isPresented: $showSettingsPopover
                )
                .frame(width: 240)
                Rule()
            } else if sidebarVisible {
                Sidebar(viewModel: viewModel, toggleSidebar: { sidebarVisible.toggle() }, showPhonePopover: $showPhonePopover, showSettingsPopover: $showSettingsPopover)
                    .frame(width: 240)
                Rule()
            } else {
                CollapsedSidebar(toggleSidebar: { sidebarVisible.toggle() })
            }
            MainWorkspace(viewModel: viewModel)
        }
        .background(Theme.bg)
        .preferredColorScheme(isLightTheme ? .light : .dark)
        .id(isLightTheme ? "light" : "dark")
        .overlay(alignment: .bottomLeading) {
            if showPhonePopover {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .onTapGesture { showPhonePopover = false }

                PhonePairingPopover(
                    viewModel: viewModel,
                    isPresented: $showPhonePopover
                )
                .padding(.leading, 24)
                .padding(.bottom, 72)
                .transition(.scale(scale: 0.96, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.15), value: showPhonePopover)
        .animation(.smooth(duration: 0.18), value: showSettingsPopover)
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
