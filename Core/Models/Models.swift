import Foundation

// MARK: - Sleep

public enum SleepStage: String, Codable, CaseIterable, Sendable {
    case awake
    case light
    case deep
    case rem
    case unknown

    /// Maps Google Health API Enums (uppercase) and Fitbit legacy values.
    public init(apiValue: String) {
        switch apiValue.uppercased() {
        case "AWAKE", "WAKE", "RESTLESS": self = .awake
        case "LIGHT", "ASLEEP": self = .light
        case "DEEP": self = .deep
        case "REM": self = .rem
        default: self = .unknown
        }
    }

    public var isAsleep: Bool {
        self == .light || self == .deep || self == .rem
    }
}

public struct StageSpan: Codable, Hashable, Sendable {
    public var stage: SleepStage
    public var start: Date
    public var end: Date

    public init(stage: SleepStage, start: Date, end: Date) {
        self.stage = stage
        self.start = start
        self.end = end
    }

    public var minutes: Double {
        max(0, end.timeIntervalSince(start) / 60)
    }
}

public struct SleepSession: Codable, Hashable, Sendable {
    public var id: String
    public var start: Date
    public var end: Date
    public var minutesAsleep: Double
    public var minutesAwake: Double
    public var stages: [StageSpan]
    public var isMainSleep: Bool

    public init(
        id: String,
        start: Date,
        end: Date,
        minutesAsleep: Double,
        minutesAwake: Double,
        stages: [StageSpan] = [],
        isMainSleep: Bool = true
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.minutesAsleep = minutesAsleep
        self.minutesAwake = minutesAwake
        self.stages = stages
        self.isMainSleep = isMainSleep
    }

    public var minutesInBed: Double {
        max(0, end.timeIntervalSince(start) / 60)
    }

    /// Sleep efficiency in percent (sleep time / time in bed).
    public var efficiency: Double? {
        guard minutesInBed > 0 else { return nil }
        return min(100, minutesAsleep / minutesInBed * 100)
    }

    public func minutes(in stage: SleepStage) -> Double {
        stages.filter { $0.stage == stage }.reduce(0) { $0 + $1.minutes }
    }

    public var stageMinutes: [SleepStage: Double] {
        var result: [SleepStage: Double] = [:]
        for span in stages {
            result[span.stage, default: 0] += span.minutes
        }
        return result
    }
}

// MARK: - Heart Rate

public struct HRSample: Codable, Hashable, Sendable {
    /// Timestamp (minute resolution after downsampling)
    public var t: Date
    public var bpm: Double

    public init(t: Date, bpm: Double) {
        self.t = t
        self.bpm = bpm
    }
}

// MARK: - Workouts

public struct Workout: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var start: Date
    public var end: Date
    public var averageHR: Double?
    public var calories: Double?
    /// Calculated Strain value (0-21), set by StrainEngine.
    public var strain: Double?

    public init(
        id: String,
        name: String,
        start: Date,
        end: Date,
        averageHR: Double? = nil,
        calories: Double? = nil,
        strain: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.start = start
        self.end = end
        self.averageHR = averageHR
        self.calories = calories
        self.strain = strain
    }

    public var durationMinutes: Double {
        max(0, end.timeIntervalSince(start) / 60)
    }
}

// MARK: - Profile

public struct UserProfile: Codable, Sendable {
    public var displayName: String?
    /// Birthday as "yyyy-MM-dd", if provided by the API.
    public var birthday: String?

    public init(displayName: String? = nil, birthday: String? = nil) {
        self.displayName = displayName
        self.birthday = birthday
    }

    public var age: Int? {
        guard let birthday, let date = DayKey.date(from: birthday) else { return nil }
        let years = Calendar.current.dateComponents([.year], from: date, to: Date()).year
        return years
    }
}

// MARK: - Daily Record

/// All metrics for a calendar day. Nightly values (HRV, respiratory rate, SpO2,
/// temperature) are assigned to the day of waking up.
public struct DayRecord: Codable, Sendable {
    public var date: String // "yyyy-MM-dd"

    // Nightly recovery metrics
    public var hrvRmssd: Double?          // ms, nightly average
    public var restingHR: Double?         // beats/min
    public var respiratoryRate: Double?   // breaths/min
    public var spo2Avg: Double?           // %
    public var spo2Min: Double?           // %
    public var bodyTemp: Double?          // °C (skin/body temperature during night)

    // Activity
    public var steps: Int?
    public var sleepSessions: [SleepSession]
    public var workouts: [Workout]
    /// Intraday heart rate, downsampled to 1-minute resolution.
    public var hrSamples: [HRSample]

    public var syncedAt: Date?
    public var hrSyncedAt: Date?

    public init(date: String) {
        self.date = date
        self.sleepSessions = []
        self.workouts = []
        self.hrSamples = []
    }

    /// Main sleep = session flagged as such, otherwise the longest one.
    public var mainSleep: SleepSession? {
        if let flagged = sleepSessions.first(where: { $0.isMainSleep }) {
            return flagged
        }
        return sleepSessions.max(by: { $0.minutesAsleep < $1.minutesAsleep })
    }

    public var naps: [SleepSession] {
        guard let main = mainSleep else { return [] }
        return sleepSessions.filter { $0.id != main.id }
    }

    public var totalSleepMinutes: Double {
        sleepSessions.reduce(0) { $0 + $1.minutesAsleep }
    }

    // New: DayRecord.hrSyncedAt timestamp
    // A day is "complete" if we synced AFTER midnight of that day
    // → follow-up syncs only load today
    public static func isIntradayComplete(_ record: DayRecord?, dayKey: String) -> Bool {
        guard let record = record, let syncedAt = record.hrSyncedAt else { return false }
        guard let dayEnd = DayKey.date(from: dayKey)?.addingTimeInterval(24 * 3600) else { return false }
        return syncedAt >= dayEnd
    }
}

// MARK: - Journal

public enum JournalFactor: String, Codable, CaseIterable, Sendable {
    case alcohol, lateCaffeine, stress, sick, screenBeforeBed, exercised
}

public struct JournalEntry: Codable, Sendable {
    public var date: String
    public var factors: Set<JournalFactor>
    public var notes: String?

    public init(date: String, factors: Set<JournalFactor> = [], notes: String? = nil) {
        self.date = date
        self.factors = factors
        self.notes = notes
    }
}

public struct FactorInsight: Codable, Sendable {
    public let factor: JournalFactor
    public let avgWith: Double
    public let avgWithout: Double
    public var delta: Double { avgWith - avgWithout }
    
    public init(factor: JournalFactor, avgWith: Double, avgWithout: Double) {
        self.factor = factor
        self.avgWith = avgWith
        self.avgWithout = avgWithout
    }
}
