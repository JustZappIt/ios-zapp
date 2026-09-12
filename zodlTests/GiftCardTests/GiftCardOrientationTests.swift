import Testing
@testable import zodl_internal

@Suite
struct GiftCardOrientationTests {
    @Test(arguments: [0.0, 45, 89.9, 270.1, 359.9, 360, 405, 720, -0.1, -45])
    func frontRemainsVisibleUntilTheCardPassesItsEdge(_ angle: Double) {
        #expect(!GiftCardOrientation.showsBack(at: angle))
    }

    @Test(arguments: [90.0, 90.1, 180, 269.9, 270, 450, 540, 810, -90, -180, -270])
    func reverseUsesTheCurrentAngleAcrossFlourishesAndOvershoot(_ angle: Double) {
        #expect(GiftCardOrientation.showsBack(at: angle))
    }
}
