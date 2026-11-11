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

    init(limit: Int) {
        cache.countLimit = limit
    }

    static func key(_ url: URL, maxPixel: Int) -> String { "\(maxPixel)|\(url.absoluteString)" }

    func image(for key: String) -> ImageBox? { cache.object(forKey: key as NSString)?.box }

    func store(_ box: ImageBox, for key: String) { cache.setObject(Entry(box), forKey: key as NSString) }
}

/// An image from the network, downsampled with ImageIO off the main actor to `targetSize` at the display scale.
public struct RemoteImage: View {
    private let url: URL?
    private let targetSize: CGSize
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: ImageBox?

    public init(url: URL?, targetSize: CGSize) {
        self.url = url
        self.targetSize = targetSize
    }

    private var maxPixel: Int { max(1, Int((max(targetSize.width, targetSize.height) * displayScale).rounded(.up))) }
    private var key: String? { url.map { ImageCache.key($0, maxPixel: maxPixel) } }

    public var body: some View {
        let shown = loaded ?? key.flatMap { ImageCache.shared.image(for: $0) }
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

    private func load() async {
        guard let url, let key else { return }
        if ImageCache.shared.image(for: key) != nil { return }
        let pixel = maxPixel
        let box = await Task.detached(priority: .utility) { () -> ImageBox? in
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                let image = ImageDownsampler.thumbnail(data: data, maxPixel: pixel)
            else { return nil }
            return ImageBox(image: image)
        }.value
        guard let box, !Task.isCancelled else { return }
        ImageCache.shared.store(box, for: key)
        loaded = box
    }
}
