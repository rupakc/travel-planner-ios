import Testing
import Telemetry
import VoyagerModel

@Suite struct PropsFilterTests {
    @Test func test_emailRejected() { #expect(PropsFilter.token("jane@x.com") == nil) }
    @Test func test_spaceRejected() { #expect(PropsFilter.token("my trip") == nil) }
    @Test func test_65CharsRejected() {
        #expect(PropsFilter.token(String(repeating: "a", count: 65)) == nil)
        #expect(PropsFilter.token(String(repeating: "a", count: 64)) != nil)
    }
    @Test func test_boolNotInt() {
        #expect(PropsFilter.int(.bool(true)) == nil)
        #expect(PropsFilter.int(.number(3)) == 3)
    }
    @Test func test_tokenAlphabet() {
        #expect(PropsFilter.token("a-Z_0.9:/x") == "a-Z_0.9:/x")
        #expect(PropsFilter.token("") == nil)
        #expect(PropsFilter.token("tokyo\n") == nil)
        #expect(PropsFilter.token("é") == nil)
        #expect(PropsFilter.token("a?b=c") == nil)
    }
    @Test func test_intRange() {
        #expect(PropsFilter.int(9_007_199_254_740_992) == 9_007_199_254_740_992)
        #expect(PropsFilter.int(9_007_199_254_740_993) == nil)
        #expect(PropsFilter.int(.number(1.5)) == nil)
        #expect(PropsFilter.int(.string("3")) == nil)
    }
    @Test func test_floatFinite() {
        #expect(PropsFilter.float(.infinity) == nil)
        #expect(PropsFilter.float(.nan) == nil)
        #expect(PropsFilter.float(1.5e20) == nil)
        #expect(PropsFilter.float(12.5) == 12.5)
    }
    @Test func test_boolAndEnum() {
        #expect(PropsFilter.bool(.number(1)) == nil)
        #expect(PropsFilter.bool(.bool(false)) == false)
        #expect(PropsFilter.enum("a", allowed: ["a", "b"]) == "a")
        #expect(PropsFilter.enum("c", allowed: ["a", "b"]) == nil)
    }
}
