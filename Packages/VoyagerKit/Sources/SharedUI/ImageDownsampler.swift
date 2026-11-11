import Foundation
import ImageIO

public enum ImageDownsampler {
    /// Decodes at most `maxPixel` on the long side straight from the data, never the full-size bitmap.
    public static func thumbnail(data: Data, maxPixel: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard maxPixel > 0, let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
