import AuthCore
import Foundation
import Networking
import Testing
import VoyagerModel
@testable import VoyagerData

struct LiveAuthAPITests {
    @Test func test_providers404IsEmpty() async throws {
        let h = try Harness(token: nil) { _ in .init(status: 404, json: #"{"detail":"Not Found"}"#) }
        #expect(try await LiveAuthAPI(api: h.api).providers() == [])
        #expect(h.request?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(h.request?.url?.path == "/api/auth/providers")
    }

    @Test func test_providersLenientlySkipsUnknownIds() async throws {
        let h = try Harness { _ in
            .init(json: #"{"providers":[{"id":"apple","configured":true,"start_url":"https://x.y/a"},{"id":"myspace","configured":true},{"id":"github","configured":false}]}"#)
        }
        let list = try await LiveAuthAPI(api: h.api).providers()
        #expect(list.map(\.id) == [.apple, .github])
        #expect(list.first?.configured == true)
    }

    @Test func test_providersServerErrorPropagates() async throws {
        let h = try Harness { _ in .init(status: 500, json: #"{"detail":"boom"}"#) }
        await #expect(throws: APIError.server(status: 500, detail: "boom")) { _ = try await LiveAuthAPI(api: h.api).providers() }
    }

    @Test func test_loginDecodes() async throws {
        let h = try Harness(token: nil) { _ in
            .init(json: #"{"access_token":"jwt.a.b","token_type":"bearer","user":{"username":"alice","is_admin":true,"requires_password_change":false,"email":null}}"#)
        }
        let response = try await LiveAuthAPI(api: h.api).login(username: "alice", password: "pw")
        #expect(response.accessToken == "jwt.a.b")
        #expect(response.user.username == "alice")
        #expect(response.user.isAdmin)
        #expect(h.request?.url?.path == "/api/auth/login")
        #expect(h.request?.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try h.body()
        #expect(body["username"].string == "alice")
        #expect(body["password"].string == "pw")
    }

    @Test func test_changePasswordAndMe() async throws {
        let h = try Harness { request in
            request.url?.path == "/api/auth/me"
                ? .init(json: #"{"username":"alice","is_admin":false,"requires_password_change":false,"email":"a@b.co"}"#)
                : .init(json: #"{"access_token":"fresh","token_type":"bearer"}"#)
        }
        let api = LiveAuthAPI(api: h.api)
        #expect(try await api.changePassword(current: "old", new: "newpassword") == "fresh")
        #expect(try h.body()["current_password"].string == "old")
        #expect(try h.body()["new_password"].string == "newpassword")
        #expect(try await api.me().email == "a@b.co")
    }

    @Test func test_loginWrongCredentialsIsUnauthorized() async throws {
        let h = try Harness(token: nil) { _ in .init(status: 401, json: #"{"detail":"Incorrect username or password"}"#) }
        await #expect(throws: APIError.unauthorized) { _ = try await LiveAuthAPI(api: h.api).login(username: "a", password: "b") }
    }
}
