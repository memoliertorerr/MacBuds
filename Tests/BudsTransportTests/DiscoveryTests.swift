import Testing
@testable import BudsTransport

@Suite struct DiscoveryTests {
    @Test func matchesOnlyPlainBuds2Names() {
        #expect(BudsTransport.isBuds2("Galaxy Buds2"))
        #expect(BudsTransport.isBuds2("Galaxy Buds2"))
        #expect(!BudsTransport.isBuds2("Galaxy Buds2 Pro"))
        #expect(!BudsTransport.isBuds2("Galaxy Buds2 Pro (1234)"))
        #expect(!BudsTransport.isBuds2("Galaxy Buds+"))
        #expect(!BudsTransport.isBuds2("Galaxy Buds2Pro"))
        #expect(!BudsTransport.isBuds2("Galaxy Buds"))
        #expect(!BudsTransport.isBuds2(nil))
    }
}
