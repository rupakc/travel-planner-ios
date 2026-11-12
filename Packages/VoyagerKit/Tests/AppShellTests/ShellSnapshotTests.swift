import DesignSystem
import SnapshotTesting
import SwiftUI
import TestSupport
import XCTest

@testable import AppShell

@MainActor
final class ShellSnapshotTests: XCTestCase {
    private func shell() -> some View {
        let env = AppEnvironment.fake()
        let router = AppRouter()
        env.router = router
        return ShellView(env: env, router: router)
    }

    // test_iPhoneTabBar is deferred: with the real Search form the iPhone TabView hosts blank Explore content in a
    // hosted snapshot (the iPad sidebar renders it fine). Tracked in task-20-report.md; do not record a blank baseline.

    func test_iPadSidebar() async {
        let pad = [
            SnapshotConfig(name: "ipad13-light", device: SnapshotDevice.iPadPro13.config, dark: false),
            SnapshotConfig(name: "ipad13-dark", device: SnapshotDevice.iPadPro13.config, dark: true),
        ]
        await assertSnapshots(of: { shell() }, named: "sidebar", configs: pad, layout: .screen, settle: 1.5)
    }
}
