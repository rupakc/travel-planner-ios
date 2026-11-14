import Foundation
import Networking
import Telemetry
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureAlerts

@MainActor
struct PriceStoryTests {
    private func config(alertsAPI: Int = 2) -> ClientConfig {
        ClientConfig(features: ["alerts_api": .number(Double(alertsAPI)), "price_alerts_v2": .bool(true), "live_prices": .bool(true)])
    }

    private func envWith(
        _ story: PriceStory? = goodFlightStory, alertsAPI: Int = 2
    ) -> (AppEnvironment, FakeRepositories) {
        let fakes = FakeRepositories()
        if let story { fakes.alertsV2.onStory.returns(story) }
        return (AppEnvironment.fake(fakes: fakes, clientConfig: config(alertsAPI: alertsAPI)), fakes)
    }

    private final class Events {
        var storyViews: [String] = []
        var advice: [String] = []
        func record(_ event: TelemetryEvent) {
            switch event {
            case .alertStoryView(let kind, let verdict): storyViews.append("\(kind):\(verdict)")
            case .alertAdvice(let kind, let outcome): advice.append("\(kind):\(outcome)")
            default: break
            }
        }
    }

    // MARK: Copy

    @Test func test_adviceCodeCopyForAll8() {
        let advices = [
            StoryAdvice(code: .pending), StoryAdvice(code: .checksPaused, params: ["days": 5]),
            StoryAdvice(code: .belowTarget, params: ["by": 12]), StoryAdvice(code: .nearTarget, params: ["gap": 32]),
            StoryAdvice(code: .atLowest), StoryAdvice(code: .belowTypical), StoryAdvice(code: .withinTypical),
            StoryAdvice(code: .aboveTypical), StoryAdvice(code: .steady, params: ["days": 4]),
            StoryAdvice(code: .fewChecks, params: ["n": 2]),
        ]
        var seen = Set<String>()
        for advice in advices {
            let text = PriceStoryModel.adviceText(advice, currency: "USD")
            #expect(text?.isEmpty == false, "no copy for \(advice.code.wire)")
            #expect(text?.contains("{{") == false, "unfilled placeholder in \(advice.code.wire)")
            seen.insert(text ?? "")
        }
        #expect(seen.count == advices.count)
        #expect(PriceStoryModel.adviceText(StoryAdvice(code: .nearTarget, params: ["gap": 32]), currency: "USD")?.contains("$32") == true)
        #expect(PriceStoryModel.adviceText(StoryAdvice(code: .checksPaused, params: ["days": 1]), currency: "USD")?.contains("1 day ") == true)
    }

    @Test func test_unknownAdviceCodeShowsNoLine() {
        #expect(PriceStoryModel.adviceText(StoryAdvice(code: .unknown("from_the_future")), currency: "USD") == nil)
        #expect(PriceStoryModel.adviceText(nil, currency: "USD") == nil)
    }

    @Test func test_checksPausedNeverSaysGreatPrice() {
        // Even if a (stale) story still carries a verdict, the chip is hidden and no line calls the price great.
        var story = pausedStory
        story.verdict = .great
        #expect(PriceStoryModel.verdict(of: story) == nil)
        let line = PriceStoryModel.adviceText(story.advice, currency: "USD")?.lowercased() ?? ""
        #expect(line.contains("paused"))
        #expect(!line.contains("great") && !line.contains("good"))
        #expect(PriceStoryModel.checkedText(story)?.contains("6 days ago") == true)
    }

    @Test func test_verdictAbsentMeansNoChip() {
        var story = goodFlightStory
        story.verdict = nil
        #expect(PriceStoryModel.verdict(of: story) == nil)
        #expect(PriceStoryModel.verdict(of: goodFlightStory) == .good)
    }

    @Test func test_checkedAgeComesFromTheServer() {
        #expect(PriceStoryModel.checkedText(highHotelStory) == "Checked today")
        #expect(PriceStoryModel.checkedText(goodFlightStory) == "Checked 1 day ago")
        #expect(PriceStoryModel.checkedText(pendingStory) == nil)
    }

    // MARK: Chart

