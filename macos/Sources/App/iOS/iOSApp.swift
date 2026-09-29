import SwiftUI
import XGhosttyKit

@main
struct Ghostty_iOSApp: App {
    @StateObject private var xghostty_app: XGhostty.App

    init() {
        if xghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != XGHOSTTY_SUCCESS {
            preconditionFailure("Initialize ghostty backend failed")
        }
        _xghostty_app = StateObject(wrappedValue: XGhostty.App())
    }

    var body: some Scene {
        WindowGroup {
            iOS_GhosttyTerminal()
                .environmentObject(xghostty_app)
        }
    }
}

struct iOS_GhosttyTerminal: View {
    @EnvironmentObject private var xghostty_app: XGhostty.App

    var body: some View {
        ZStack {
            // Make sure that our background color extends to all parts of the screen
            Color(xghostty_app.config.backgroundColor).ignoresSafeArea()

            XGhostty.Terminal()
        }
    }
}

struct iOS_GhosttyInitView: View {
    @EnvironmentObject private var xghostty_app: XGhostty.App

    var body: some View {
        VStack {
            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 96)
            Text("XGhostty")
            Text("State: \(xghostty_app.readiness.rawValue)")
        }
        .padding()
    }
}
