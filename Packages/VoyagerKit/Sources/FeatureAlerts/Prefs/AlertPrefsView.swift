import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// Settings > Alert preferences. Reached from the You tab (only with `alerts_api` 2); on an older backend, by a deep
/// route, it shows nothing but the title.
public struct AlertPrefsView: View {
    @State private var model: AlertPrefsModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @MainActor public init(env: AppEnvironment) {
        _model = State(initialValue: AlertPrefsModel(env: env))
    }

    @MainActor init(model: AlertPrefsModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            // VStack, not LazyVStack: lazy stacks hang hosted snapshot tests.
            VStack(alignment: .leading, spacing: Spacing.xl) {
                switch model.phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity).padding(Spacing.xl)
                        .accessibilityIdentifier("alertPrefs.loading")
                case .failed:
                    VStack(spacing: Spacing.sm) {
                        ErrorState(error: model.loadError) { Task { await model.load() } }
                        Text(verbatim: L10n.text(K.alertPrefs.error.load))
                            .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                    }
                case .unavailable:
                    EmptyView()
                case .loaded:
                    form
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(SemanticColor.surface)
        // Beyond this size German compounds no longer fit a phone-width card without splitting mid-word.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .navigationTitle(L10n.text(K.alertPrefs.title))
        .task { await model.load() }
        .accessibilityIdentifier("alertPrefs.root")
    }

    @ViewBuilder private var form: some View {
        Text(verbatim: L10n.text(K.alertPrefs.intro))
            .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        digest
        instant
        quietHours
        caps
        grouping
        if let message = model.saveFailureMessage {
            Text(verbatim: message)
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("alertPrefs.saveFailed")
        }
    }

    // MARK: Sections

    private var digest: some View {
        PrefsGroup(title: nil) {  // the row below carries the same title
            PrefsToggleRow(
                title: L10n.text(K.alertPrefs.digest.label), hint: nil, tid: "alertPrefs.digestWeekly",
                isOn: Binding(get: { model.prefs.digestWeekly }, set: { model.setDigestWeekly($0) }))
            if model.prefs.digestWeekly {
                dayPicker
            }
            PrefsToggleRow(
                title: L10n.text(K.alertPrefs.digest.push), hint: nil, tid: "alertPrefs.digestPush",
                isOn: Binding(get: { model.prefs.digestPush }, set: { model.setDigestPush($0) })
            )
            .disabled(!model.canEditDigestPush)
        }
    }

