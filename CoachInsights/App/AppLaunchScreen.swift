import SwiftUI

struct AppLaunchScreen<Content: View>: View {
    @StateObject private var launch = LaunchScreenController()
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            content()
                .accessibilityHidden(launch.presentation != nil)
                .allowsHitTesting(launch.presentation == nil)
            if let presentation = launch.presentation {
                LaunchArtworkView(presentation: presentation, skip: launch.dismiss)
            }
        }
        .preferredColorScheme(launch.presentation?.image == nil ? .light : .dark)
        .task { await launch.start() }
    }
}

@MainActor
private final class LaunchScreenController: ObservableObject {
    @Published private(set) var presentation: LaunchScreenPresentation?
    private let repository: LaunchScreenRepository?
    private let holdPreview: Bool
    private var started = false

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--launch-screen-preview") {
            presentation = .bundled
            repository = nil
            holdPreview = true
            return
        }
        if arguments.contains("--ui-testing") || arguments.contains("--layout-probe")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            presentation = nil
            repository = nil
            holdPreview = false
            return
        }
        #endif
        let cache = LaunchScreenDiskCache.standard
        presentation = cache.presentation()
        repository = LaunchScreenRepository(cache: cache, transport: LaunchScreenHTTPTransport())
        holdPreview = false
    }

    func dismiss() {
        presentation = nil
    }

    func start() async {
        guard !started else { return }
        started = true
        if let repository {
            Task { await repository.refresh() }
        }
        guard let presentation, !holdPreview else { return }
        try? await Task.sleep(for: .milliseconds(presentation.configuration.displayDurationMs))
        dismiss()
    }
}

private struct LaunchArtworkView: View {
    let presentation: LaunchScreenPresentation
    let skip: () -> Void
    private var usesDefaultArtwork: Bool { presentation.image == nil }
    private var foregroundColor: Color { usesDefaultArtwork ? Theme.burgundy : .white }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                usesDefaultArtwork ? Color("LaunchBackground") : Theme.burgundy
                if let image = presentation.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .accessibilityHidden(true)
                    Color.black.opacity(0.66)
                } else {
                    Image("LaunchField")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .accessibilityHidden(true)
                }

                Image(usesDefaultArtwork ? "LaunchIdentityLight" : "LaunchIdentity")
                    .resizable()
                    .scaledToFit()
                    .frame(width: max(0, min(264, geometry.size.width - 48)))
                    .accessibilityLabel(Text("棒球训练助手"))
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height * (usesDefaultArtwork ? 0.72 : 0.50)
                    )
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if !presentation.configuration.message.isEmpty {
                Text(presentation.configuration.message)
                    .font(.footnote.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(foregroundColor)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: skip) {
                Text(Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "跳过" : "Skip")
                    .font(.footnote)
                    .foregroundStyle(foregroundColor)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(.black.opacity(usesDefaultArtwork ? 0.06 : 0.24), in: Capsule())
            }
            .padding(.trailing, 20)
            .accessibilityIdentifier("skip-launch-screen")
        }
    }
}
