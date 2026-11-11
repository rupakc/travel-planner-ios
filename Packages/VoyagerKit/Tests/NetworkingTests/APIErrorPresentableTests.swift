import Testing
import VoyagerModel

@testable import Networking

struct APIErrorPresentableTests {
    @Test func test_kindMapping() {
        #expect(APIError.unauthorized.presentationKind == .unauthorized)
        #expect(APIError.rateLimited(message: "slow down", retryAfter: 5).presentationKind == .rateLimited)
        #expect(APIError.network.presentationKind == .network)
        #expect(APIError.interrupted.presentationKind == .network)
        #expect(APIError.server(status: 500, detail: nil).presentationKind == .server)
        #expect(APIError.decoding.presentationKind == .other)
        #expect(APIError.notFound(nil).presentationKind == .other)
    }

    @Test func test_detailIsTheServersText() {
        #expect(APIError.rateLimited(message: "slow down", retryAfter: nil).userFacingDetail == "slow down")
        #expect(APIError.network.userFacingDetail == nil)
    }
}
