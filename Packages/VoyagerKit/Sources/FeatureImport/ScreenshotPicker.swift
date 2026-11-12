import ImageIO
import L10n
import PhotosUI
import SharedUI
import SwiftUI
import UniformTypeIdentifiers
import VoyagerModel

/// Re-encodes a chosen screenshot for upload: JPEG with the long edge at most 2048 px and the
/// base64 text at most 5 MB (the server's limit). A GIF is never uploaded as a GIF: its first frame goes as PNG.
public enum ScreenshotEncoder {
    public static let maxEdge = 2048
    public static let maxBase64Bytes = 5 * 1024 * 1024
    public static let maxImages = 4

    public enum Failure: Error, Equatable {
        case unreadable
        case tooBig
    }

    public static func encode(_ data: Data) throws -> ImportImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw Failure.unreadable }
        let isGIF = (CGImageSourceGetType(source) as String?) == UTType.gif.identifier
        guard var image = ImageDownsampler.thumbnail(data: data, maxPixel: maxEdge) else { throw Failure.unreadable }
        var qualities: [Double] = isGIF ? [1] : [0.85, 0.7, 0.55, 0.4]
        // Each round tries the qualities, then shrinks the picture by a quarter.
        for _ in 0..<8 {
            for quality in qualities {
                guard let encoded = write(image, png: isGIF, quality: quality) else { continue }
                let base64 = encoded.base64EncodedString()
                if base64.utf8.count <= maxBase64Bytes {
                    return ImportImage(mediaType: isGIF ? "image/png" : "image/jpeg", dataBase64: base64)
                }
            }
            qualities = isGIF ? [1] : [0.4]
            let edge = max(64, Int(Double(max(image.width, image.height)) * 0.75))
            guard let smaller = ImageDownsampler.thumbnail(data: data, maxPixel: edge) else { break }
            image = smaller
        }
        throw Failure.tooBig
    }

    private static func write(_ image: CGImage, png: Bool, quality: Double) -> Data? {
        let output = NSMutableData()
        let type = (png ? UTType.png : UTType.jpeg).identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }
        var options: [CFString: Any] = [:]
        if !png { options[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

/// "Add screenshots": the system photo picker (no photo-library permission), up to the remaining room.
struct ScreenshotPicker: View {
    let remaining: Int
    let onPicked: ([Data]) -> Void
    @State private var selection: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(selection: $selection, maxSelectionCount: max(1, remaining), matching: .images) {
            Label(L10n.text(K.search.import.chooseFiles), systemImage: "photo.on.rectangle")
                .font(.subheadline.weight(.semibold))
        }
        .disabled(remaining <= 0)
        .accessibilityIdentifier("import.pick")
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var datas: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) { datas.append(data) }
                }
                selection = []
                onPicked(datas)
            }
        }
    }
}
