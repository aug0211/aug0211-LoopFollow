// LoopFollow
// Chart.swift

import Charts
import Foundation

final class OverrideFillFormatter: FillFormatter {
    func getFillLinePosition(dataSet: Charts.LineChartDataSetProtocol, dataProvider _: Charts.LineChartDataProvider) -> CGFloat {
        return CGFloat(dataSet.entryForIndex(0)!.y)
        // return 375
    }
}

final class basalFillFormatter: FillFormatter {
    func getFillLinePosition(dataSet _: Charts.LineChartDataSetProtocol, dataProvider _: Charts.LineChartDataProvider) -> CGFloat {
        return 0
    }
}

final class ChartXValueFormatter: AxisValueFormatter {
    func stringForValue(_ value: Double, axis _: AxisBase?) -> String {
        let dateFormatter = DateFormatter()
        // let timezoneOffset = TimeZone.current.secondsFromGMT()
        // let epochTimezoneOffset = value + Double(timezoneOffset)
        if dateTimeUtils.is24Hour() {
            dateFormatter.setLocalizedDateFormatFromTemplate("HH:mm")
        } else {
            dateFormatter.setLocalizedDateFormatFromTemplate("hh:mm")
        }

        // let date = Date(timeIntervalSince1970: epochTimezoneOffset)
        let date = Date(timeIntervalSince1970: value)
        let formattedDate = dateFormatter.string(from: date)

        return formattedDate
    }
}

final class ChartYDataValueFormatter: ValueFormatter {
    func stringForValue(_: Double, entry: ChartDataEntry, dataSetIndex _: Int, viewPortHandler _: ViewPortHandler?) -> String {
        if entry.data != nil {
            return entry.data as? String ?? ""
        } else {
            return ""
        }
    }
}

final class ChartYOverrideValueFormatter: ValueFormatter {
    func stringForValue(_: Double, entry: ChartDataEntry, dataSetIndex _: Int, viewPortHandler _: ViewPortHandler?) -> String {
        if entry.data != nil {
            return entry.data as? String ?? ""
        } else {
            return ""
        }
    }
}

final class ChartYMMOLValueFormatter: AxisValueFormatter {
    func stringForValue(_ value: Double, axis _: AxisBase?) -> String {
        return Localizer.toDisplayUnits(String(value))
    }
}

final class OnlyValueFormatter: ValueFormatter {
    func stringForValue(_ value: Double, entry: ChartDataEntry, dataSetIndex: Int, viewPortHandler: ViewPortHandler?) -> String {
        // Show only the value, not the timestamp
        return String(format: "%g", value)
    }
}

final class EntryAmountValueFormatter: ValueFormatter {
    var isBolus: Bool = false
    init(isBolus: Bool = false) {
        self.isBolus = isBolus
    }
    func stringForValue(_ value: Double, entry: ChartDataEntry, dataSetIndex: Int, viewPortHandler: ViewPortHandler?) -> String {
        if let dict = entry.data as? [String: Any], let amount = dict["amount"] as? Double {
            if isBolus {
                // Drop leading and trailing zeros for bolus
                var str = String(format: "%.2f", amount)
                // Remove trailing zeros and decimal point if needed
                str = str.replacingOccurrences(of: "\\.0+$", with: "", options: .regularExpression)
                str = str.replacingOccurrences(of: "(\\.[1-9]*)0+$", with: "$1", options: .regularExpression)
                if str.hasPrefix("0.") {
                    return String(str.dropFirst(1))
                } else if str.hasPrefix("-0.") {
                    return "-" + String(str.dropFirst(2))
                }
                return str
            } else {
                return String(format: "%g", amount)
            }
        }
        return ""
    }
}

class PillMarker: MarkerImage {
    private(set) var color: UIColor
    private(set) var font: UIFont
    private(set) var textColor: UIColor
    private var labelText: String = ""
    private var attrs: [NSAttributedString.Key: AnyObject]!

