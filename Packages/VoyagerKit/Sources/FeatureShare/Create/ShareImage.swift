import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The story card (1080x1920 PNG) for the system share sheet. It exports the file the card loader already wrote, so
/// nothing is read into memory and nothing but the card leaves the app.
struct ShareImage: Transferable {
    let fileURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { image in
            SentTransferredFile(image.fileURL, allowAccessingOriginalFile: true)
        }
    }
}
