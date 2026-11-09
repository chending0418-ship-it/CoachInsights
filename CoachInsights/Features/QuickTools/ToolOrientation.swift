import SwiftUI
import UserNotifications

@MainActor enum ToolOrientation {
    static var mask: UIInterfaceOrientationMask = .allButUpsideDown
}

final class PocketAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad && ToolOrientation.mask != .landscape { return .all }
        return ToolOrientation.mask
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

/// Use the scene geometry API, without changing the physical device orientation.
/// Restore the previous interface orientation when this operation page leaves.
struct LandscapeToolOrientation: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ uiViewController: Controller, context: Context) {}
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.restore() }

    final class Controller: UIViewController {
        private weak var scene: UIWindowScene?
        private var previous = UIInterfaceOrientation.unknown
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard scene == nil, let windowScene = view.window?.windowScene else { return }
            scene = windowScene; previous = windowScene.interfaceOrientation
            ToolOrientation.mask = .landscape
            windowScene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
        }
        func restore() {
            guard let scene else { return }
            ToolOrientation.mask = .allButUpsideDown
            scene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
            let mask: UIInterfaceOrientationMask
            switch previous {
            case .landscapeLeft: mask = .landscapeLeft
            case .landscapeRight: mask = .landscapeRight
            case .portraitUpsideDown where UIDevice.current.userInterfaceIdiom == .pad: mask = .portraitUpsideDown
            default: mask = .portrait
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
            self.scene = nil
        }
    }
}
