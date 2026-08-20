// SPDX-License-Identifier: MIT OR Apache-2.0

import SwiftUI
import UIKit

struct ZappSparkChartSelection {
    let primary: String
    let secondary: String
    let accessibilityDescription: String
}

struct ZappCrosshairGuides: Equatable {
    let verticalStart: CGPoint
    let verticalEnd: CGPoint
    let horizontalStart: CGPoint
    let horizontalEnd: CGPoint
}

/// Guides extend only toward their readout axes: left for value and down for date.
func crosshairGuides(selectedPoint: CGPoint, size: CGSize) -> ZappCrosshairGuides {
    ZappCrosshairGuides(
        verticalStart: selectedPoint,
        verticalEnd: CGPoint(x: selectedPoint.x, y: size.height),
        horizontalStart: CGPoint(x: 0, y: selectedPoint.y),
        horizontalEnd: selectedPoint
    )
}

func nearestChartPointIndex(points: [ZappChartPoint], x: CGFloat, width: CGFloat) -> Int {
    guard let first = points.first, let last = points.last else { return 0 }
    let range = last.timestamp.timeIntervalSince1970 - first.timestamp.timeIntervalSince1970
    guard range > 0 else { return 0 }
    let target = first.timestamp.timeIntervalSince1970 + min(max(x, 0), width) / max(width, 1) * range
    var low = 0
    var high = points.count - 1

    while low <= high {
        let middle = (low + high) / 2
        let value = points[middle].timestamp.timeIntervalSince1970
        if value < target {
            low = middle + 1
        } else if value > target {
            high = middle - 1
        } else {
            return middle
        }
    }

    guard low > 0 else { return 0 }
    guard low < points.count else { return points.count - 1 }
    let before = low - 1
    let beforeDistance = abs(points[before].timestamp.timeIntervalSince1970 - target)
    let afterDistance = abs(points[low].timestamp.timeIntervalSince1970 - target)
    return beforeDistance <= afterDistance ? before : low
}

struct ZappSparkChart: View {
    @Environment(\.colorScheme)
    private var colorScheme
    @State private var selectedPointIndex: Int?
    @State private var haptics = ZappHaptics.SelectionTicker()

