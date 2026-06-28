import SwiftUI

@main
struct AgentClientMacShellApp: App {
    var body: some Scene {
        WindowGroup {
            MacShellView()
                .frame(
                    minWidth: MacWindowMetrics.minWidth,
                    minHeight: MacWindowMetrics.minHeight
                )
                #if os(macOS)
                .background(
                    WindowResizeConfigurator(
                        minSize: CGSize(
                            width: MacWindowMetrics.minWidth,
                            height: MacWindowMetrics.minHeight
                        )
                    )
                )
                #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        #endif
    }
}

private enum MacWindowMetrics {
    static let minWidth: CGFloat = 960
    static let minHeight: CGFloat = 620
}

#if os(macOS)
import AppKit

private struct WindowResizeConfigurator: NSViewRepresentable {
    let minSize: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.styleMask.insert(.resizable)
        window.minSize = minSize
    }
}
#endif
