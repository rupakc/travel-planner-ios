import SnapshotTesting
import SwiftUI
import TestSupport
import UIKit
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureShare

@MainActor
final class ShareSheetSnapshotTests: XCTestCase {
    private func canvas(_ height: CGFloat) -> CGSize { CGSize(width: 320, height: height) }

    private func phone(_ name: String, dark: Bool = false, language: AppLanguage = .en, size: UIContentSizeCategory = .large, height: CGFloat = 1500)
        -> SnapshotConfig {
        SnapshotConfig(
            name: name, device: .iPhoneSe(.portrait), dark: dark, language: language, size: size, canvas: canvas(height))
    }

    /// A stand-in for the server's share card: 1200x630, a flat teal with a headline (the real card is drawn by the server).
    private nonisolated static func cardPNG() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 630), format: format).image { context in
            UIColor(red: 0.05, green: 0.45, blue: 0.5, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 630))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 96), .foregroundColor: UIColor.white,
            ]
            ("7 days in Lisbon" as NSString).draw(at: CGPoint(x: 80, y: 220), withAttributes: attributes)
        }
        return image.pngData() ?? Data()
    }

    private struct Prepared {
        let model: ShareSheetModel
        let env: AppEnvironment
    }

    /// A sheet on fakes. `ready` creates the link first; `cards` lets the downloads finish (else they never do).
    private func prepare(ready: Bool, cards: Bool, options: ShareOptions = ShareOptions(), dirty: ShareOptions? = nil) async -> Prepared {
        let fakes = FakeRepositories()
        fakes.shares.onCreate.handler = { request in
            Share(
                token: "snap1", kind: .plan, planID: 3, url: "https://voyager.example/share/snap1",
                cardLinkURL: "https://fake.voyager.test/c?size=link", cardStoryURL: "https://fake.voyager.test/c?size=story",
                options: request.options)
        }
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: ClientConfig(features: ["sharing": .number(1)]))
        let loader = FakeShareCardLoader()
        if cards {
            let store = loader.store
            loader.onLoad.handler = { input in try store.write(Self.cardPNG(), token: input.token, size: input.size) }
        } else {
            loader.onLoad.handler = { _ in
                try await Task.sleep(for: .seconds(120))
                throw CancellationError()
            }
        }
        let model = ShareSheetModel(env: env, target: .plan(id: 3), loader: loader, pasteboard: { _ in true }, track: { _ in })
        model.options = options
        if ready {
            await model.create()
            if cards { await model.settled() }
        }
        if let dirty { model.options = dirty }
        return Prepared(model: model, env: env)
    }

    func test_sharePlan() async {
        let prepared = await prepare(ready: true, cards: true)
        await assertSnapshots(
            of: { ShareSheetView(model: prepared.model) }, named: "plan",
            configs: [phone("se-light"), phone("se-dark", dark: true)], layout: .screen)
    }

    func test_datesExactIsAnUnsavedChange() async {
        let prepared = await prepare(ready: true, cards: true, dirty: ShareOptions(dates: .exact, showOrigin: true))
        await assertSnapshots(
            of: { ShareSheetView(model: prepared.model) }, named: "dates-exact", configs: [phone("se-light")], layout: .screen)
    }

    func test_loadingCard() async {
        let prepared = await prepare(ready: true, cards: false)
        await assertSnapshots(
            of: { ShareSheetView(model: prepared.model) }, named: "loading-card", configs: [phone("se-light")], layout: .screen)
        prepared.model.cancel()
    }

    func test_german() async {
        let prepared = await prepare(ready: true, cards: true)
        await assertSnapshots(
            of: { ShareSheetView(model: prepared.model) }, named: "de",
            configs: [phone("se-de", language: .de, height: 1700)], layout: .screen)
    }

    func test_ax5() async {
        let prepared = await prepare(ready: true, cards: true)
        await assertSnapshots(
            of: { ShareSheetView(model: prepared.model) }, named: "ax5",
            configs: [phone("se-ax5", size: .accessibilityExtraExtraExtraLarge, height: 3600)], layout: .screen)
    }

    func test_ipadForm() async {
        let prepared = await prepare(ready: false, cards: true)
        await assertSnapshots(
            of: { ShareSheetView(model: prepared.model) }, named: "form",
            configs: [SnapshotConfig(name: "ipad-light", device: .iPadPro11(.portrait), dark: false, canvas: CGSize(width: 834, height: 1000))],
            layout: .screen)
    }
}