    let points: [ZappChartPoint]
    let accessibilitySummary: String
    let selectionFormatter: (ZappChartPoint) -> ZappSparkChartSelection

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                drawSparkline(context: &context, size: size)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        selectNearestPoint(x: gesture.location.x, width: geometry.size.width)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("\(accessibilitySummary). \(String(localizable: .zappPayChartScrubHint))")
            .accessibilityValue(selectedAccessibilityValue)
            .accessibilityAdjustableAction { direction in
                adjustSelection(direction: direction)
            }
        }
        .frame(height: 140)
        .onChange(of: points) { _ in selectedPointIndex = nil }
    }

    private func drawSparkline(context: inout GraphicsContext, size: CGSize) {
        let lineWidth = 2.0
        let coordinates = chartCoordinates(points: points, size: size, lineWidth: lineWidth)
        guard let first = coordinates.first else { return }

        var line = Path()
        line.move(to: first)
        coordinates.dropFirst().forEach { line.addLine(to: $0) }

        var area = line
        area.addLine(to: CGPoint(x: coordinates.last?.x ?? size.width, y: size.height))
        area.addLine(to: CGPoint(x: first.x, y: size.height))
        area.closeSubpath()

        let accent = ZappColors.accent.color(colorScheme)
        context.fill(
            area,
            with: .linearGradient(
                Gradient(colors: [accent.opacity(0.24), accent.opacity(0.02)]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )
        context.stroke(line, with: .color(accent), lineWidth: lineWidth)

        guard let selectedPointIndex,
            let selectedPoint = points[safe: selectedPointIndex],
            let selectedCoordinate = coordinates[safe: selectedPointIndex] else { return }
        drawCrosshair(selectedCoordinate, context: &context, size: size, accent: accent)
        drawReadouts(
            selectionFormatter(selectedPoint),
            selectedCoordinate: selectedCoordinate,
            context: &context,
            size: size
        )
    }

    private func drawCrosshair(
        _ selectedCoordinate: CGPoint,
        context: inout GraphicsContext,
        size: CGSize,
        accent: Color
    ) {
        let guides = crosshairGuides(selectedPoint: selectedCoordinate, size: size)
        let guideStyle = StrokeStyle(lineWidth: 1, dash: [4, 4])
        context.stroke(
            Path { path in
                path.move(to: guides.verticalStart)
                path.addLine(to: guides.verticalEnd)
            },
            with: .color(accent.opacity(0.5)),
            style: guideStyle
        )
        context.stroke(
            Path { path in
                path.move(to: guides.horizontalStart)
                path.addLine(to: guides.horizontalEnd)
            },
            with: .color(accent.opacity(0.5)),
            style: guideStyle
        )
        context.fill(
            Path(CGRect(x: selectedCoordinate.x - 5, y: selectedCoordinate.y - 5, width: 10, height: 10)),
            with: .color(ZappColors.bg.color(colorScheme))
        )
        context.fill(
            Path(CGRect(x: selectedCoordinate.x - 3, y: selectedCoordinate.y - 3, width: 6, height: 6)),
            with: .color(accent)
        )
    }

    private func drawReadouts(
        _ selection: ZappSparkChartSelection,
        selectedCoordinate: CGPoint,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let primary = context.resolve(
            Text(selection.primary)
                .font(.custom(FontFamily.RobotoMono.medium.name, size: 12))
                .foregroundColor(ZappColors.accent.color(colorScheme))
        )
        let secondary = context.resolve(
            Text(selection.secondary)
                .font(.custom(FontFamily.Inter.bold.name, size: 10))
                .foregroundColor(ZappColors.textMuted.color(colorScheme))
        )
        let primarySize = primary.measure(in: size)
        let secondarySize = secondary.measure(in: size)
        let inset = 4.0
        let gap = 4.0
        let primaryY = min(max(selectedCoordinate.y - primarySize.height - gap, 0), max(size.height - primarySize.height, 0))
        let proposedSecondaryX = selectedCoordinate.x + gap + secondarySize.width + inset <= size.width
            ? selectedCoordinate.x + gap
            : selectedCoordinate.x - gap - secondarySize.width
        let secondaryX = min(max(proposedSecondaryX, inset), max(size.width - secondarySize.width - inset, inset))
        let secondaryY = size.height - secondarySize.height - inset
        context.draw(primary, at: CGPoint(x: inset, y: primaryY), anchor: .topLeading)
        context.draw(secondary, at: CGPoint(x: secondaryX, y: secondaryY), anchor: .topLeading)
    }

    private func chartCoordinates(points: [ZappChartPoint], size: CGSize, lineWidth: CGFloat) -> [CGPoint] {
        guard let firstDate = points.first?.timestamp.timeIntervalSince1970,
            let lastDate = points.last?.timestamp.timeIntervalSince1970 else { return [] }
        let values = points.map(\.value)
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        let dateRange = max(lastDate - firstDate, 1)
        let valueRange = maximum - minimum
        let plotHeight = max(size.height - lineWidth * 2, 1)
        return points.map { point in
            let fraction = valueRange > 0 ? (point.value - minimum) / valueRange : 0.5
            return CGPoint(
                x: (point.timestamp.timeIntervalSince1970 - firstDate) / dateRange * size.width,
                y: lineWidth + (1 - fraction) * plotHeight
            )
        }
    }

    private func selectNearestPoint(x: CGFloat, width: CGFloat) {
        let nextIndex = nearestChartPointIndex(points: points, x: x, width: width)
        guard selectedPointIndex != nextIndex else { return }
        selectedPointIndex = nextIndex
        haptics.tick()
    }

    private func adjustSelection(direction: AccessibilityAdjustmentDirection) {
        guard !points.isEmpty else { return }
        guard let current = selectedPointIndex else {
            selectedPointIndex = direction == .decrement ? points.count - 1 : 0
            haptics.tick()
            return
        }
        let next: Int
        switch direction {
        case .increment:
            next = min(current + 1, points.count - 1)
        case .decrement:
            next = max(current - 1, 0)
        @unknown default:
            return
        }
        guard selectedPointIndex != next else { return }
        selectedPointIndex = next
        haptics.tick()
    }

    private var selectedAccessibilityValue: String {
        guard let selectedPointIndex, let point = points[safe: selectedPointIndex] else { return "" }
        return selectionFormatter(point).accessibilityDescription
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
