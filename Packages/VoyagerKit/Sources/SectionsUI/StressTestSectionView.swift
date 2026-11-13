import DesignSystem
import L10n
import Observation
import SharedUI
import SwiftUI
import Telemetry
import VoyagerModel

/// A failed re-check; `message` is the server's own text (a 429 detail), shown as-is.
public struct ItineraryRecheckError: Error, Sendable {
    public var message: String?
    public init(message: String? = nil) { self.message = message }
}

/// State behind the stress-test section: the editor (for the arranged itinerary), the latest re-check result
/// and its fingerprint (a later edit makes it stale).
@MainActor @Observable
final class StressTestModel {
    let editor: ItineraryEditorModel
    private(set) var rechecked: JSONValue?
    private(set) var checkedFingerprint: String?
    private(set) var isRechecking = false
    private(set) var errorMessage: String?
    @ObservationIgnored private var send: (@MainActor @Sendable (JSONValue) async throws -> JSONValue)?

    init(editor: ItineraryEditorModel, send: (@MainActor @Sendable (JSONValue) async throws -> JSONValue)? = nil) {
        self.editor = editor
        self.send = send
    }

    func attach(_ host: ItineraryHost?) {
        guard let host else { return }
        if let itinerary = host.itinerary() { editor.update(itinerary: itinerary) }
        editor.attach(host)
        send = host.recheck
    }

    /// The original check no longer matches once the user moved something.
    var layoutMoved: Bool { editor.changeCount > 0 }
    var canRecheck: Bool { send != nil && layoutMoved }
    var isStale: Bool { rechecked != nil && checkedFingerprint != editor.recheckFingerprint() }
    /// Shown instead of the original while a re-check of the moved plan exists.
    func shown(original: JSONValue) -> JSONValue { layoutMoved ? (rechecked ?? original) : original }

    func recheck() async {
        guard let send, !isRechecking else { return }
        isRechecking = true
        errorMessage = nil
        let payload = editor.recheckPayload()
        let fingerprint = editor.recheckFingerprint()
        do {
            let result = try await send(payload)
            if result["error"].isTruthy {
                errorMessage = L10n.text(K.sections.stress.unavailable)
            } else {
                rechecked = result
                checkedFingerprint = fingerprint
            }
        } catch let failure as ItineraryRecheckError {
            errorMessage = failure.message ?? L10n.text(K.sections.stress.unavailable)
        } catch {
            errorMessage = L10n.text(K.sections.stress.unavailable)
        }
        isRechecking = false
    }
}

