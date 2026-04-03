// LoopFollow
// BGChartView.swift

import Charts
import SwiftUI
import WatchKit

struct BGChartView: View {
    let bgHistory: [BGReading]
    let loopStatus: LoopStatus?
    let treatments: [Treatment]
    let tempTargetEntries: [TempTargetEntry]
    let overrideEntries: [OverrideEntry]
    let config: WatchConfig
    @Binding var timeOffset: Double
    @State private var lastHapticOffset: Double = 0
    @State private var zoomHours: Double = 3
    @AppStorage("showTreatments") private var showTreatments: Bool = false

    // timeOffset is in units of 5 minutes (1 BG reading), snapped to integers
    private var snappedOffset: Double {
        timeOffset.rounded()
    }

    private var visibleStart: Date {
        Date().addingTimeInterval(-zoomHours * 3600 + snappedOffset * 300)
    }

    private var visibleEnd: Date {
        Date().addingTimeInterval(snappedOffset * 300)
    }

    private var yDomain: ClosedRange<Double> {
        if config.units == "mmol/L" {
            return 0 ... 16.7
        }
        return 0 ... 300
    }

    private func convertBG(_ mgdl: Double) -> Double {
        config.units == "mmol/L" ? mgdl * 0.0555 : mgdl
    }

    /// Find the closest BG value at a given timestamp, offset slightly above for treatment dots
    private func bgValueAbove(timestamp: Date) -> Double {
        let closest = bgHistory.min(by: {
            abs($0.timestamp.timeIntervalSince(timestamp)) < abs($1.timestamp.timeIntervalSince(timestamp))
        })
        let baseBG: Double
        if let closest = closest, abs(closest.timestamp.timeIntervalSince(timestamp)) < 600 {
            baseBG = Double(closest.bgValue)
        } else {
            baseBG = 150
        }
        // Offset above by ~15 mg/dL so dots sit above the BG point
        return convertBG(baseBG + 15)
    }

    var body: some View {
        Chart {
            if showTreatments {
                // Override shading (green)
                ForEach(overrideEntries) { entry in
                    RectangleMark(
                        xStart: .value("Start", entry.startDate),
                        xEnd: .value("End", entry.endDate),
                        yStart: .value("Low", convertBG(0)),
                        yEnd: .value("High", convertBG(300))
                    )
                    .foregroundStyle(.green.opacity(0.12))
                }

                // Temp target shading (purple)
                ForEach(tempTargetEntries) { entry in
                    RectangleMark(
                        xStart: .value("Start", entry.startDate),
                        xEnd: .value("End", entry.endDate),
                        yStart: .value("Low", convertBG(entry.targetBottom)),
                        yEnd: .value("High", convertBG(entry.targetTop))
                    )
                    .foregroundStyle(.purple.opacity(0.2))
                }
            }

            // Threshold lines
            RuleMark(y: .value("Low", convertBG(config.lowLine)))
                .foregroundStyle(.red.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
            RuleMark(y: .value("High", convertBG(config.highLine)))
                .foregroundStyle(.yellow.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 3]))

            // BG history points
            ForEach(bgHistory, id: \.timestamp) { reading in
                PointMark(
                    x: .value("Time", reading.timestamp),
                    y: .value("BG", convertBG(Double(reading.bgValue)))
                )
                .symbolSize(12)
                .foregroundStyle(pointColor(bgValue: reading.bgValue))
            }

            // Prediction lines — detect OpenAPS by checking for populated prediction arrays
            if let status = loopStatus {
                let hasOpenAPSPredictions = status.ztPredictions != nil || status.iobPredictions != nil ||
                    status.cobPredictions != nil || status.uamPredictions != nil
                if status.isOpenAPS || hasOpenAPSPredictions {
                    predictionMarks(values: status.ztPredictions, start: status.predictionStart, color: Color(red: 0.443, green: 0.380, blue: 0.937), series: "ZT")
                    predictionMarks(values: status.iobPredictions, start: status.predictionStart, color: Color(red: 0.118, green: 0.588, blue: 0.988), series: "IOB")
                    predictionMarks(values: status.cobPredictions, start: status.predictionStart, color: Color(red: 1.0, green: 0.757, blue: 0.271), series: "COB")
                    predictionMarks(values: status.uamPredictions, start: status.predictionStart, color: Color(red: 1.0, green: 0.518, blue: 0.271), series: "UAM")
                } else {
                    predictionMarks(values: status.predictions, start: status.predictionStart, color: .purple, series: "Pred")
                }
            }

            if showTreatments {
                // Bolus dots — blue upside-down triangles, offset above BG
                ForEach(treatments.filter { $0.type == .bolus || $0.type == .smb }) { treatment in
                    PointMark(
                        x: .value("Time", treatment.timestamp),
                        y: .value("BG", bgValueAbove(timestamp: treatment.timestamp))
                    )
                    .symbol {
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 6))
                            .foregroundColor(.blue)
                    }
                    .symbolSize(30)
                    .foregroundStyle(.blue)
                    .annotation(position: .top, spacing: 1) {
                        Text(String(format: "%.1fU", treatment.value))
                            .font(.system(size: 7, weight: .medium))
                            .foregroundColor(.white)
                    }
                }

