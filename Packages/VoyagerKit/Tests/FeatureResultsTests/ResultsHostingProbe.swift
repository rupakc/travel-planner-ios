import SwiftUI
import UIKit
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureResults

/// Hosts a `ResultsView` in a window and lets a test change its size class, as Split View does.
@MainActor
final class ResultsHostingProbe {
        private let controller: UIHostingController<AnyView>
    private let window: UIWindow
    private let env: AppEnvironment
    private let request: TravelSearchRequest

    init(env: AppEnvironment, request: TravelSearchRequest) {
        self.env = env
        self.request = request
        controller = UIHostingController(rootView: AnyView(EmptyView()))
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
    }

    /// Rebuilds the view with a new size class; the `ResultsView` is a fresh value, and its `@State` keeps the first model.
    func render(compact: Bool) {
        let trait: UserInterfaceSizeClass = compact ? .compact : .regular
        controller.rootView = AnyView(
            ResultsView(env: env, request: request).environment(\.horizontalSizeClass, trait))
        controller.view.layoutIfNeeded()
    }
}
