import Foundation

public struct HealthAlert: Sendable {
    public let title: String
    public let message: String
}

public enum BandState: String, Sendable {
    case inRange
    case above
    case below
    case noData
    case calibrating
}

public enum HealthMetricKind: String, CaseIterable, Sendable {
    case restingHR
    case hrv
    case respiratoryRate
    case spo2
    case bodyTemp

    public var label: String {
        switch self {
        case .restingHR: return "Resting HR"
        case .hrv: return "HRV"
        case .respiratoryRate: return "Respiratory Rate"
        case .spo2: return "SpO₂"
        case .bodyTemp: return "Skin Temperature"
        }
    }

    public var unit: String {
        switch self {
        case .restingHR: return "S/min"
        case .hrv: return "ms"
        case .respiratoryRate: return "/min"
        case .spo2: return "%"
        case .bodyTemp: return "°C"
        }
    }

    public func formatted(_ value: Double) -> String {
        switch self {
        case .restingHR, .hrv: return String(format: "%.0f", value)
        case .respiratoryRate, .spo2: return String(format: "%.1f", value)
        case .bodyTemp: return String(format: "%.2f", value)
        }
    }

    /// Minimum half bandwidth so tight baselines don't become overly sensitive.
    var minimumHalfWidth: Double {
        switch self {
        case .restingHR: return 3
        case .hrv: return 10
        case .respiratoryRate: return 0.8
        case .spo2: return 1.5
        case .bodyTemp: return 0.4
        }
    }
}

public struct HealthMetricStatus: Sendable {
    public let kind: HealthMetricKind
    public let value: Double?
    public let baseline: Baseline?
    public let lowerBound: Double?
    public let upperBound: Double?
    public let state: BandState
}

/// Whoop-like Health Monitor: Each night metric is checked against the personal
/// baseline band (mean ± 1.65 SD).
public enum HealthMonitor {
    public static func evaluate(today: DayRecord, history: [DayRecord]) -> [HealthMetricStatus] {
        HealthMetricKind.allCases.map { kind in
            let value = value(kind, today)
            let values = history.compactMap { self.value(kind, $0) }.suffix(30)
            let baseline = Stats.baseline(Array(values))

            guard let value else {
                return HealthMetricStatus(kind: kind, value: nil, baseline: baseline, lowerBound: nil, upperBound: nil, state: .noData)
            }
            guard let baseline, baseline.isReliable else {
                return HealthMetricStatus(kind: kind, value: value, baseline: baseline, lowerBound: nil, upperBound: nil, state: .calibrating)
            }

            let halfWidth = max(1.65 * baseline.sd, kind.minimumHalfWidth)
            var lower: Double? = baseline.mean - halfWidth
            var upper: Double? = baseline.mean + halfWidth

            // SpO₂: only critical downwards, hard lower limit 90 %.
            if kind == .spo2 {
                lower = max(90, baseline.mean - halfWidth)
                upper = nil
            }

            let state: BandState
            if let lower, value < lower {
                state = .below
            } else if let upper, value > upper {
                state = .above
            } else {
                state = .inRange
            }

            return HealthMetricStatus(
                kind: kind,
                value: value,
                baseline: baseline,
                lowerBound: lower,
                upperBound: upper,
                state: state
            )
        }
    }

    private static func value(_ kind: HealthMetricKind, _ record: DayRecord) -> Double? {
        switch kind {
        case .restingHR: return record.restingHR
        case .hrv: return record.hrvRmssd
        case .respiratoryRate: return record.respiratoryRate
        case .spo2: return record.spo2Avg
        case .bodyTemp: return record.bodyTemp
        }
    }

    // Health Monitor alert: fires if 2+ vitals abnormal today OR same vital 2+ days running
    public static func alert(records: [DayRecord], lookback: Int = 3) -> HealthAlert? {
        let sortedRecords = records.sorted { $0.date < $1.date }
        guard let _ = sortedRecords.last else { return nil }
        
        var recentEvals: [[HealthMetricStatus]] = []
        let recentRecords = Array(sortedRecords.suffix(max(2, lookback)))
        let baseCount = sortedRecords.count - recentRecords.count
        
        for (i, record) in recentRecords.enumerated() {
            let historyBefore = Array(sortedRecords.prefix(baseCount + i))
            recentEvals.append(evaluate(today: record, history: historyBefore))
        }
        
        guard let todayEval = recentEvals.last else { return nil }
        let todayAbnormal = todayEval.filter { $0.state == .below || $0.state == .above }
        
        if todayAbnormal.count >= 2 {
            let names = todayAbnormal.map { $0.kind.label }.joined(separator: ", ")
            return HealthAlert(
                title: "Multiple Vitals Abnormal",
                message: "Your \(names) are outside normal ranges today."
            )
        }
        
        if recentEvals.count >= 2 {
            let yesterdayEval = recentEvals[recentEvals.count - 2]
            let yesterdayAbnormalKinds = Set(yesterdayEval.filter { $0.state == .below || $0.state == .above }.map { $0.kind })
            let todayAbnormalKinds = Set(todayAbnormal.map { $0.kind })
            
            let consecutiveAbnormal = yesterdayAbnormalKinds.intersection(todayAbnormalKinds)
            if let kind = consecutiveAbnormal.first {
                return HealthAlert(
                    title: "Trend Alert: \(kind.label)",
                    message: "Your \(kind.label) has been abnormal for multiple days running."
                )
            }
        }
        
        return nil
    }
}
