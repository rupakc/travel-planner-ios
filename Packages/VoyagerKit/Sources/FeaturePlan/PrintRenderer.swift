import SwiftUI

#if canImport(UIKit)
import UIKit

/// Plan → paginated PDF → the system print dialog. The PDF is always rendered in the light scheme.
@MainActor
enum PrintRenderer {
    static let colorScheme: ColorScheme = .light
    static let pageSize = CGSize(width: 612, height: 792) // US Letter in points; AirPrint scales to the paper
    static let margin: CGFloat = 36
    static let gap: CGFloat = 8

    private static var contentWidth: CGFloat { pageSize.width - 2 * margin }
    private static var usableHeight: CGFloat { pageSize.height - 2 * margin }

    private struct Placement {
        let chunk: Int
        let top: CGFloat
        /// Offset into the chunk (non-zero only for a chunk taller than a page).
        let slice: CGFloat
        let height: CGFloat
    }

    private static func renderer(_ view: AnyView) -> ImageRenderer<some View> {
        let renderer = ImageRenderer(content: view.frame(width: contentWidth, alignment: .topLeading))
        renderer.proposedSize = ProposedViewSize(width: contentWidth, height: nil)
        return renderer
    }

    /// The first chunk as an image (what the page header looks like): used to check the output is light.
    static func headerImage(_ document: PlanPrintDocument) -> UIImage? {
        guard let first = PlanPrintView(document: document).chunks.first else { return nil }
        let renderer = renderer(first)
        renderer.scale = 1
        return renderer.uiImage
    }

    static func makePDF(_ document: PlanPrintDocument) -> Data? {
        let chunks = PlanPrintView(document: document).chunks
        var sizes: [CGSize] = []
        for chunk in chunks {
            var size = CGSize.zero
            renderer(chunk).render { measured, _ in size = measured }
            sizes.append(size)
        }
        let pages = layout(sizes)
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return nil }
        for placements in pages {
            context.beginPDFPage(nil)
            for place in placements {
                let size = sizes[place.chunk]
                let pageTop = pageSize.height - margin - place.top
                renderer(chunks[place.chunk]).render { _, draw in
                    context.saveGState()
                    context.clip(to: CGRect(x: margin, y: pageTop - place.height, width: contentWidth, height: place.height))
                    context.translateBy(x: margin, y: pageTop - (size.height - place.slice))
                    draw(context)
                    context.restoreGState()
                }
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// Greedy page fill: a chunk that does not fit what is left starts the next page; one taller than a page is
    /// sliced across pages.
    private static func layout(_ sizes: [CGSize]) -> [[Placement]] {
        var pages: [[Placement]] = [[]]
        var cursor: CGFloat = 0
        for (index, size) in sizes.enumerated() where size.height > 0 {
            if size.height > usableHeight {
                if cursor > 0 { pages.append([]); cursor = 0 }
                var offset: CGFloat = 0
                while offset < size.height {
                    let slice = min(usableHeight, size.height - offset)
                    pages[pages.count - 1].append(Placement(chunk: index, top: 0, slice: offset, height: slice))
                    offset += slice
                    if offset < size.height { pages.append([]) } else { cursor = slice + gap }
                }
                continue
            }
            if cursor > 0, cursor + size.height > usableHeight {
                pages.append([])
                cursor = 0
            }
            pages[pages.count - 1].append(Placement(chunk: index, top: cursor, slice: 0, height: size.height))
            cursor += size.height + gap
        }
        return pages
    }

    /// The system print dialog for `pdf`.
    static func present(_ pdf: Data, jobName: String) {
        guard UIPrintInteractionController.isPrintingAvailable else { return }
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = jobName
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = pdf
        controller.present(animated: true, completionHandler: nil)
    }
}
#endif
