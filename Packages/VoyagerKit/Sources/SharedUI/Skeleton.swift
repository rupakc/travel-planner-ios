import DesignSystem
import L10n
import SwiftUI

/// Placeholder text lines while a section loads. Pulses unless Reduce Motion is on; read as "Loading…".
public struct Skeleton: View {
    private let lines: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    public init(lines: Int = 3) {
        self.lines = max(1, lines)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(0..<lines, id: \.self) { index in
                RoundedRectangle(cornerRadius: Radius.input)
                    .fill(Palette.color(.gray, .s200))
                    .frame(height: 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, index == lines - 1 && lines > 1 ? 64 : 0)
            }
        }
        .opacity(dim ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text(K.results.loading.default))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
    }
}
