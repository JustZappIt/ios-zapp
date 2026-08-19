import CoreGraphics
import Foundation
import Testing
@testable import zodl_internal

@Suite
struct BalanceChartSelectionTests {
    private let points = [
        ZappChartPoint(timestamp: Date(timeIntervalSince1970: 0), value: 1),
        ZappChartPoint(timestamp: Date(timeIntervalSince1970: 10), value: 2),
        ZappChartPoint(timestamp: Date(timeIntervalSince1970: 70), value: 3),
        ZappChartPoint(timestamp: Date(timeIntervalSince1970: 100), value: 4)
    ]

    @Test
    func nearestPointFindsIrregularPoint() {
        #expect(nearestChartPointIndex(points: points, x: 20, width: 100) == 1)
        #expect(nearestChartPointIndex(points: points, x: 60, width: 100) == 2)
    }

    @Test
    func nearestPointClampsToChartEdges() {
        #expect(nearestChartPointIndex(points: points, x: -10, width: 100) == 0)
        #expect(nearestChartPointIndex(points: points, x: 110, width: 100) == 3)
    }

    @Test
    func nearestPointChoosesClosestPointAroundMidpoint() {
        #expect(nearestChartPointIndex(points: points, x: 4, width: 100) == 0)
        #expect(nearestChartPointIndex(points: points, x: 6, width: 100) == 1)
    }

    @Test
    func guidesRunFromPointToLabelledAxes() {
        let selected = CGPoint(x: 30, y: 40)

        let guides = crosshairGuides(selectedPoint: selected, size: CGSize(width: 100, height: 80))

        #expect(guides.verticalStart == selected)
        #expect(guides.verticalEnd == CGPoint(x: 30, y: 80))
        #expect(guides.horizontalStart == CGPoint(x: 0, y: 40))
        #expect(guides.horizontalEnd == selected)
    }

    @Test
    func guidesDrawNothingAboveOrRightOfPoint() {
        let selected = CGPoint(x: 30, y: 40)

        let guides = crosshairGuides(selectedPoint: selected, size: CGSize(width: 100, height: 80))

        #expect(guides.verticalStart.y >= selected.y)
        #expect(guides.verticalEnd.y >= selected.y)
        #expect(guides.horizontalStart.x <= selected.x)
        #expect(guides.horizontalEnd.x <= selected.x)
    }

    @Test
    func guidesStayInBoundsAtChartCorners() {
        let size = CGSize(width: 100, height: 80)

        let topLeft = crosshairGuides(selectedPoint: .zero, size: size)
        #expect(topLeft.verticalStart == .zero)
        #expect(topLeft.verticalEnd == CGPoint(x: 0, y: 80))
        #expect(topLeft.horizontalStart == .zero)

        let bottomRight = crosshairGuides(selectedPoint: CGPoint(x: 100, y: 80), size: size)
        #expect(bottomRight.verticalStart == CGPoint(x: 100, y: 80))
        #expect(bottomRight.verticalEnd == CGPoint(x: 100, y: 80))
        #expect(bottomRight.horizontalStart == CGPoint(x: 0, y: 80))
        #expect(bottomRight.horizontalEnd == CGPoint(x: 100, y: 80))
    }
}
