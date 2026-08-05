import Foundation

public struct SyncProgress: Sendable {
    public let message: String
    public let fraction: Double

    public init(message: String, fraction: Double) {
        self.message = message
        self.fraction = fraction
    }
}

public struct SyncLogEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let metric: String
    public let detail: String
    public let isError: Bool

    public init(metric: String, detail: String, isError: Bool = false) {
        self.id = UUID()
        self.timestamp = Date()
        self.metric = metric
        self.detail = detail
        self.isError = isError
    }
}

public struct SyncOutcome: Sendable {
    public let updatedDays: [String: DayRecord]
    public let log: [SyncLogEntry]
    public let profile: UserProfile?
    public var hadErrors: Bool { log.contains { $0.isError } }

    public init(updatedDays: [String: DayRecord], log: [SyncLogEntry], profile: UserProfile?) {
        self.updatedDays = updatedDays
        self.log = log
        self.profile = profile
    }
}

/// Orchestrates all API fetches for a time window. Each metric is loaded isolated
/// — an error (e.g. an unavailable data type) doesn't block
/// the other metrics, but only lands in the sync log.
public final class SyncEngine: @unchecked Sendable {
    private let client: HealthAPIClient

    public init(client: HealthAPIClient) {
        self.client = client
    }

    public func sync(
        existingDays: [String: DayRecord],
        daysBack: Int,
        hrDaysBack: Int,
        progress: (@Sendable (SyncProgress) -> Void)? = nil
    ) async -> SyncOutcome {
        var days = existingDays
        var log: [SyncLogEntry] = []
        var profile: UserProfile?

        let todayKey = DayKey.today()
        let startKey = DayKey.addDays(todayKey, -(max(1, daysBack) - 1))
        guard let windowStart = DayKey.date(from: startKey) else {
            return SyncOutcome(updatedDays: days, log: [SyncLogEntry(metric: "Sync", detail: "Invalid time window", isError: true)], profile: nil)
        }
        let windowEnd = Date()
        let syncStamp = Date()

        func note(_ metric: String, _ detail: String, error: Bool = false) {
            log.append(SyncLogEntry(metric: metric, detail: detail, isError: error))
        }

        func update(_ key: String, _ mutate: (inout DayRecord) -> Void) {
            guard key >= startKey, key <= todayKey else { return }
            var record = days[key] ?? DayRecord(date: key)
            mutate(&record)
            record.syncedAt = syncStamp
            days[key] = record
        }

        let totalSteps = 10.0
        var currentStep = 0.0
        func report(_ message: String) {
            progress?(SyncProgress(message: message, fraction: min(1, currentStep / totalSteps)))
            currentStep += 1
        }

        // 1. Profil
        report("Loading profile…")
        do {
            profile = try await client.fetchProfile()
            note("Profile", "loaded")
        } catch {
            note("Profile", Self.describe(error), error: true)
        }

        // 2. Sleep sessions (assigned to wake-up day)
        report("Loading sleep…")
        do {
            let sessions = try await client.fetchSleepSessions(
                start: windowStart.addingTimeInterval(-12 * 3600),
                end: windowEnd
            )
            var byDay: [String: [SleepSession]] = [:]
            for session in sessions {
                byDay[DayKey.string(from: session.end), default: []].append(session)
            }
            for (key, list) in byDay {
                var sorted = list.sorted { $0.start < $1.start }
                if !sorted.contains(where: { $0.isMainSleep }),
                   let longest = sorted.indices.max(by: { sorted[$0].minutesAsleep < sorted[$1].minutesAsleep }) {
                    sorted[longest].isMainSleep = true
                }
                update(key) { $0.sleepSessions = sorted }
            }
            note("Sleep", "\(sessions.count) Sessions")
        } catch {
            note("Sleep", Self.describe(error), error: true)
        }

        // 3. HRV (nächtliche Samples → Mittelwert je Nacht)
        report("Loading HRV…")
        do {
            let samples = try await client.fetchSamples(
                type: "heart-rate-variability",
                payloadKey: "heartRateVariability",
                valueKeys: ["rmssd", "rmssdMilliseconds", "milliseconds", "dailyRmssd", "value"],
                start: windowStart.addingTimeInterval(-12 * 3600),
                end: windowEnd
            )
            let grouped = Self.groupByNight(samples)
            for (key, values) in grouped {
                update(key) { $0.hrvRmssd = Stats.mean(values) }
            }
            note("HRV", "\(samples.count) Samples, \(grouped.count) Nights")
        } catch {
            note("HRV", Self.describe(error), error: true)
        }

        // 4. Respiratory rate
        report("Loading respiratory rate…")
        do {
            let samples = try await client.fetchSamples(
                type: "respiratory-rate",
                payloadKey: "respiratoryRate",
                valueKeys: ["breathsPerMinute", "rate", "value", "fullSleepSummary"],
                start: windowStart.addingTimeInterval(-12 * 3600),
                end: windowEnd
            )
            let grouped = Self.groupByNight(samples)
            for (key, values) in grouped {
                update(key) { $0.respiratoryRate = Stats.mean(values) }
            }
            note("Respiratory rate", "\(grouped.count) Nights")
        } catch {
            note("Respiratory rate", Self.describe(error), error: true)
        }

        // 5. SpO2 (nächtlicher Durchschnitt + Minimum)
        report("Loading SpO₂…")
        do {
            let samples = try await client.fetchSamples(
                type: "oxygen-saturation",
                payloadKey: "oxygenSaturation",
                valueKeys: ["percentage", "averagePercentage", "value"],
                start: windowStart.addingTimeInterval(-12 * 3600),
                end: windowEnd
            )
            var byNight: [String: [Double]] = [:]
            for sample in samples {
                byNight[DayKey.nightKey(for: sample.time), default: []].append(sample.value)
            }
            for (key, values) in byNight where !values.isEmpty {
                update(key) {
                    $0.spo2Avg = Stats.mean(values)
                    $0.spo2Min = values.min()
                }
            }
            note("SpO₂", "\(byNight.count) Nights")
        } catch {
            note("SpO₂", Self.describe(error), error: true)
        }

        // 6. Temperatur (Haut/Körper, nächtlicher Wert)
        report("Loading temperature…")
        do {
            let samples = try await client.fetchSamples(
                type: "body-temperature",
                payloadKey: "bodyTemperature",
                valueKeys: ["celsius", "degreesCelsius", "temperature", "value", "nightlyRelative"],
                start: windowStart.addingTimeInterval(-12 * 3600),
                end: windowEnd
            )
            let grouped = Self.groupByNight(samples)
            for (key, values) in grouped {
                update(key) { $0.bodyTemp = Stats.mean(values) }
            }
            note("Temperature", "\(grouped.count) Nights")
        } catch {
            note("Temperature", Self.describe(error), error: true)
        }

        // 7. Resting HR (daily type; fallback later from night HR)
        report("Loading resting HR…")
        do {
            let values = try await client.fetchDailyValues(
                type: "resting-heart-rate",
                payloadKey: "restingHeartRate",
                valueKeys: ["beatsPerMinute", "bpm", "value"],
                start: windowStart,
                end: windowEnd
            )
            for (key, value) in values {
                update(key) { $0.restingHR = value }
            }
            note("Resting HR", "\(values.count) Days")
        } catch {
            note("Resting HR", "\(Self.describe(error)) – Fallback via night HR active", error: true)
        }

        // 8. Steps (interval samples → daily sum)
        report("Loading steps…")
        do {
            let samples = try await client.fetchSamples(
                type: "steps",
                payloadKey: "steps",
                valueKeys: ["count", "steps", "value"],
                start: windowStart,
                end: windowEnd,
                filterField: "interval.start_time"
            )
            var byDay: [String: Double] = [:]
            for sample in samples {
                byDay[DayKey.string(from: sample.time), default: 0] += sample.value
            }
            for (key, total) in byDay {
                update(key) { $0.steps = Int(total) }
            }
            note("Steps", "\(byDay.count) Days")
        } catch {
            note("Steps", Self.describe(error), error: true)
        }

        // 9. Intraday heart rate (Phase 2: parallelized)
        report("Loading heart rate (Phase 2)…")
        let hrOutcome = await syncIntradayHeartRate(
            existingDays: days,
            hrDaysBack: hrDaysBack,
            maxConcurrent: 4,
            progress: progress
        )
        days = hrOutcome.updatedDays
        log.append(contentsOf: hrOutcome.log)

        // Resting HR fallback: 5th percentile of night HR (00:00–08:00)
        for key in DayKey.keys(from: startKey, to: todayKey) {
            guard let record = days[key], record.restingHR == nil, !record.hrSamples.isEmpty,
                  let dayStart = DayKey.date(from: key) else { continue }
            let nightEnd = dayStart.addingTimeInterval(8 * 3600)
            let nightSamples = record.hrSamples.filter { $0.t < nightEnd }.map { $0.bpm }
            let basis = nightSamples.count >= 30 ? nightSamples : record.hrSamples.map { $0.bpm }
            if let p5 = Stats.percentile(basis, 0.05) {
                update(key) { $0.restingHR = p5 }
            }
        }

        // 10. Workouts
        report("Loading workouts…")
        do {
            let workouts = try await client.fetchExerciseSessions(start: windowStart, end: windowEnd)
            var byDay: [String: [Workout]] = [:]
            for workout in workouts {
                byDay[DayKey.string(from: workout.start), default: []].append(workout)
            }
            for (key, list) in byDay {
                update(key) { $0.workouts = list.sorted { $0.start < $1.start } }
            }
            note("Workouts", "\(workouts.count) Sessions")
        } catch {
            note("Workouts", Self.describe(error), error: true)
        }

        progress?(SyncProgress(message: "Done", fraction: 1))
        return SyncOutcome(updatedDays: days, log: log, profile: profile)
    }

