import Testing
@testable import BudsProtocol

@Test func versionIsSet() {
    #expect(BudsProtocol.version == "0.1.0")
}
