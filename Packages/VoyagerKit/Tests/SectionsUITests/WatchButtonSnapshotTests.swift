import DesignSystem
import L10n
import SnapshotTesting
import SwiftUI
import VoyagerModel
import XCTest

@testable import SectionsUI

/// The Watch button in each state of the one-tap watch (plan Task 3.4): idle, limit (looks idle, a tap explains), pending,
/// existing. The `off` state shows no button at all.
@MainActor
final class WatchButtonSnapshotTests: XCTestCase {
    private func configs(height: CGFloat) -> [SnapshotConfig] {
        let phone = CGSize(width: 320, height: height)
        return [
            SnapshotConfig(name: "se-light", device: .iPhoneSe(.portrait), dark: false, canvas: phone),
            SnapshotConfig(name: "se-dark", device: .iPhoneSe(.portrait), dark: true, canvas: phone),
            SnapshotConfig(name: "se-de", device: .iPhoneSe(.portrait), dark: false, language: .de, canvas: phone),
        ]
    }

    private var ctx: SectionContext {
        SectionContext(
            isSelected: { _, _ in false }, toggle: { _, _ in }, watch: { _ in },
            watchState: { request in
                switch request.spec["name"].string ?? "" {
                case "pending": .pending(2)
                case "existing": .existing(3)
                case "limit": .limit
                case "off": .off
                default: .idle
                }
            },
            openURL: { _, _ in })
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
    }

    private func button(_ name: String) -> some View {
        WatchButton(
            kind: .hotel, spec: ["name": .string(name)], tid: "results.hotel.watch", title: L10n.text(K.alerts.btn.watchPrice),
            accessibilityName: name, ctx: ctx)
    }

    func test_watchButtonStates() {
        assertSnapshots(
            of: {
                VStack(alignment: .leading, spacing: 12) {
                    caption("idle")
                    self.button("idle")
                    caption("limit")
                    self.button("limit")
                    caption("pending")
                    self.button("pending")
                    caption("existing")
                    self.button("existing")
                    caption("off (nothing below)")
                    self.button("off")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }, named: "WatchButtonStates", configs: configs(height: 397))
    }
}