    public func syncIntradayHeartRate(
        existingDays: [String: DayRecord],
        hrDaysBack: Int,
        maxConcurrent: Int = 4,
        progress: (@Sendable (SyncProgress) -> Void)? = nil
    ) async -> SyncOutcome {
        var days = existingDays
        var log: [SyncLogEntry] = []
        
        let todayKey = DayKey.today()
        let hrStartKey = DayKey.addDays(todayKey, -(max(1, hrDaysBack) - 1))
        
        var keysToLoad: [String] = []
        for key in DayKey.keys(from: hrStartKey, to: todayKey) {
            if DayRecord.isIntradayComplete(days[key], dayKey: key) {
                continue
            }
            keysToLoad.append(key)
        }
        
        if keysToLoad.isEmpty {
            return SyncOutcome(updatedDays: days, log: log, profile: nil)
        }
        
        let total = keysToLoad.count
        var completed = 0
        let syncStamp = Date()
        let windowEnd = Date()
        
        let client = self.client
        
        await withTaskGroup(of: (String, Result<[SamplePoint], Error>).self) { group in
            var index = 0
            
            // Queue initial batch
            for _ in 0..<maxConcurrent {
                if index < keysToLoad.count {
                    let key = keysToLoad[index]
                    index += 1
                    let dayStart = DayKey.date(from: key)!
                    let dayEnd = min(dayStart.addingTimeInterval(24 * 3600), windowEnd)
                    
                    group.addTask {
                        do {
                            let samples = try await client.fetchSamples(
                                type: "heart-rate",
                                payloadKey: "heartRate",
                                valueKeys: ["beatsPerMinute", "bpm", "value"],
                                start: dayStart,
                                end: dayEnd
                            )
                            return (key, .success(samples))
                        } catch {
                            return (key, .failure(error))
                        }
                    }
                }
            }
            
            // Process completed and queue next
            for await (key, result) in group {
                completed += 1
                progress?(SyncProgress(message: "HR loading (\(completed)/\(total) days)", fraction: Double(completed) / Double(total)))
                
                switch result {
                case .success(let samples):
                    var record = days[key] ?? DayRecord(date: key)
                    if !samples.isEmpty {
                        record.hrSamples = Self.downsampleToMinutes(samples)
                    }
                    record.hrSyncedAt = syncStamp
                    days[key] = record
                    
                case .failure(let error):
                    log.append(SyncLogEntry(metric: "Heart rate", detail: "\(key): \(Self.describe(error))", isError: true))
                }
                
                if index < keysToLoad.count {
                    let nextKey = keysToLoad[index]
                    index += 1
                    let dayStart = DayKey.date(from: nextKey)!
                    let dayEnd = min(dayStart.addingTimeInterval(24 * 3600), windowEnd)
                    
                    group.addTask {
                        do {
                            let samples = try await client.fetchSamples(
                                type: "heart-rate",
                                payloadKey: "heartRate",
                                valueKeys: ["beatsPerMinute", "bpm", "value"],
                                start: dayStart,
                                end: dayEnd
                            )
                            return (nextKey, .success(samples))
                        } catch {
                            return (nextKey, .failure(error))
                        }
                    }
                }
            }
        }
        
        let successCount = keysToLoad.count - log.count
        if successCount > 0 {
            log.append(SyncLogEntry(metric: "Heart rate", detail: "\(successCount) days intraday loaded in parallel"))
        }
        
        return SyncOutcome(updatedDays: days, log: log, profile: nil)
    }

    // MARK: - Helpers

    /// Groups samples by wake-up day (night assignment via +6h shift).
    public static func groupByNight(_ samples: [SamplePoint]) -> [String: [Double]] {
        var result: [String: [Double]] = [:]
        for sample in samples {
            result[DayKey.nightKey(for: sample.time), default: []].append(sample.value)
        }
        return result
    }

    /// Reduces raw samples (up to 5-second resolution) to minute averages.
    public static func downsampleToMinutes(_ samples: [SamplePoint]) -> [HRSample] {
        var buckets: [Date: (sum: Double, count: Int)] = [:]
        for sample in samples {
            let bucket = Date(timeIntervalSince1970: (sample.time.timeIntervalSince1970 / 60).rounded(.down) * 60)
            let existing = buckets[bucket] ?? (0, 0)
            buckets[bucket] = (existing.sum + sample.value, existing.count + 1)
        }
        return buckets
            .map { HRSample(t: $0.key, bpm: $0.value.sum / Double($0.value.count)) }
            .sorted { $0.t < $1.t }
    }

    static func describe(_ error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.localizedDescription
        }
        if let authError = error as? AuthError {
            return authError.localizedDescription
        }
        return error.localizedDescription
    }
}
