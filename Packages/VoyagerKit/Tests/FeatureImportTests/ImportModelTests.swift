import CoreGraphics
import Foundation
import ImageIO
import Networking
import Telemetry
import Testing
import TestSupport
import UniformTypeIdentifiers
import VoyagerEnv
import VoyagerModel

@testable import FeatureImport

@MainActor
private final class Recorder {
    var events: [TelemetryEvent] = []
}

/// A solid or noisy RGBA picture as image data in `type`.
private func imageData(width: Int, height: Int, noisy: Bool, type: UTType) -> Data {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    if noisy {
        var state: UInt32 = 12345
        for index in 0..<pixels.count where index % 4 != 3 {
            state = state &* 1_664_525 &+ 1_013_904_223
            pixels[index] = UInt8(truncatingIfNeeded: state >> 24)
        }
    }
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}

private func pixelSize(_ image: ImportImage) -> (Int, Int)? {
    guard let data = Data(base64Encoded: image.dataBase64), let source = CGImageSourceCreateWithData(data as CFData, nil),
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    return (w, h)
}

private let preview = LinkImportResult(
    source: ImportSourceInfo(kind: "url", url: "https://blog.example/lisbon", title: "Lisbon in 3 days"),
    title: "Lisbon in 3 days",
    destinations: [ImportDestination(name: "Lisbon, Portugal", city: "Lisbon", country: "Portugal", nights: 3)],
    places: [
        ImportPlace(
            id: "p1", name: "Belem Tower", kind: "sight", city: "Lisbon", destination: "Lisbon, Portugal", lat: 38.69, lng: -9.21,
            approximate: false, verified: true, note: "Go early"),
        ImportPlace(
            id: "p2", name: "Time Out Market", kind: "food", city: "Belem", destination: "Lisbon, Portugal", lat: 38.7, lng: -9.2,
            approximate: true),
        ImportPlace(id: "p3", name: "Hotel Avenida", kind: "stay", destination: "Lisbon, Portugal"),
    ],
    unresolved: [ImportPlace(id: "u1", name: "Secret Cafe", kind: "food")],
    interests: ["food", "history"])

@MainActor
struct ImportModelTests {
    @Test func test_imagesDownscaledUnder5MB() throws {
        let data = imageData(width: 3200, height: 2400, noisy: true, type: .png)
        let encoded = try ScreenshotEncoder.encode(data)
        #expect(encoded.mediaType == "image/jpeg")
        #expect(encoded.dataBase64.utf8.count <= 5 * 1024 * 1024)
        let size = try #require(pixelSize(encoded))
        #expect(max(size.0, size.1) <= 2048)
    }

    @Test func test_gifConvertedToPNG() throws {
        let gif = imageData(width: 40, height: 30, noisy: false, type: .gif)
        let encoded = try ScreenshotEncoder.encode(gif)
        #expect(encoded.mediaType == "image/png")
        let bytes = try #require(Data(base64Encoded: encoded.dataBase64))
        #expect(Array(bytes.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    @Test func test_unreadableDataThrows() {
        #expect(throws: ScreenshotEncoder.Failure.unreadable) { try ScreenshotEncoder.encode(Data([1, 2, 3])) }
    }

    @Test func test_mustIncludePassedToSearch() async throws {
        let env = AppEnvironment.fake()
        let recorder = Recorder()
        let model = ImportModel(env: env, now: Date(timeIntervalSince1970: 1_800_000_000), track: { recorder.events.append($0) })
        model.origin = "London"
        model.nationality = "British"
        model.load(preview)
        // The hotel starts unticked; the unplaced spot is not in a stop yet.
        #expect(model.plannedCount == 2)
        model.rename(model.places[0].id, to: "Torre de Belem")
        model.plan()

        guard case .results(let search) = try #require(env.recordedRoutes.last) else {
            Issue.record("expected a results route")
            return
        }
        let names = (search.mustInclude ?? []).compactMap { $0["name"].string }
        #expect(names == ["Torre de Belem", "Time Out Market"])
        let first = try #require(search.mustInclude?.first)
        #expect(first["lat"].double == 38.69)
        #expect(first["verified"].bool == true)
        let second = try #require(search.mustInclude?.last)
        #expect(second["lat"].isNull)  // approximate: no coordinates
        #expect(second["town"].string == "Belem")
        #expect(search.importSource?["title"].string == "Lisbon in 3 days")
        #expect(search.importSource?["url"].string == "https://blog.example/lisbon")
        #expect(search.destination == "Lisbon, Portugal")
        #expect(search.interests == ["food", "history"])
        #expect(search.origin == "London")
        let modes = recorder.events.compactMap { event -> ExploreModeName? in
            if case .searchSubmit(let mode, _, _, _) = event { return mode }
            return nil
        }
        #expect(modes == [.link])
    }

    @Test func test_removedPlaceIsNotSent() throws {
        let env = AppEnvironment.fake()
        let model = ImportModel(env: env, track: { _ in })
        model.load(preview)
        model.remove(model.places[0].id)
        let names = (model.searchRequest().mustInclude ?? []).compactMap { $0["name"].string }
        #expect(names == ["Time Out Market"])
    }

    @Test func test_structuredErrorCode() async {
        let fakes = FakeRepositories()
        fakes.importer.onExtract.fails(
            APIError.client(status: 422, detail: "That page is behind a paywall.", code: "paywall", body: .null))
        let model = ImportModel(env: AppEnvironment.fake(fakes: fakes), track: { _ in })
        model.text = "https://blog.example/post"
        await model.extract()
        guard case .failed(let view) = model.phase else {
            Issue.record("expected failure")
            return
        }
        #expect(view.code == "paywall")
        #expect(view.message == "That page is behind a paywall.")
        #expect(view.actions == [.text, .images])
        #expect(fakes.importer.onExtract.lastCall?.url == "https://blog.example/post")
    }

    @Test func test_tooLargeAndGif() {
        let large = ImportModel.errorView(for: APIError.client(status: 413, detail: nil, code: nil, body: .null))
        #expect(large.code == "too_large")
        #expect(large.actions == [.images])
        let gif = ImportModel.errorView(for: APIError.client(status: 422, detail: "No GIFs", code: "gif_unsupported", body: .null))
        #expect(gif.code == "gif_unsupported")
        #expect(ImportModel.errorView(for: APIError.network).code == "network")
    }

    @Test func test_detectsLinkVersusText() {
        let model = ImportModel(env: AppEnvironment.fake(), track: { _ in })
        model.text = "lisbon-blog.com/trip"
        #expect(model.detected == .url("https://lisbon-blog.com/trip"))
        model.text = "Belem Tower and pasteis"
        #expect(model.detected == .text)
    }
}