    @Test func test_estimateNeverPlotted() {
        let data = StoryChartData(story: pendingStory)
        #expect(data.points.isEmpty && !data.showsChart)
        #expect(PriceStoryModel.estimateText(pendingStory)?.contains("Estimate") == true)
        #expect(PriceStoryModel.estimateText(pendingStory)?.contains("€352") == true)
        // The estimate is not among the points of a story that has observed ones either.
        var story = goodFlightStory
        story.estimate = StoryEstimate(price: 1, source: "typical")
        #expect(StoryChartData(story: story).points.count == goodFlightStory.points.count)
    }

    @Test func test_chartNeedsTwoChecks() {
        var story = goodFlightStory
        story.points = [point(1, 441)]
        #expect(!StoryChartData(story: story).showsChart)
        #expect(StoryChartData(story: goodFlightStory).showsChart)
    }

    @Test func test_yDomainHoldsEverythingDrawn() {
        let data = StoryChartData(story: goodFlightStory)
        #expect(data.yDomain.contains(430) && data.yDomain.contains(560) && data.yDomain.contains(500))
    }

    @Test func test_scrubReadsPointAndAge() async {
        let (env, _) = envWith()
        let model = PriceStoryModel(env: env, kind: .flight, watchID: 1, track: { _ in }, now: { fixedNow })
        await model.load()
        // Nearest to eight days ago, a little late: the 470 check.
        model.scrub(to: fixedNow.addingTimeInterval(-86_400 * 7.8))
        #expect(model.selected?.price == 470)
        let readout = model.readout(for: model.selected ?? point(0, 0))
        #expect(readout.contains("$470"))
        #expect(readout.lowercased().contains("ago") || readout.contains("8"))
        model.selectFirst()
        #expect(model.selected?.price == 500)
        model.selectLatest()
        #expect(model.selected?.price == 441)
        model.clearSelection()
        #expect(model.selected == nil)
    }

    @Test func test_voiceOverDescriptorHasOnePointPerCheck() {
        let data = StoryChartData(story: goodFlightStory)
        let descriptor = StoryChartDescriptor.descriptor(for: data)
        #expect(descriptor.series.first?.dataPoints.count == 6)
        #expect(descriptor.summary?.contains("6") == true)
        #expect(descriptor.series.first?.dataPoints.first?.label?.contains("$500") == true)
        #expect(StoryChartDescriptor.summary(for: StoryChartData(story: pendingStory)) == "No price checks yet.")
    }

    // MARK: Loading and telemetry

    @Test func test_storyViewEmitsOnce() async {
        let (env, fakes) = envWith()
        let events = Events()
        let model = PriceStoryModel(env: env, kind: .flight, watchID: 1, track: { events.record($0) }, now: { fixedNow })
        await model.load()
        await model.load()
        #expect(fakes.alertsV2.onStory.callCount == 2)
        #expect(events.storyViews == ["flight:good"])
    }

    @Test func test_storyWithoutVerdictIsReportedAsNone() async {
        let (env, _) = envWith(pausedStory)
        let events = Events()
        let model = PriceStoryModel(env: env, kind: .flight, watchID: 1, track: { events.record($0) }, now: { fixedNow })
        await model.load()
        #expect(events.storyViews == ["flight:none"])
    }

    @Test func test_olderBackendShowsNoStoryAndMakesNoCall() async {
        let (env, fakes) = envWith(alertsAPI: 0)
        let model = PriceStoryModel(env: env, kind: .flight, watchID: 1, track: { _ in }, now: { fixedNow })
        await model.load()
        #expect(model.phase == .unavailable)
        #expect(fakes.alertsV2.onStory.callCount == 0)
    }

    @Test func test_failedRefreshKeepsTheStory() async {
        let (env, fakes) = envWith()
        let model = PriceStoryModel(env: env, kind: .flight, watchID: 1, track: { _ in }, now: { fixedNow })
        await model.load()
        fakes.alertsV2.onStory.fails(APIError.network)
        await model.load()
        #expect(model.story == goodFlightStory)
    }

    @Test func test_failedFirstLoadIsAnErrorWithRetry() async {
        let (env, fakes) = envWith()
        fakes.alertsV2.onStory.fails(APIError.network)
        let model = PriceStoryModel(env: env, kind: .flight, watchID: 1, track: { _ in }, now: { fixedNow })
        await model.load()
        #expect(model.phase == .failed("Could not load the price story."))
    }

