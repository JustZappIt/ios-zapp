//
//  ZappSparkChart.swift
//  Zapp
//
//  Zapp fork: iOS port of android-zapp's `SparkChart` - a stroked line over a
//  vertical gradient fill. No axes, no ticks; a visual summary meant to sit
//  inside a card alongside a numeric label. Auto-scales both axes to fit.
//

import SwiftUI

struct ZappSparkChartData: Equatable {
    struct Point: Equatable {
        let x: Double
        let y: Double
    }

    let points: [Point]

    var isRenderable: Bool { points.count >= 2 }
}

struct ZappSparkChart: View {
    @Environment(\.colorScheme) private var colorScheme

    let data: ZappSparkChartData
    var height: CGFloat = 140
    var strokeWidth: CGFloat = 2

    var body: some View {
        if data.isRenderable {
            Canvas { context, size in
                let xValues = data.points.map(\.x)
                let yValues = data.points.map(\.y)
                guard
                    let xMin = xValues.min(), let xMax = xValues.max(),
                    let yMin = yValues.min(), let yMax = yValues.max()
                else { return }

                let xRange = (xMax - xMin) > 0 ? (xMax - xMin) : 1
                let yRange = (yMax - yMin) > 0 ? (yMax - yMin) : 1

                let topPadding = strokeWidth
                let availableHeight = size.height - topPadding * 2

                let offsets: [CGPoint] = data.points.map { point in
                    CGPoint(
                        x: (point.x - xMin) / xRange * size.width,
                        y: topPadding + (yMax - point.y) / yRange * availableHeight
                    )
                }

                var linePath = Path()
                linePath.move(to: offsets[0])
                for offset in offsets.dropFirst() {
                    linePath.addLine(to: offset)
                }

                var fillPath = linePath
                fillPath.addLine(to: CGPoint(x: offsets[offsets.count - 1].x, y: size.height))
                fillPath.addLine(to: CGPoint(x: offsets[0].x, y: size.height))
                fillPath.closeSubpath()

                let accent = ZappColor.accent(colorScheme)
                context.fill(
                    fillPath,
                    with: .linearGradient(
                        Gradient(colors: [accent.opacity(0.24), .clear]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
                context.stroke(
                    linePath,
                    with: .color(accent),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
            }
            .frame(height: height)
        }
    }
}
