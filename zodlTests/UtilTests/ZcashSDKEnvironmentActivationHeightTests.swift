import Testing
@preconcurrency import ZcashLightClientKit
@testable import zodl_internal

@Suite struct ZcashSDKEnvironmentActivationHeightTests {
    @Test func mainnetActivationHeight() {
        let environment = ZcashSDKEnvironment.live(network: ZcashNetworkBuilder.network(for: .mainnet))
        #expect(environment.ironwoodActivationHeight() == 3_428_143)
    }

    @Test func testnetActivationHeight() {
        let environment = ZcashSDKEnvironment.live(network: ZcashNetworkBuilder.network(for: .testnet))
        #expect(environment.ironwoodActivationHeight() == 4_134_000)
    }

    @Test func memberwiseDefaultFailsClosed() {
        #expect(ZcashSDKEnvironment().ironwoodActivationHeight() == BlockHeight.max)
    }
}
