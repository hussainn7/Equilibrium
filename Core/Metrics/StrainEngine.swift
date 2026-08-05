import Foundation

public struct StrainConfig: Sendable {
    public var age: Int
    public var maxHROverride: Double?
    /// Time constant of the logarithmic 0–21 scale.
    public var tau: Double

    public init(age: Int = 30, maxHROverride: Double? = nil, tau: Double = 450) {
        self.age = age
        self.maxHROverride = maxHROverride
        self.tau = tau
    }

    /// Maximum heart rate: override or Tanaka formula (208 − 0.7 × age).
    public var maxHR: Double {
        maxHROverride ?? (208 - 0.7 * Double(age))
    }
}

public struct StrainResult: Sendable {
    /// Strain on the Whoop-like 0–21 scale.
    public let strain: Double
    public let rawLoad: Double
    /// Minutes per intensity zone (index 0 = very light … 5 = maximum).
    public let zoneMinutes: [Double]
    public let avgHR: Double?
    public let peakHR: Double?

    public static let empty = StrainResult(strain: 0, rawLoad: 0, zoneMinutes: Array(repeating: 0, count: 6), avgHR: nil, peakHR: nil)
}

/// Cardiovascular load according to the TRIMP principle:
/// Time in heart rate reserve zones is weighted, summed up, and
/// mapped logarithmically to 0–21 (like the Whoop strain scale, which becomes
/// increasingly harder to raise at the top).
public enum StrainEngine {
    /// Lower bounds of the zones as a fraction of heart rate reserve (Karvonen).
    public static let zoneLowerBounds: [Double] = [0.20, 0.30, 0.45, 0.60, 0.72, 0.85]
    public static let zoneWeights: [Double] = [0.5, 1.0, 2.5, 5.0, 8.0, 11.0]
    public static let zoneLabels: [String] = ["Very light", "Light", "Moderate", "Hard", "Very hard", "Maximum"]

    public static func strain(fromRaw raw: Double, tau: Double = 450) -> Double {
        guard raw > 0 else { return 0 }
        return 21 * (1 - exp(-raw / tau))
    }

    public static func zoneIndex(for fraction: Double) -> Int? {
        var index: Int?
        for (i, bound) in zoneLowerBounds.enumerated() where fraction >= bound {
            index = i
        }
        return index
    }

    /// Sums the weighted load over HR samples (minute resolution).
    public static func accumulate(
        samples: [HRSample],
        restingHR: Double,
        maxHR: Double
    ) -> (raw: Double, zones: [Double], avgHR: Double?, peakHR: Double?) {
        let emptyZones = Array(repeating: 0.0, count: zoneWeights.count)
        guard !samples.isEmpty, maxHR > restingHR + 20 else {
            return (0, emptyZones, nil, nil)
        }
        let sorted = samples.sorted { $0.t < $1.t }
        var raw = 0.0
        var zones = emptyZones
        var previous: Date?
        var sum = 0.0
        var peak = 0.0

        for sample in sorted {
            var dt = 1.0
            if let prev = previous {
                dt = Stats.clamp(sample.t.timeIntervalSince(prev) / 60, 0, 5)
            }
            previous = sample.t
            sum += sample.bpm
            peak = max(peak, sample.bpm)

            let fraction = (sample.bpm - restingHR) / (maxHR - restingHR)
            guard let zone = zoneIndex(for: fraction) else { continue }
            raw += zoneWeights[zone] * dt
            zones[zone] += dt
        }
        return (raw, zones, sum / Double(sorted.count), peak)
    }

    /// Daily strain from intraday HR; fallback via workout average heart rate
    /// and steps if no samples are available.
    public static func dayStrain(
        record: DayRecord,
        restingHR: Double?,
        config: StrainConfig = StrainConfig()
    ) -> StrainResult {
        let rhr = restingHR ?? 62
        let maxHR = config.maxHR

        if !record.hrSamples.isEmpty {
            let acc = accumulate(samples: record.hrSamples, restingHR: rhr, maxHR: maxHR)
            return StrainResult(
                strain: strain(fromRaw: acc.raw, tau: config.tau),
                rawLoad: acc.raw,
                zoneMinutes: acc.zones,
                avgHR: acc.avgHR,
                peakHR: acc.peakHR
            )
        }

        // Fallback without intraday data
        var raw = 0.0
        var zones = Array(repeating: 0.0, count: zoneWeights.count)
        for workout in record.workouts {
            guard let avgHR = workout.averageHR else { continue }
            let fraction = (avgHR - rhr) / (maxHR - rhr)
            guard let zone = zoneIndex(for: fraction) else { continue }
            raw += zoneWeights[zone] * workout.durationMinutes
            zones[zone] += workout.durationMinutes
        }
        if let steps = record.steps, steps > 0 {
            raw += Double(steps) / 1000 * 2.0
        }
        return StrainResult(
            strain: strain(fromRaw: raw, tau: config.tau),
            rawLoad: raw,
            zoneMinutes: zones,
            avgHR: nil,
            peakHR: nil
        )
    }

    /// Strain of a single workout (own 0–21 scale).
    public static func workoutStrain(
        workout: Workout,
        daySamples: [HRSample],
        restingHR: Double?,
        config: StrainConfig = StrainConfig()
    ) -> Double? {
        let rhr = restingHR ?? 62
        let slice = daySamples.filter { $0.t >= workout.start && $0.t <= workout.end }
        if slice.count >= 3 {
            let acc = accumulate(samples: slice, restingHR: rhr, maxHR: config.maxHR)
            return strain(fromRaw: acc.raw, tau: config.tau)
        }
        guard let avgHR = workout.averageHR else { return nil }
        let fraction = (avgHR - rhr) / (config.maxHR - rhr)
        guard let zone = zoneIndex(for: fraction) else { return 0 }
        let raw = zoneWeights[zone] * workout.durationMinutes
        return strain(fromRaw: raw, tau: config.tau)
    }
}
