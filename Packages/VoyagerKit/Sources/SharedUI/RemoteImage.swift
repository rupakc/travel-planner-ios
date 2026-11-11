import DesignSystem
import ImageIO
import SwiftUI

struct ImageBox: @unchecked Sendable {
    let image: CGImage
}

/// 200 decoded thumbnails, keyed by URL and pixel size.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache(limit: 200)
    private let cache = NSCache<NSString, Entry>()

    private final class Entry {
        let box: ImageBox
        init(_ box: ImageBox) { self.box = box }
    }

    /// Decoded size in memory: width x height x 4 bytes.
    static func cost(_ box: ImageBox) -> Int { box.image.width * box.image.height * 4 }

    init(limit: Int, totalCostLimit: Int = 64 * 1024 * 1024) {
        cache.countLimit = limit
        cache.totalCostLimit = totalCostLimit
    }

    static func key(_ url: URL, maxPixel: Int) -> String { "\(maxPixel)|\(url.absoluteString)" }

    func image(for key: String) -> ImageBox? { cache.object(forKey: key as NSString)?.box }

    func store(_ box: ImageBox, for key: String) { cache.setObject(Entry(box), forKey: key as NSString, cost: Self.cost(box)) }
}

/// An image from the network, downsampled with ImageIO off the main actor to `targetSize` at the display scale.
public struct RemoteImage: View {
    private let url: URL?
    private let targetSize: CGSize
    @Environment(\.displayScale) private var displayScale
    /// The last image this view fetched, with the cache key it belongs to (a changed url or size never shows it).
    @State private var loaded: (key: String, box: ImageBox)?

    public init(url: URL?, targetSize: CGSize) {
        self.url = url
        self.targetSize = targetSize
    }

    private var maxPixel: Int { max(1, Int((max(targetSize.width, targetSize.height) * displayScale).rounded(.up))) }
    private var key: String? { url.map { ImageCache.key($0, maxPixel: maxPixel) } }

    public var body: some View {
        let shown = key.flatMap { current in
            loaded.flatMap { $0.key == current ? $0.box : nil } ?? ImageCache.shared.image(for: current)
        }
        ZStack {
            if let shown {
                Image(decorative: shown.image, scale: displayScale)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Palette.color(.gray, .s100))
                    .overlay {
                        Image(systemName: "photo").foregroundStyle(SemanticColor.textMuted).accessibilityHidden(true)
                    }
            }
        }
        .frame(width: targetSize.width, height: targetSize.height)
        .clipped()
        .task(id: key) { await load() }
    }

    /// Largest body downloaded for one image.
    static let maxDownloadBytes = 10 * 1024 * 1024

    private func load() async {
        guard let url, let key else { return }
        if ImageCache.shared.image(for: key) != nil { return }
        let pixel = maxPixel
        let work = Task.detached(priority: .utility) { () -> ImageBox? in
            guard let data = await Self.download(url), let image = ImageDownsampler.thumbnail(data: data, maxPixel: pixel)
            else { return nil }
            return ImageBox(image: image)
        }
        // `.task(id:)` cancels this task when the key changes or the view goes away; the detached work follows it.
        let box = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        guard let box, !Task.isCancelled else { return }
        ImageCache.shared.store(box, for: key)
        loaded = (key, box)
    }

    /// The body of a 2xx response, abandoned as soon as it exceeds `maxDownloadBytes`.
    static func download(_ url: URL) async -> Data? {
        guard let (bytes, response) = try? await URLSession.shared.bytes(from: url) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        if response.expectedContentLength > Int64(maxDownloadBytes) { return nil }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxDownloadBytes { return nil }
            }
        } catch {
            return nil
        }
        return data
    }
}
