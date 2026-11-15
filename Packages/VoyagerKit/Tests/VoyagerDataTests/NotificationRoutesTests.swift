import Foundation
import Networking
import Testing
import VoyagerModel

@testable import VoyagerData

struct NotificationRoutesTests {
    @Test func test_routes() {
        let get = Endpoints.notificationSettings()
        #expect(get.method == .get && get.path == "/api/notification-settings" && get.auth == .required)
        let put = Endpoints.updateNotificationSettings(NotificationSettingsPatch(dailyCap: 4))
        #expect(put.method == .put && put.path == "/api/notification-settings")
        let catalog = Endpoints.notificationCatalog(locale: .es)
        #expect(catalog.path == "/api/notifications/catalog" && catalog.query == [URLQueryItem(name: "locale", value: "es")])
    }

    @Test func test_noCoordinatesInAnyNewCall() {
        let queries = [
            Endpoints.notificationSettings().query, Endpoints.notificationCatalog(locale: .de).query,
            Endpoints.updateNotificationSettings(NotificationSettingsPatch()).query,
        ]
        for query in queries {
            let names = Set(query.map(\.name))
            #expect(names.isDisjoint(with: ["lat", "lng", "lon", "latitude", "longitude"]))
        }
    }

    @Test func test_invalidCodeIsReadFromTheEnvelope() {
        let code = NotificationSettingsFailure.invalid.rawValue
        let error = APIError.client(status: 422, detail: "bad", code: code, body: .object(["error_code": .string(code)]))
        #expect(NotificationSettingsFailure.from(error) == .invalid)
        let other = APIError.client(status: 422, detail: "x", code: "something_else", body: .object([:]))
        #expect(NotificationSettingsFailure.from(other) == nil)
        #expect(NotificationSettingsFailure.from(.network) == nil)
    }
}
