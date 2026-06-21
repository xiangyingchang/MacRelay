import SwiftUI

struct MacShellView: View {
    @StateObject private var viewModel = MacShellViewModel()

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(viewModel: viewModel)
                .frame(width: 292)
            Rule()
            VStack(spacing: 0) {
                ActiveSessionsBar(viewModel: viewModel)
                    .frame(height: 50)
                Rule(horizontal: true)
                HStack(spacing: 0) {
                    ChatWorkspace(viewModel: viewModel)
                    Rule()
                    Inspector(viewModel: viewModel)
                        .frame(width: 360)
                }
            }
        }
        .background(Theme.bgPrimary)
    }
}
