import Testing
@testable import Telemetry
import VoyagerModel

@Suite struct TelemetryEventTests {
    @Test func test_namesAndPropNamesAreTheRegistrys() {
        let view = TelemetryEvent.screenView(route: "/chat", referrer: "/").wire
        #expect(view.name == "screen_view")
        #expect(view.props["referrer_route"] == .string("/"))
        #expect(view.screen == "/chat")

        let submit = TelemetryEvent.searchSubmit(mode: .link, travelers: 2, nights: 5, multiCity: true).wire
        #expect(submit.props["multi_city"] == .bool(true))
        #expect(submit.props["mode"] == .string("link"))

        let error = TelemetryEvent.apiError(source: "search", status: 503).wire
        #expect(error.name == "error")
        #expect(error.props == ["kind": .string("api"), "source": .string("search"), "status": .number(503)])

        let consent = TelemetryEvent.consentGranted.wire
        #expect(consent.name == "consent")
        #expect(consent.props == ["choice": .string("granted")])
    }

    @Test func test_nilReferrerIsOmitted() {
        #expect(TelemetryEvent.screenView(route: "/", referrer: nil).wire.props["referrer_route"] == nil)
    }

    @Test func test_freeTextPropsAreDroppedNotSent() {
        let tap = TelemetryEvent.uiTap(tid: "Jane Doe's trip", route: "/plans/:id").wire
        #expect(tap.props["tid"] == nil)
        #expect(tap.props["route"] == .string("/plans/:id"))
        #expect(TelemetryEvent.themeChange("purple").wire.props["theme"] == nil)
        #expect(TelemetryEvent.themeChange("dark").wire.props["theme"] == .string("dark"))
        #expect(TelemetryEvent.perf(metric: .ttfb, value: .nan, route: "/").wire.props["value"] == nil)
    }

    @Test func test_languageChangeUsesTheCode() {
        #expect(TelemetryEvent.languageChange(.zh).wire.props["lang"] == .string("zh"))
    }
}