    static let formatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.minute, .second]
        f.unitsStyle = .short
        return f
    }()

    init(color: UIColor, font: UIFont, textColor: UIColor) {
        self.color = color
        self.font = font
        self.textColor = textColor

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        attrs = [.font: font, .paragraphStyle: paragraphStyle, .foregroundColor: textColor, .baselineOffset: NSNumber(value: -4)]
        super.init()
    }

    override func draw(context: CGContext, point: CGPoint) {
        // custom padding around text
        let labelWidth = labelText.size(withAttributes: attrs).width + 10
        // if you modify labelHeigh you will have to tweak baselineOffset in attrs
        let labelHeight = labelText.size(withAttributes: attrs).height + 4

        // place pill above the marker, centered along x
        var rectangle = CGRect(x: point.x, y: point.y, width: labelWidth, height: labelHeight)
        rectangle.origin.x -= rectangle.width / 2.0
        var spacing: CGFloat = 20
        if point.y < 300 { spacing = -40 }

        rectangle.origin.y -= rectangle.height + spacing

        // rounded rect
        let clipPath = UIBezierPath(roundedRect: rectangle, cornerRadius: 6.0).cgPath
        context.addPath(clipPath)
        context.setFillColor(UIColor.secondarySystemBackground.cgColor)
        context.setStrokeColor(UIColor.label.cgColor)
        context.closePath()
        context.drawPath(using: .fillStroke)

        // add the text
        labelText.draw(with: rectangle, options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
    }

    override func refreshContent(entry: ChartDataEntry, highlight _: Highlight) {
        var valueString = ""
        var timeString = ""
        var prefix = ""
        
        if let dict = entry.data as? [String: Any] {
            // Handle dictionary-based data (tappable treatments: bolus, carbs, SMB)
            if let amount = dict["amount"] as? Double {
                if let isBolus = dict["isBolus"] as? Bool, isBolus {
                    var str = String(format: "%.2f", amount)
                    str = str.replacingOccurrences(of: "\\.0+$", with: "", options: .regularExpression)
                    str = str.replacingOccurrences(of: "(\\.[1-9]*)0+$", with: "$1", options: .regularExpression)
                    if str.hasPrefix("0.") {
                        valueString = String(str.dropFirst(1))
                    } else if str.hasPrefix("-0.") {
                        valueString = "-" + String(str.dropFirst(2))
                    } else {
                        valueString = str
                    }
                    valueString += " U"
                    if let isSMB = dict["isSMB"] as? Bool, isSMB {
                        prefix = "SMB"
                    } else {
                        prefix = "Bolus"
                    }
                } else {
                    prefix = "Carbs"
                    valueString = String(format: "%g", amount) + "g"
                }
            }
            if let time = dict["time"] as? String {
                timeString = time
            }
        } else if let dataString = entry.data as? String, !dataString.isEmpty {
            // For BG and other entries using a preformatted string, just show the string as-is
            labelText = dataString
            return
        } else {
            // Fallback for entries without data
            valueString = String(format: "%g", entry.y)
            let date = Date(timeIntervalSince1970: entry.x)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "h:mm a"
            timeString = dateFormatter.string(from: date)
            labelText = "\(valueString)\n\(timeString)"
            return
        }
        
        if !prefix.isEmpty {
            labelText = "\(timeString)\n\(prefix)\n\(valueString)"
        } else {
            labelText = "\(valueString)\n\(timeString)"
        }
    }

    private func customString(_ value: Double) -> String {
        let formattedString = PillMarker.formatter.string(from: TimeInterval(value))!
        // using this to convert the left axis values formatting, ie 2 min
        return "\(formattedString)"
    }
}

final class CarbsValueFormatter: ValueFormatter {
    let carbData: [MainViewController.carbGraphStruct]
    init(carbData: [MainViewController.carbGraphStruct]) {
        self.carbData = carbData
    }
    func stringForValue(_ value: Double, entry: ChartDataEntry, dataSetIndex: Int, viewPortHandler: ViewPortHandler?) -> String {
        if let match = carbData.first(where: { abs($0.date - entry.x) < 1 }) {
            return String(format: "%g", match.value)
        }
        return ""
    }
}

final class BolusValueFormatter: ValueFormatter {
    let bolusData: [MainViewController.bolusGraphStruct]
    init(bolusData: [MainViewController.bolusGraphStruct]) {
        self.bolusData = bolusData
    }
    func stringForValue(_ value: Double, entry: ChartDataEntry, dataSetIndex: Int, viewPortHandler: ViewPortHandler?) -> String {
        if let match = bolusData.first(where: { abs($0.date - entry.x) < 1 }) {
            return String(format: "%g", match.value)
        }
        return ""
    }
}

final class SMBValueFormatter: ValueFormatter {
    let smbData: [MainViewController.bolusGraphStruct]
    init(smbData: [MainViewController.bolusGraphStruct]) {
        self.smbData = smbData
    }
    func stringForValue(_ value: Double, entry: ChartDataEntry, dataSetIndex: Int, viewPortHandler: ViewPortHandler?) -> String {
        if let match = smbData.first(where: { abs($0.date - entry.x) < 1 }) {
            return String(format: "%g", match.value)
        }
        return ""
    }
}
