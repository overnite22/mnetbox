import SwiftUI

@main struct MNetBoxApp: App {
    @State private var connection = ConnectionModel()
    init() {
        #if DEBUG
        if let fixture = UITestSupport.connection() {
            _connection = State(initialValue: fixture)
        }
        #endif
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if connection.state == .connected { ShellView(model: connection) }
                else { ConnectionView(model: connection) }
            }
            #if DEBUG
            .modifier(UITestAppearance())
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--ui-testing-dashboard") && ProcessInfo.processInfo.arguments.contains("--ui-testing-dark") ? .dark : nil)
            #endif
            .task { connection.restore() }
        }
    }
}

#if DEBUG
private struct UITestAppearance: ViewModifier {
    func body(content: Content) -> some View {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-dashboard") && ProcessInfo.processInfo.arguments.contains("--ui-testing-large-text") {
            content.dynamicTypeSize(.accessibility3)
        } else { content }
    }
}
#endif
