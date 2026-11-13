import Foundation
import Networking
import Observation
import VoyagerEnv
import VoyagerModel

/// One point of a daily chart.
struct DailyPoint: Identifiable, Hashable {
    let date: Date
    let value: Int
    var id: Date { date }
}

/// The Analytics tab. A 404 (older backend, telemetry off) hides the tab.
@MainActor @Observable
final class AnalyticsModel {
    enum Phase: Equatable { case idle, loading, loaded, unavailable, failed }

    nonisolated static let days = 30

    private let repo: any AdminRepository
    private(set) var phase: Phase = .idle
    private(set) var summary = TelemetrySummary()

    init(env: AppEnvironment) { repo = env.repos.admin }

    var isAvailable: Bool { phase != .unavailable }

    func load() async {
        guard phase != .loading else { return }
        phase = .loading
        do {
            summary = try await repo.telemetrySummary(days: Self.days)
            phase = .loaded
        } catch let error as APIError {
            switch error {
            case .notFound: phase = .unavailable
            case .cancelled: phase = .idle
            default: phase = .failed
            }
        } catch {
            phase = error is CancellationError ? .idle : .failed
        }
    }

    nonisolated static func parse(day: String?) -> Date? {
        guard let day, day.count >= 10 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(day.prefix(10)))
    }

    /// Days sorted oldest first; a day with an unreadable date is dropped.
    private var ordered: [(date: Date, day: TelemetryDay)] {
        summary.days.compactMap { day in Self.parse(day: day.day).map { (date: $0, day: day) } }
            .sorted { $0.date < $1.date }
    }

    func series(_ value: (TelemetryDay) -> Int?) -> [DailyPoint] {
        ordered.map { DailyPoint(date: $0.date, value: max(0, value($0.day) ?? 0)) }
    }

    var users: [DailyPoint] { series(\.users) }
    var sessions: [DailyPoint] { series(\.sessions) }
    var events: [DailyPoint] { series(\.events) }

    var usersToday: Int { users.last?.value ?? 0 }
    var sessionsToday: Int { sessions.last?.value ?? 0 }
    /// Sum of the last seven days of daily users; saturates instead of overflowing.
    var userDays7: Int { Self.saturatingSum(users.suffix(7).map(\.value)) }

    nonisolated static func saturatingSum(_ values: [Int]) -> Int {
        values.reduce(0) { total, value in
            let (sum, overflow) = total.addingReportingOverflow(value)
            return overflow ? Int.max : sum
        }
    }

    var topEvents: [TelemetryTopEvent] { summary.topEvents.filter { $0.event != nil } }
    var topScreens: [TelemetryTopScreen] { summary.topScreens.filter { $0.route != nil } }
    var isEmpty: Bool { summary.days.isEmpty && topEvents.isEmpty && topScreens.isEmpty }
}