    private var dayPicker: some View {
        HStack {
            Text(verbatim: L10n.text(K.alertPrefs.digest.day)).font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
            Spacer(minLength: Spacing.sm)
            Picker(selection: Binding(get: { model.prefs.digestDay }, set: { model.setDigestDay($0) })) {
                ForEach(1...7, id: \.self) { day in Text(verbatim: Self.dayName(day)).tag(day) }
            } label: {
                Text(verbatim: L10n.text(K.alertPrefs.digest.day))
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(SemanticColor.primary)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alertPrefs.digestDay")
    }

    private var instant: some View {
        PrefsGroup(title: nil) {  // the row below carries the same title
            PrefsToggleRow(
                title: L10n.text(K.alertPrefs.instant.label), hint: L10n.text(K.alertPrefs.instant.hint),
                tid: "alertPrefs.instant",
                isOn: Binding(get: { model.prefs.instant == .targetsOnly }, set: { model.setInstantTargetsOnly($0) }))
        }
    }

    private var quietHours: some View {
        PrefsGroup(title: nil) {  // the row below carries the same title
            PrefsToggleRow(
                title: L10n.text(K.alertPrefs.quiet.label), hint: nil, tid: "alertPrefs.quiet",
                isOn: Binding(get: { model.prefs.quietHours.enabled }, set: { model.setQuietEnabled($0) }))
            if model.prefs.quietHours.enabled {
                clockRow(title: L10n.text(K.alertPrefs.quiet.start), tid: "alertPrefs.quietStart", value: model.prefs.quietHours.start) {
                    model.setQuietTimes(start: $0)
                }
                clockRow(title: L10n.text(K.alertPrefs.quiet.end), tid: "alertPrefs.quietEnd", value: model.prefs.quietHours.end) {
                    model.setQuietTimes(end: $0)
                }
            }
            // The time zone is the account's; it is read-only here.
            Text(verbatim: timezoneText)
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("alertPrefs.timezone")
        }
    }

    private var timezoneText: String {
        guard let zone = model.prefs.timezone else { return L10n.text(K.alertPrefs.quiet.inactive) }
        return L10n.text(K.alertPrefs.quiet.timezone, ["tz": zone])
    }

    @ViewBuilder private func clockRow(title: String, tid: String, value: String, set: @escaping (String) -> Void) -> some View {
        let selection = Binding(get: { PrefsClock.date(value) }, set: { set(PrefsClock.text($0)) })
        if dynamicTypeSize.isAccessibilitySize {
            // At accessibility sizes the compact picker takes the whole row, so the label goes above it.
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: title).font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
                DatePicker(selection: selection, displayedComponents: .hourAndMinute) { Text(verbatim: title) }
                    .labelsHidden()
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(tid)
        } else {
            DatePicker(selection: selection, displayedComponents: .hourAndMinute) {
                Text(verbatim: title).font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier(tid)
        }
    }

    private var caps: some View {
        PrefsGroup(title: L10n.text(K.alertPrefs.caps.label)) {
            ForEach(WatchKind.allCases, id: \.self) { kind in
                let name = Self.kindName(kind)
                Stepper(
                    value: Binding(get: { model.prefs.dailyCap[kind] }, set: { model.setCap(kind, $0) }),
                    in: AlertPrefsModel.capRange
                ) {
                    HStack {
                        Text(verbatim: name).font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
                        Spacer(minLength: Spacing.sm)
                        Text(verbatim: String(model.prefs.dailyCap[kind])).font(VFont.body(.body, weight: .semibold))
                            .foregroundStyle(SemanticColor.text)
                    }
                }
                .frame(minHeight: 44)
                .accessibilityLabel(name)
                .accessibilityValue(String(model.prefs.dailyCap[kind]))
                .accessibilityIdentifier("alertPrefs.cap.\(kind.rawValue)")
            }
            Text(verbatim: L10n.text(K.alertPrefs.caps.hint))
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var grouping: some View {
        PrefsGroup(title: L10n.text(K.alertPrefs.group.label)) {
            Stepper(
                value: Binding(get: { model.prefs.groupWindowMin }, set: { model.setGroupWindow($0) }),
                in: AlertPrefsModel.groupRange, step: AlertPrefsModel.groupStep
            ) {
                Text(verbatim: Self.groupText(model.prefs.groupWindowMin))
                    .font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
            }
            .frame(minHeight: 44)
            .accessibilityLabel(L10n.text(K.alertPrefs.group.label))
            .accessibilityValue(Self.groupText(model.prefs.groupWindowMin))
            .accessibilityIdentifier("alertPrefs.group")
            Text(verbatim: L10n.text(K.alertPrefs.group.hint))
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Words

    static func groupText(_ minutes: Int) -> String {
        minutes == 0 ? L10n.text(K.alertPrefs.group.off) : L10n.text(K.alertPrefs.group.minutes, count: minutes)
    }

    static func kindName(_ kind: WatchKind) -> String {
        switch kind {
        case .flight: L10n.text(K.alertPrefs.kind.flight)
        case .hotel: L10n.text(K.alertPrefs.kind.hotel)
        case .activity: L10n.text(K.alertPrefs.kind.activity)
        case .trip: L10n.text(K.alertPrefs.kind.trip)
        }
    }

    static func dayName(_ day: Int) -> String {
        switch day {
        case 1: L10n.text(K.alertPrefs.day._1)
        case 2: L10n.text(K.alertPrefs.day._2)
        case 3: L10n.text(K.alertPrefs.day._3)
        case 4: L10n.text(K.alertPrefs.day._4)
        case 5: L10n.text(K.alertPrefs.day._5)
        case 6: L10n.text(K.alertPrefs.day._6)
        default: L10n.text(K.alertPrefs.day._7)
        }
    }
}

/// A titled card of rows.
private struct PrefsGroup<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let title {
                Text(verbatim: title)
                    .font(VFont.display(.headline)).foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            VCard {
                VStack(alignment: .leading, spacing: Spacing.md) { content }
            }
        }
    }
}

/// A switch with an optional hint under its label.
private struct PrefsToggleRow: View {
    let title: String
    let hint: String?
    let tid: String
    @Binding var isOn: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // The switch would leave the label a sliver of the row: label above, switch below.
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    label
                    Toggle(isOn: $isOn) { Text(verbatim: title) }.labelsHidden()
                }
            } else {
                Toggle(isOn: $isOn) { label }
            }
        }
        .tint(SemanticColor.primary)
        .telemetryToggle(tid: tid, value: isOn)
        .accessibilityIdentifier(tid)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title).font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
            if let hint {
                Text(verbatim: hint).font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// `HH:MM` (the wire form) to a `Date` on today's date in the device calendar and back, for the time pickers.
enum PrefsClock {
    static func date(_ text: String, calendar: Calendar = .current, on day: Date = Date()) -> Date {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        let hour = parts.first ?? 0
        let minute = parts.count > 1 ? parts[1] : 0
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    static func text(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
