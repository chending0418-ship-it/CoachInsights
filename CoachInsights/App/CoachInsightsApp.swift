import SwiftUI

@main struct CoachInsightsApp: App {
    @StateObject private var library = LibraryStore()
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--layout-probe") { LayoutProbeView() }
                else { RootView() }
                #else
                RootView()
                #endif
            }.environmentObject(library).tint(Theme.burgundy).preferredColorScheme(.light)
        }
    }
}

#if DEBUG
private struct LayoutProbeView: View {
    @State private var narrow = false
    var body: some View {
        GeometryReader { geometry in
            VStack {
                HStack {
                    Button("窄窗口") { narrow = true }.accessibilityIdentifier("narrowViewport")
                    Button("宽窗口") { narrow = false }.accessibilityIdentifier("wideViewport")
                }.buttonStyle(.bordered)
                RootView()
                    .environment(\.horizontalSizeClass, narrow ? .compact : .regular)
                    .frame(width: narrow ? 360 : geometry.size.width)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
#endif

enum Theme {
    static let burgundy = Color(red: 0.447, green: 0.184, blue: 0.216)
    static let paper = Color(red: 0.973, green: 0.953, blue: 0.945)
    static let rose = Color(red: 0.937, green: 0.812, blue: 0.827)
}
