import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// The price story inside a watch card: the verdict, the advice line, the history chart, how old the last check is,
/// an estimate (labelled as one) and, for flights, the AI timing tip. Shows nothing when the server has no stories.
struct PriceStoryView: View {
    let model: PriceStoryModel

    var body: some View {
        switch model.phase {
        case .idle, .unavailable:
            EmptyView()
        case .loading:
            HStack(spacing: Spacing.sm) {
                ProgressView()
                Text(verbatim: L10n.text(K.priceStory.loading))
                    .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            }
            .accessibilityElement(children: .combine)
        case .failed(let message):
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: message)
                    .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                VButton(L10n.text(K.alerts.ui.retry), tid: "alerts.story.retry.\(model.kind.rawValue)-\(model.watchID)", role: .secondary) {
                    Task { await model.load() }
                }
            }
        case .loaded(let story):
            loaded(story)
        }
    }

    private func loaded(_ story: PriceStory) -> some View {
        let id = "\(model.kind.rawValue)-\(model.watchID)"
        let data = StoryChartData(story: story)
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            AdviceLine(advice: story.advice, currency: story.currency)
            chart(story, data)
            if let checked = PriceStoryModel.checkedText(story) {
                Text(verbatim: checked)
                    .font(VFont.body(.caption))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .foregroundStyle(SemanticColor.textMuted)
                    .accessibilityIdentifier("alerts.story.checked")
            }
            if let estimate = PriceStoryModel.estimateText(story) {
                Text(verbatim: estimate)
                    .font(VFont.body(.caption))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("alerts.story.estimate")
            }
            if model.canAskForTip {
                AIAdviceButton(model: model, tid: "alerts.story.tip.\(id)")
            }
        }
        .padding(.top, Spacing.sm)
        .overlay(alignment: .top) { Rectangle().fill(SemanticColor.border).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alerts.story.\(id)")
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                title
                Spacer(minLength: Spacing.sm)
                verdictChip
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                title
                verdictChip
            }
        }
    }

    private var title: some View {
        Text(verbatim: L10n.text(K.priceStory.title))
            .font(VFont.body(.subheadline, weight: .semibold))
            .foregroundStyle(SemanticColor.text)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var verdictChip: some View {
        if let verdict = model.verdict {
            let family: Family = {
                switch verdict {
                case .great, .good: .emerald
                case .typical: .slate
                case .high: .amber
                }
            }()
            let text = PriceStoryModel.verdictText(verdict)
            Text(verbatim: text)
                .font(VFont.body(.caption, weight: .medium))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundStyle(Palette.color(family, .s800))
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Palette.color(family, .s100), in: Capsule())
                .accessibilityLabel(L10n.text(K.priceStory.verdictLabel, ["level": text]))
                .accessibilityIdentifier("alerts.story.verdict")
        }
    }

    @ViewBuilder private func chart(_ story: PriceStory, _ data: StoryChartData) -> some View {
        if data.showsChart {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                StoryChart(data: data, selected: model.selected) { model.scrub(to: $0) }
                    .accessibilityAction(named: Text(verbatim: firstActionName(story))) { model.selectFirst() }
                    .accessibilityAction(named: Text(verbatim: L10n.text(K.priceStory.latest))) { model.selectLatest() }
                legend(story)
                if let selected = model.selected {
                    Text(verbatim: model.readout(for: selected))
                        .font(VFont.body(.footnote, weight: .medium))
                        .foregroundStyle(SemanticColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("alerts.story.readout")
                }
            }
        } else {
            let text = data.points.isEmpty
                ? L10n.text(K.priceStory.chart.none) : L10n.text(K.priceStory.chart.few, count: data.points.count)
            Text(verbatim: text)
                .font(VFont.body(.caption))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func firstActionName(_ story: PriceStory) -> String {
        let price = story.points.first.map { Fmt.currency($0.price, code: story.currency ?? "USD") } ?? ""
        return L10n.text(K.priceStory.chart.baseline, ["price": price])
    }

    /// Typical range, lowest and target, in words under the chart (colour alone never carries meaning).
    private func legend(_ story: PriceStory) -> some View {
        let code = story.currency ?? "USD"
        var parts: [String] = []
        if let typical = story.typical {
            let range = "\(Fmt.currency(typical.low, code: code))–\(Fmt.currency(typical.high, code: code))"
            parts.append("\(L10n.text(K.priceStory.chart.typical)): \(range)")
        }
        if let lowest = story.lowest {
            parts.append(L10n.text(K.priceStory.chart.lowest, ["price": Fmt.currency(lowest.price, code: code)]))
        }
        if let target = story.target {
            parts.append(L10n.text(K.priceStory.chart.target, ["price": Fmt.currency(target, code: code)]))
        }
        return Text(verbatim: parts.joined(separator: " · "))
            .font(VFont.body(.caption))
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .foregroundStyle(SemanticColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