    // MARK: AI timing tip

    @Test func test_tipIsOfferedForFlightsWithAPriceOnly() async {
        let (env, _) = envWith()
        let flight = PriceStoryModel(env: env, kind: .flight, watchID: 1, track: { _ in }, now: { fixedNow })
        #expect(!flight.canAskForTip)
        await flight.load()
        #expect(flight.canAskForTip)
        let (hotelEnv, _) = envWith(highHotelStory)
        let hotel = PriceStoryModel(env: hotelEnv, kind: .hotel, watchID: 4, track: { _ in }, now: { fixedNow })
        await hotel.load()
        #expect(!hotel.canAskForTip)
        let (pendingEnv, _) = envWith(pendingStory)
        let pending = PriceStoryModel(env: pendingEnv, kind: .flight, watchID: 1, track: { _ in }, now: { fixedNow })
        await pending.load()
        #expect(!pending.canAskForTip)
    }

    @Test func test_tipSuccessAndCachedAreReported() async {
        let (env, fakes) = envWith()
        let events = Events()
        let model = PriceStoryModel(env: env, kind: .flight, watchID: 1, track: { events.record($0) }, now: { fixedNow })
        await model.load()
        fakes.alertsV2.onAdvice.returns(AdviceTip(tip: "Prices usually dip midweek.", cached: false))
        await model.requestTip()
        #expect(model.tip == .tip(AdviceTip(tip: "Prices usually dip midweek.", cached: false)))
        fakes.alertsV2.onAdvice.returns(AdviceTip(tip: "Prices usually dip midweek.", cached: true))
        await model.requestTip()
        #expect(events.advice == ["flight:ok", "flight:cached"])
    }

    @Test func test_adviceErrorMapping() async {
        let limit = "The AI limit is reached for this month."
        let general = "Could not get a tip right now."
        func server(_ status: Int, _ code: String?) -> APIError { .server(status: status, detail: "backend text", code: code) }
        #expect(PriceStoryModel.adviceMessage(server(503, "ai_limit")) == limit)
        #expect(PriceStoryModel.adviceMessage(server(503, "ai_billing")) == limit)
        #expect(PriceStoryModel.adviceMessage(server(502, "advice_failed")) == general)
        #expect(
            PriceStoryModel.adviceMessage(APIError.client(status: 422, detail: "x", code: "advice_no_data", body: .null)) == general)
        #expect(
            PriceStoryModel.adviceMessage(
                APIError.client(status: 422, detail: "x", code: nil, body: .object(["error_code": .string("advice_unsupported")])))
                == general)
        #expect(PriceStoryModel.adviceMessage(APIError.notFound("watch_not_found")) == general)
        #expect(PriceStoryModel.adviceMessage(APIError.network) == general)
        // A backend without the route: the service refuses the call itself.
        let (oldEnv, _) = envWith(alertsAPI: 0)
        do {
            _ = try await oldEnv.alertsV2.advice(kind: .flight, id: 1)
            Issue.record("expected Unavailable")
        } catch {
            #expect(PriceStoryModel.adviceMessage(error) == general)
        }
        #expect(
            PriceStoryModel.adviceMessage(APIError.rateLimited(message: "Too many requests, wait 30 s.", retryAfter: 30))
                == "Too many requests, wait 30 s.")
    }

    @Test func test_tipFailureShowsMessageAndEmitsError() async {
        let (env, fakes) = envWith()
        let events = Events()
        let model = PriceStoryModel(env: env, kind: .flight, watchID: 1, track: { events.record($0) }, now: { fixedNow })
        await model.load()
        fakes.alertsV2.onAdvice.fails(APIError.server(status: 503, detail: nil, code: "ai_limit"))
        await model.requestTip()
        #expect(model.tip == .failed("The AI limit is reached for this month."))
        #expect(events.advice == ["flight:error"])
    }

    @Test func test_storeKeepsOneModelPerWatch() {
        let store = PriceStoryStore(env: AppEnvironment.fake(), track: { _ in })
        #expect(store.model(kind: .flight, watchID: 1) === store.model(kind: .flight, watchID: 1))
        #expect(store.model(kind: .flight, watchID: 1) !== store.model(kind: .hotel, watchID: 1))
    }
}
