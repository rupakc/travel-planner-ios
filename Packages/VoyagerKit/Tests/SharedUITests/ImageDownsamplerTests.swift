import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import SharedUI

struct ImageDownsamplerTests {
    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func test_thumbnailBoundedByMaxPixel() throws {
        let data = try pngData(width: 4000, height: 3000)
        let thumb = try #require(ImageDownsampler.thumbnail(data: data, maxPixel: 300))
        #expect(max(thumb.width, thumb.height) <= 300)
        #expect(thumb.width == 300)
        #expect(thumb.height == 225)
    }

    @Test func test_smallImageIsNotUpscaledBeyondRequest() throws {
        let data = try pngData(width: 100, height: 50)
        let thumb = try #require(ImageDownsampler.thumbnail(data: data, maxPixel: 300))
        #expect(max(thumb.width, thumb.height) <= 300)
    }

    @Test func test_garbageDataGivesNil() {
        #expect(ImageDownsampler.thumbnail(data: Data("not an image".utf8), maxPixel: 300) == nil)
    }

    @Test func test_nonPositiveMaxPixelGivesNil() throws {
        let data = try pngData(width: 20, height: 20)
        #expect(ImageDownsampler.thumbnail(data: data, maxPixel: 0) == nil)
    }

    @Test func test_cacheKeyIncludesPixelSize() throws {
        let url = try #require(URL(string: "https://example.com/a.jpg"))
        #expect(ImageCache.key(url, maxPixel: 100) != ImageCache.key(url, maxPixel: 200))
    }
}
