import DesignSystem
import SharedUI
import SwiftUI

/// Follow-up chips (at most four): a tap sends the text as the next message.
struct SuggestionChips: View {
    let chips: [String]
    let onTap: (String) -> Void

    var body: some View {
        if !chips.isEmpty {
            // Wrapped rows: chips are long phrases, so they sit one per line when they do not fit side by side.
            FlowLayout(spacing: Spacing.sm) {
                ForEach(Array(chips.prefix(ChatReducer.maxChips).enumerated()), id: \.offset) { index, chip in
                    VChip(title: chip, tid: "chat.suggestion.\(index + 1)", selected: false) { onTap(chip) }
                }
            }
        }
    }
}

/// Lays children out left to right and wraps to the next line.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for (index, frame) in rows.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], width: CGFloat, height: CGFloat) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
            if width.isFinite { size.width = min(size.width, width) }
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (frames, maxX, y + rowHeight)
    }
}