                // Carb dots — yellow circles, offset above BG
                ForEach(treatments.filter { $0.type == .carbs }) { treatment in
                    PointMark(
                        x: .value("Time", treatment.timestamp),
                        y: .value("BG", bgValueAbove(timestamp: treatment.timestamp))
                    )
                    .symbol(.circle)
                    .symbolSize(30)
                    .foregroundStyle(.yellow)
                    .annotation(position: .top, spacing: 1) {
                        Text("\(Int(treatment.value))g")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: visibleStart ... visibleEnd)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                    .font(.system(size: 8))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 100, 200, 300].map { convertBG(Double($0)) }) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(config.units == "mmol/L" ? String(format: "%.0f", v) : String(format: "%.0f", v))
                            .font(.system(size: 7))
                    }
                }
            }
        }
        .focusable()
        .digitalCrownRotation($timeOffset, from: -300, through: 12, by: 1, sensitivity: .medium, isHapticFeedbackEnabled: false)
        .onChange(of: timeOffset) { newValue in
            let snapped = newValue.rounded()
            if snapped != lastHapticOffset {
                lastHapticOffset = snapped
                timeOffset = snapped
                WKInterfaceDevice.current().play(.click)
            }
        }
        .onTapGesture(count: 5) {
            showTreatments.toggle()
            WKInterfaceDevice.current().play(.click)
        }
        .onTapGesture(count: 3) {
            // Triple-tap: zoom out (reverse cycle)
            switch zoomHours {
            case 6: zoomHours = 0.25
            case 0.25: zoomHours = 0.5
            case 0.5: zoomHours = 1
            case 1: zoomHours = 2
            case 2: zoomHours = 3
            default: zoomHours = 6
            }
        }
        .onTapGesture(count: 2) {
            // Double-tap: zoom in cycle 6h→3h→2h→1h→30m→15m→6h
            switch zoomHours {
            case 6: zoomHours = 3
            case 3: zoomHours = 2
            case 2: zoomHours = 1
            case 1: zoomHours = 0.5
            case 0.5: zoomHours = 0.25
            default: zoomHours = 6
            }
        }
    }

    private func pointColor(bgValue: Int) -> Color {
        let bg = Double(bgValue)
        if bg <= config.lowLine { return .red }
        if bg >= config.highLine { return .yellow }
        return .green
    }

    @ChartContentBuilder
    private func predictionMarks(values: [Double]?, start: Date?, color: Color, series: String) -> some ChartContent {
        if let values = values, let start = start, !values.isEmpty {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                LineMark(
                    x: .value("Time", start.addingTimeInterval(Double(index) * 300)),
                    y: .value("BG", convertBG(value)),
                    series: .value("Series", series)
                )
                .foregroundStyle(color.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                .interpolationMethod(.catmullRom)
            }
        }
    }
}
