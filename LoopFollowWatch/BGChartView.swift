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
    @Binding var zoomHours: Double
    @AppStorage("showTreatments") private var showTreatments: Bool = false

    private var treatmentFontSize: CGFloat {
        switch zoomHours {
        case ...0.5: return 10
        case ...1: return 8
        default: return 6
        }
    }
    private var treatmentSymbolSize: CGFloat { CGFloat(30.0 * min(1.6, max(0.7, 2.0 / zoomHours))) }
    private var showTreatmentLabels: Bool { zoomHours <= 2 }
    @FocusState private var chartFocused: Bool

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

    private var centerTime: Date {
        visibleStart.addingTimeInterval(visibleEnd.timeIntervalSince(visibleStart) * 0.7)
    }

    // Pre-filtered data for visible window only (with small margin)
    private var visibleBG: [BGReading] {
        let margin: TimeInterval = 600 // 10-min margin
        let start = visibleStart.addingTimeInterval(-margin)
        let end = visibleEnd.addingTimeInterval(margin)
        return bgHistory.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    private var visibleTreatments: [Treatment] {
        let margin: TimeInterval = 600
        let start = visibleStart.addingTimeInterval(-margin)
        let end = visibleEnd.addingTimeInterval(margin)
        return treatments.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    private var visibleOverrides: [OverrideEntry] {
        return overrideEntries.filter { $0.endDate >= visibleStart && $0.startDate <= visibleEnd }
    }

    private var visibleTempTargets: [TempTargetEntry] {
        return tempTargetEntries.filter { $0.endDate >= visibleStart && $0.startDate <= visibleEnd }
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
        let closest = visibleBG.min(by: {
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

    /// Find the closest BG value at a given timestamp, offset higher for carb dots to clear bolus markers
    private func bgValueAboveCarb(timestamp: Date) -> Double {
        let closest = visibleBG.min(by: {
            abs($0.timestamp.timeIntervalSince(timestamp)) < abs($1.timestamp.timeIntervalSince(timestamp))
        })
        let baseBG: Double
        if let closest = closest, abs(closest.timestamp.timeIntervalSince(timestamp)) < 600 {
            baseBG = Double(closest.bgValue)
        } else {
            baseBG = 150
        }
        // Offset above by ~40 mg/dL so carbs clear bolus triangles + their text
        return convertBG(baseBG + 75)
    }

    var body: some View {
        Chart {
            if showTreatments {
                // Override ticker tape (purple band at bottom: 0-29 mg/dL)
                ForEach(visibleOverrides) { entry in
                    RectangleMark(
                        xStart: .value("Start", entry.startDate),
                        xEnd: .value("End", entry.endDate),
                        yStart: .value("Low", convertBG(0)),
                        yEnd: .value("High", convertBG(29))
                    )
                    .foregroundStyle(.purple.opacity(0.6))
                    .annotation(position: .overlay, alignment: .leading) {
                        Text(entry.name.isEmpty
                            ? (entry.percentage.map { String(format: "%.0f%%", $0) } ?? "Override")
                            : entry.name)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .padding(.leading, 2)
                    }
                }

                // Temp target ticker tape (green band: 31-60 mg/dL)
                ForEach(visibleTempTargets) { entry in
                    RectangleMark(
                        xStart: .value("Start", entry.startDate),
                        xEnd: .value("End", entry.endDate),
                        yStart: .value("Low", convertBG(31)),
                        yEnd: .value("High", convertBG(60))
                    )
                    .foregroundStyle(.green.opacity(0.6))
                    .annotation(position: .overlay, alignment: .leading) {
                        Text(entry.reason.isEmpty
                            ? String(format: "%.0f", entry.targetTop)
                            : entry.reason)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .padding(.leading, 2)
                    }
                }
            }

            // Midpoint inspection marker
            RuleMark(x: .value("Center", centerTime))
                .foregroundStyle(.white.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 0.5))

            // BG history — smooth line with gradient fill
            ForEach(visibleBG, id: \.timestamp) { reading in
                LineMark(
                    x: .value("Time", reading.timestamp),
                    y: .value("BG", convertBG(Double(reading.bgValue)))
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .foregroundStyle(pointColor(bgValue: reading.bgValue))

                AreaMark(
                    x: .value("Time", reading.timestamp),
                    y: .value("BG", convertBG(Double(reading.bgValue)))
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [pointColor(bgValue: reading.bgValue).opacity(0.45), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
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
                ForEach(visibleTreatments.filter { $0.type == .bolus || $0.type == .smb }) { treatment in
                    PointMark(
                        x: .value("Time", treatment.timestamp),
                        y: .value("BG", bgValueAbove(timestamp: treatment.timestamp))
                    )
                    .symbol {
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: treatmentFontSize * 0.6))
                            .foregroundColor(.blue)
                    }
                    .symbolSize(treatmentSymbolSize)
                    .foregroundStyle(.blue)
                    .annotation(position: .top, spacing: 1) {
                        if showTreatmentLabels {
                            Text(String(format: "%g", treatment.value))
                                .font(.system(size: treatmentFontSize, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                }

                // Carb dots — yellow circles, offset above BG
                ForEach(visibleTreatments.filter { $0.type == .carbs }) { treatment in
                    PointMark(
                        x: .value("Time", treatment.timestamp),
                        y: .value("BG", bgValueAboveCarb(timestamp: treatment.timestamp))
                    )
                    .symbol(.circle)
                    .symbolSize(treatmentSymbolSize)
                    .foregroundStyle(.yellow)
                    .annotation(position: .top, spacing: 1) {
                        if showTreatmentLabels {
                            Text("\(Int(treatment.value))")
                                .font(.system(size: treatmentFontSize, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: visibleStart ... visibleEnd)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour)) { _ in
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                    .font(.system(size: 8))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 100, 200, 300].map { convertBG(Double($0)) }) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(config.units == "mmol/L" ? String(format: "%.0f", v) : String(format: "%.0f", v))
                            .font(.system(size: 7))
                    }
                }
            }
        }
        .focusable()
        .focused($chartFocused)
        .digitalCrownRotation($timeOffset, from: -300, through: 12, by: 1, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: false)
        .onAppear { chartFocused = true }
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
        return bgDynamicColor(Double(bgValue))
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