/// The plan audit: overall colour, score, summary and findings grouped by day (trip-wide ones first), each
/// with severity, category and a concrete fix. "Re-check" sends the arranged, edited itinerary again.
public struct StressTestSectionView: View {
    let data: JSONValue
    let ctx: SectionContext
    @Environment(\.itineraryHost) private var host
    @State private var model: StressTestModel

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
        _model = State(initialValue: StressTestModel(editor: ItineraryEditorModel(itinerary: .null, editable: false)))
    }

    // MARK: Pure helpers (tested)

    static func overall(_ data: JSONValue) -> String {
        let value = data["overall"].string ?? ""
        return ["green", "amber", "red"].contains(value) ? value : "amber"
    }

    static func severityRank(_ value: String?) -> Int {
        switch value {
        case "high": 0
        case "medium": 1
        case "low": 2
        default: 3
        }
    }

    /// Trip-wide findings first, then by day; each group by severity (stable within a severity).
    static func grouped(_ data: JSONValue) -> [(day: Int?, findings: [JSONValue])] {
        let all = (data["findings"].array ?? []).filter { $0.object != nil }
        var byDay: [Int?: [JSONValue]] = [:]
        for finding in all { byDay[finding["day_number"].int, default: []].append(finding) }
        let days = byDay.keys.sorted { lhs, rhs in
            switch (lhs, rhs) {
            case (nil, nil): false
            case (nil, _): true
            case (_, nil): false
            case (let first?, let second?): first < second
            }
        }
        return days.map { day in
            let sorted = byDay[day, default: []].enumerated().sorted { lhs, rhs in
                let left = severityRank(lhs.element["severity"].string)
                let right = severityRank(rhs.element["severity"].string)
                return left != right ? left < right : lhs.offset < rhs.offset
            }
            return (day, sorted.map(\.element))
        }
    }

    /// 0...100 from loose JSON; nil when absent or not a finite number.
    static func score(_ data: JSONValue) -> Int? {
        guard let value = data["score"].double, value.isFinite else { return nil }
        return Int(max(0, min(100, value.rounded())))
    }

    // MARK: View

    public var body: some View {
        let shown = model.shown(original: data)
        Group {
            if shown.isNull || shown["error"].isTruthy {
                Text(verbatim: L10n.text(K.sections.stress.unavailable))
                    .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
            } else {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    summary(shown)
                    findings(shown)
                }
            }
        }
        .onAppear { model.attach(host) }
        .task(id: host?.selections()) { model.attach(host) }
        .onChange(of: data) { _, _ in model.attach(host) }
    }

    private func color(_ overall: String) -> Color {
        switch overall {
        case "green": Palette.color(.emerald, .s600)
        case "red": Palette.color(.red, .s600)
        default: Palette.color(.amber, .s600)
        }
    }

    private func summary(_ shown: JSONValue) -> some View {
        let overall = Self.overall(shown)
        return VCard {
            HStack(alignment: .top, spacing: Spacing.md) {
                scoreRing(Self.score(shown), color: color(overall))
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(verbatim: L10n.text(overallKey(overall)))
                        .font(VFont.body(.footnote, weight: .semibold))
                        .foregroundStyle(color(overall))
                    if let text = shown["summary"].string, !text.isEmpty {
                        Text(verbatim: text).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(verbatim: L10n.text(K.sections.stress.blurb)).font(VFont.body(.caption))
                        .foregroundStyle(SemanticColor.textMuted).fixedSize(horizontal: false, vertical: true)
                    status
                    if model.canRecheck && (model.rechecked == nil || model.isStale) { recheckButton }
                    if let message = model.errorMessage {
                        Text(verbatim: message).font(VFont.body(.caption)).foregroundStyle(SemanticColor.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isStaticText)
                    }
                }
            }
        }
    }

    private func overallKey(_ overall: String) -> LKey {
        switch overall {
        case "green": K.sections.stress.overall.green
        case "red": K.sections.stress.overall.red
        default: K.sections.stress.overall.amber
        }
    }

    @ViewBuilder private var status: some View {
        if model.layoutMoved {
            if model.rechecked == nil {
                note(K.sections.stress.checkedOriginal, Palette.color(.amber, .s700))
            } else if model.isStale {
                note(K.sections.stress.staleNote, Palette.color(.amber, .s700))
            } else {
                note(K.sections.stress.checkedEdited, Palette.color(.teal, .s700))
            }
        }
    }

    private func note(_ key: LKey, _ tint: Color) -> some View {
        Text(verbatim: L10n.text(key)).font(VFont.body(.caption)).foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var recheckButton: some View {
        VButton(
            L10n.text(model.isRechecking ? K.sections.stress.rechecking : K.sections.stress.recheck),
            tid: "stress.recheck", role: .tonal,
            systemImage: model.isRechecking ? "hourglass" : "arrow.clockwise"
        ) {
            Task { await model.recheck() }
        }
        .disabled(model.isRechecking)
    }

    private func scoreRing(_ score: Int?, color: Color) -> some View {
        ZStack {
            Circle().stroke(SemanticColor.border, lineWidth: 6)
            Circle().trim(from: 0, to: CGFloat(score ?? 0) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
            Text(verbatim: score.map { String($0) } ?? "–")
                .font(VFont.body(.subheadline, weight: .bold)).foregroundStyle(SemanticColor.text)
        }
        .frame(width: 56, height: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: score.map { String($0) } ?? ""))
    }

    @ViewBuilder private func findings(_ shown: JSONValue) -> some View {
        let groups = Self.grouped(shown)
        if groups.isEmpty {
            Text(verbatim: L10n.text(K.sections.stress.none))
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
        } else {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        if let day = group.day {
                            Text(verbatim: L10n.text(K.sections.stress.day, ["n": String(day)]))
                                .font(VFont.display(.headline)).foregroundStyle(SemanticColor.text)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(Array(group.findings.enumerated()), id: \.offset) { _, finding in
                            findingCard(finding)
                        }
                    }
                }
            }
        }
    }

    private func severityKey(_ severity: String?) -> LKey {
        switch severity {
        case "high": K.sections.stress.severity.high
        case "medium": K.sections.stress.severity.medium
        default: K.sections.stress.severity.low
        }
    }

    private func severityColor(_ severity: String?) -> Color {
        switch severity {
        case "high": Palette.color(.red, .s700)
        case "medium": Palette.color(.amber, .s700)
        default: Palette.color(.sky, .s700)
        }
    }

    private func categoryText(_ category: String) -> String {
        switch category {
        case "budget": L10n.text(K.sections.stress.category.budget)
        case "logistics": L10n.text(K.sections.stress.category.logistics)
        case "pacing": L10n.text(K.sections.stress.category.pacing)
        case "timing": L10n.text(K.sections.stress.category.timing)
        case "visa": L10n.text(K.sections.stress.category.visa)
        case "weather": L10n.text(K.sections.stress.category.weather)
        default: category
        }
    }

    private func findingCard(_ finding: JSONValue) -> some View {
        let severity = finding["severity"].string
        return VCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text(verbatim: L10n.text(severityKey(severity)))
                        .font(VFont.body(.caption, weight: .semibold)).foregroundStyle(severityColor(severity))
                    if let category = finding["category"].string, !category.isEmpty {
                        Text(verbatim: categoryText(category)).font(VFont.body(.caption))
                            .foregroundStyle(SemanticColor.textMuted)
                    }
                }
                if let issue = finding["issue"].string {
                    Text(verbatim: issue).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let fix = finding["suggestion"].string, !fix.isEmpty {
                    Label { Text(verbatim: fix) } icon: { Image(systemName: "lightbulb") }
                        .font(VFont.body(.subheadline)).foregroundStyle(Palette.color(.teal, .s700))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
