import SwiftUI

/// The wrapping arithmetic, pure so a test can pin that measuring and placing agree.
enum WrapGeometry {
    /// Origins and content size when the items are wrapped at `width`.
    static func arrange(sizes: [CGSize], width: CGFloat, spacing: CGFloat) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for size in sizes {
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: sizes.isEmpty ? 0 : y + rowHeight), origins)
    }

    /// What the layout reports for a proposal. With a finite width it reports that whole width: the parent then
    /// places the layout in exactly that width, so placing wraps the same rows that were measured. (Reporting the
    /// widest row instead made the parent place us in a narrower box and wrap into more rows than we had measured.)
    static func measured(sizes: [CGSize], proposalWidth: CGFloat?, spacing: CGFloat) -> CGSize {
        let width = proposalWidth.flatMap { $0.isFinite ? $0 : nil }
        let laid = arrange(sizes: sizes, width: width ?? .infinity, spacing: spacing)
        guard let width else { return laid.size }
        return CGSize(width: max(width, 0), height: laid.size.height)
    }
}

/// A plain wrapping layout, so it also works in hosted snapshots.
struct WrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        WrapGeometry.measured(sizes: sizes(subviews), proposalWidth: proposal.width, spacing: spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let laid = WrapGeometry.arrange(sizes: sizes(subviews), width: bounds.width, spacing: spacing)
        for (subview, origin) in zip(subviews, laid.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func sizes(_ subviews: Subviews) -> [CGSize] { subviews.map { $0.sizeThatFits(.unspecified) } }
}
