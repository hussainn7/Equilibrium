import Foundation
import PulseCore

// Self-Test-Runner: verifies the core logic without Xcode/iOS SDK.

var failures: [String] = []

func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ✓ \(message)")
    } else {
        print("  ✗ ERROR: \(message)")
        failures.append(message)
    }
}

func section(_ name: String) {
    print("\n— \(name)")
}

func jsonDict(_ raw: String) -> [String: Any] {
    guard let data = raw.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let dict = object as? [String: Any] else {
        failures.append("Fixture not parsable")
        return [:]
    }
    return dict
}

// MARK: PKCE (RFC-7636-Testvektor)

section("PKCE")
let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
check(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "SHA256 challenge matches RFC-7636 vector")
let freshPKCE = PKCE()
check(freshPKCE.verifier.count >= 43, "Random verifier has sufficient length")
check(freshPKCE.verifier != PKCE().verifier, "Verifiers are random")

// MARK: OAuth-Konfiguration

section("OAuth Configuration")
let config = GoogleOAuthConfig(clientID: "407408718192-abc123.apps.googleusercontent.com")
check(config.reversedClientScheme == "com.googleusercontent.apps.407408718192-abc123", "Reversed client scheme correct")
check(config.redirectURI == "com.googleusercontent.apps.407408718192-abc123:/oauth2redirect", "Redirect URI correct")
check(!GoogleOAuthConfig(clientID: "kaputt").isValid, "Invalid client ID is recognized")

let auth = GoogleAuth(usesKeychain: false)
if let url = auth.authorizationURL(config: config, pkce: pkce, state: "test-state") {
    let absolute = url.absoluteString
    check(absolute.hasPrefix("https://accounts.google.com/o/oauth2/v2/auth"), "Auth URL points to Google")
    check(absolute.contains("code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"), "Auth URL contains PKCE challenge")
    check(absolute.contains("googlehealth.sleep.readonly"), "Auth URL contains Health scopes")
    check(!absolute.contains("prompt="), "No prompt=consent (Google Health recommendation)")
} else {
    check(false, "Auth URL could not be built")
}
let callback = URL(string: "com.googleusercontent.apps.x:/oauth2redirect?state=test-state&code=4/abc")!
check(GoogleAuth.extractCode(from: callback, expectedState: "test-state") == "4/abc", "Code extraction from callback")
check(GoogleAuth.extractCode(from: callback, expectedState: "falsch") == nil, "State mismatch is rejected")
check(GoogleAuth.formEncode(["a": "b c", "x": "y+z"]) == "a=b%20c&x=y%2Bz", "Form encoding percent-encodes correctly")

// MARK: JSON-Extraktion (Google-Health-Formate)

section("JSON Extraction")
check(JSONExtract.snakeCase("heartRateVariability") == "heart_rate_variability", "camelCase → snake_case")

let hrPoint = jsonDict(#"""
{
  "dataSource": { "device": { "displayName": "Fitbit Air" }, "platform": "FITBIT", "recordingMethod": "DERIVED" },
  "heartRate": { "sampleTime": { "physicalTime": "2026-05-12T15:59:07Z" }, "beatsPerMinute": 72 }
}
"""#)
let hrPayload = (hrPoint["heartRate"] as? [String: Any]) ?? [:]
check(JSONExtract.firstDouble(in: hrPayload, keys: ["beatsPerMinute", "bpm"]) == 72, "Heart rate value extracted")
check(JSONExtract.firstDate(in: hrPayload, keys: ["physicalTime"]) != nil, "Sample time extracted (nested)")

let civil = JSONExtract.civilDateString(from: ["year": 2026, "month": 7, "day": 5])
check(civil == "2026-07-05", "CivilDate object → yyyy-MM-dd")

let sleepPoint = jsonDict(#"""
{
  "name": "users/me/dataTypes/sleep/dataPoints/abc",
  "sleep": {
    "type": "STAGES",
    "interval": { "startTime": "2026-07-16T22:45:00Z", "endTime": "2026-07-17T06:30:00Z" },
    "stages": [
      { "type": "LIGHT", "startTime": "2026-07-16T22:45:00Z", "endTime": "2026-07-17T00:10:00Z" },
      { "type": "DEEP", "startTime": "2026-07-17T00:10:00Z", "endTime": "2026-07-17T01:20:00Z" },
      { "type": "REM", "startTime": "2026-07-17T01:20:00Z", "endTime": "2026-07-17T02:00:00Z" },
      { "type": "AWAKE", "startTime": "2026-07-17T02:00:00Z", "endTime": "2026-07-17T02:08:00Z" },
      { "type": "LIGHT", "startTime": "2026-07-17T02:08:00Z", "endTime": "2026-07-17T06:30:00Z" }
    ],
    "summary": { "minutesAsleep": 457, "minutesAwake": 8, "stagesSummary": [ { "type": "DEEP", "minutes": 70 } ] }
  }
}
"""#)
if let session = HealthAPIClient.parseSleep(sleepPoint) {
    check(session.stages.count == 5, "5 sleep stages decoded")
    check(session.minutesAsleep == 457, "minutesAsleep taken from summary")
    check(session.stages[1].stage == .deep, "DEEP → .deep mapped")
    check(abs(session.minutesInBed - 465) < 0.01, "Time in bed = 465 min")
} else {
    check(false, "Sleep fixture could not be decoded")
}
check(HealthAPIClient.parseSleep(["sleep": ["interval": [:]]]) == nil, "Incomplete sleep data → nil instead of crash")

// MARK: DayKey

section("DayKey")
check(DayKey.addDays("2026-07-18", -1) == "2026-07-17", "addDays across day boundary")
check(DayKey.keys(from: "2026-02-27", to: "2026-03-02").count == 4, "Leap year range (2026 no leap year): Feb 27–Mar 2 = 4 days")
check(DayKey.distance(from: "2026-07-01", to: "2026-07-18") == 17, "Distance between keys")
if let lateEvening = DayKey.date(from: "2026-07-17")?.addingTimeInterval(23 * 3600) {
    check(DayKey.nightKey(for: lateEvening) == "2026-07-18", "11 PM sample counts towards next day's night")
}
if let earlyMorning = DayKey.date(from: "2026-07-18")?.addingTimeInterval(5 * 3600) {
    check(DayKey.nightKey(for: earlyMorning) == "2026-07-18", "5 AM sample counts towards same day")
}

// MARK: Statistik

section("Statistics")
check(Stats.percentile([1, 2, 3, 4, 5], 0.5) == 3, "Median")
check(Stats.percentile([10], 0.05) == 10, "Percentile with one value")
check(abs(Stats.logistic(0) - 0.5) < 1e-9, "Logistic(0) = 0.5")
if let baseline = Stats.baseline([60, 62, 64, 66, 68]) {
    check(abs(baseline.mean - 64) < 1e-9, "Baseline mean")
    check(baseline.isReliable, "5 values are considered reliable")
    check(abs(baseline.z(64)) < 1e-9, "z-score at mean = 0")
} else {
    check(false, "Baseline nil despite 5 values")
}
check(Stats.baseline([1, 2]) == nil, "Baseline needs at least 3 values")

// MARK: Strain-Engine

section("Strain-Engine")
check(StrainEngine.strain(fromRaw: 0) == 0, "No load → strain 0")
let s60 = StrainEngine.strain(fromRaw: 60)
let s300 = StrainEngine.strain(fromRaw: 300)
let s900 = StrainEngine.strain(fromRaw: 900)
let s5000 = StrainEngine.strain(fromRaw: 5000)
check(s60 > 2 && s60 < 4, "Easy day ≈ 2–4 (is \(String(format: "%.1f", s60)))")
check(s300 > 9 && s300 < 12, "Solid training ≈ 9–12 (is \(String(format: "%.1f", s300)))")
check(s900 > 16 && s900 < 19, "Hard day ≈ 16–19 (is \(String(format: "%.1f", s900)))")
check(s5000 < 21, "Scale stays under 21 (is \(String(format: "%.2f", s5000)))")
check(s60 < s300 && s300 < s900 && s900 < s5000, "Strain grows monotonically with load")
check(StrainEngine.zoneIndex(for: 0.1) == nil, "Below zone 0 → no load")
check(StrainEngine.zoneIndex(for: 0.5) == 2, "50 % HRR → zone 3 (index 2)")
check(StrainEngine.zoneIndex(for: 0.99) == 5, "99 % HRR → maximum zone")

// MARK: Demo Data & Engines End-to-End

section("Demo Data & Engines")
let demoDays = DemoData.generate(daysBack: 120, seed: 42)
check(demoDays.count == 120, "120 demo days generated")
let sortedKeys = demoDays.keys.sorted()

let strainConfig = StrainConfig(age: 30)
var strainByDay: [String: Double] = [:]
for (key, record) in demoDays {
    let result = StrainEngine.dayStrain(record: record, restingHR: record.restingHR, config: strainConfig)
    strainByDay[key] = result.strain
    if result.strain < 0 || result.strain > 21 {
        check(false, "Strain outside 0–21 at \(key): \(result.strain)")
    }
}
check(strainByDay.values.allSatisfy { $0 >= 0 && $0 <= 21 }, "All daily strains in 0–21")
let maxStrain = strainByDay.values.max() ?? 0
let avgStrain = strainByDay.values.reduce(0, +) / Double(strainByDay.count)
check(maxStrain > 10, "Hard days reach strain > 10 (max \(String(format: "%.1f", maxStrain)))")
check(avgStrain > 3 && avgStrain < 16, "Average strain plausible (\(String(format: "%.1f", avgStrain)))")

let sleepConfig = SleepEngineConfig()
let sleepAnalyses = SleepEngine.analyze(days: demoDays, config: sleepConfig, strainByDay: strainByDay)
check(sleepAnalyses.count == 120, "Sleep analysis for all days")
for (key, analysis) in sleepAnalyses {
    if analysis.needMinutes < 300 || analysis.needMinutes > 620 {
        check(false, "Sleep need outside plausibility at \(key): \(analysis.needMinutes)")
    }
    if analysis.debtAfterMinutes < 0 || analysis.debtAfterMinutes > sleepConfig.maxDebtMinutes {
        check(false, "Sleep debt outside bounds at \(key)")
    }
    if let consistency = analysis.consistency, consistency < 0 || consistency > 100 {
        check(false, "Consistency outside 0–100 at \(key)")
    }
    if analysis.performance < 0 || analysis.performance > 100 {
        check(false, "Sleep performance outside 0–100 at \(key)")
    }
}
check(true, "Need/debt/consistency/performance in valid ranges")
let withStages = sleepAnalyses.values.filter { !$0.stageMinutes.isEmpty }
check(withStages.count == 120, "All nights have stage minutes")

var recoveryScores: [Int] = []
for key in sortedKeys.suffix(60) {
    guard let record = demoDays[key] else { continue }
    let history = sortedKeys.filter { $0 < key }.compactMap { demoDays[$0] }
    let result = RecoveryEngine.compute(
        dateKey: key,
        today: record,
        history: history,
        sleepPerformance: sleepAnalyses[key]?.performance
    )
    if let result {
        recoveryScores.append(result.score)
        if result.score < 1 || result.score > 99 {
            check(false, "Recovery outside 1–99 at \(key): \(result.score)")
        }
        let expectedZone: RecoveryZone = result.score >= 67 ? .green : (result.score >= 34 ? .yellow : .red)
        if result.zone != expectedZone {
            check(false, "Zone mapping wrong at \(key)")
        }
        let weightSum = result.components.reduce(0) { $0 + $1.weight }
        if abs(weightSum - 1) > 0.001 {
            check(false, "Component weights do not sum to 1 at \(key)")
        }
    } else {
        check(false, "Recovery nil despite data at \(key)")
    }
}
check(recoveryScores.count == 60, "Recovery calculated for the last 60 days")
let recoveryRange = (recoveryScores.min() ?? 0)...(recoveryScores.max() ?? 0)
check(recoveryRange.upperBound - recoveryRange.lowerBound >= 20, "Recovery scatters realistically (\(recoveryRange))")

if let lastKey = sortedKeys.last, let lastRecord = demoDays[lastKey] {
    let history = sortedKeys.dropLast().compactMap { demoDays[$0] }
    let statuses = HealthMonitor.evaluate(today: lastRecord, history: Array(history))
    check(statuses.count == HealthMetricKind.allCases.count, "Health monitor returns all metrics")
    check(statuses.allSatisfy { $0.state != .noData }, "Demo data: no metric without data")
    let rhrStatus = statuses.first { $0.kind == .restingHR }
    check(rhrStatus?.lowerBound != nil && rhrStatus?.upperBound != nil, "Resting HR has baseline band")
}

// MARK: Workout-Strain

section("Workout-Strain")
var workoutStrainChecked = false
for key in sortedKeys.suffix(28) {
    guard let record = demoDays[key], let workout = record.workouts.first else { continue }
    if let strain = StrainEngine.workoutStrain(workout: workout, daySamples: record.hrSamples, restingHR: record.restingHR, config: strainConfig) {
        check(strain > 0 && strain <= 21, "Workout-Strain (\(workout.name), \(key)) in 0–21: \(String(format: "%.1f", strain))")
        workoutStrainChecked = true
        break
    }
}
check(workoutStrainChecked, "At least one workout strain calculated")

// MARK: Sync-Helfer

section("Sync Helpers")
let base = DayKey.date(from: "2026-07-17")!
let rawSamples = (0..<120).map { i in
    SamplePoint(time: base.addingTimeInterval(Double(i) * 5), value: 60 + Double(i % 10))
}
let downsampled = SyncEngine.downsampleToMinutes(rawSamples)
check(downsampled.count == 10, "600 s in 5-s resolution → 10 minute buckets")
check(downsampled.allSatisfy { $0.bpm >= 60 && $0.bpm <= 70 }, "Downsampling averages correctly")

let nightSamples = [
    SamplePoint(time: DayKey.date(from: "2026-07-16")!.addingTimeInterval(23.5 * 3600), value: 55),
    SamplePoint(time: DayKey.date(from: "2026-07-17")!.addingTimeInterval(3 * 3600), value: 65),
]
let grouped = SyncEngine.groupByNight(nightSamples)
check(grouped["2026-07-17"]?.count == 2, "Night grouping combines evening + morning")

// MARK: Store-Roundtrip

section("MetricsStore")
let tempDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("pulse-selftest-\(UUID().uuidString)")
let store = MetricsStore(directory: tempDir)
store.merge(Array(demoDays.values))
check(store.days.count == 120, "Store contains 120 days")
check(store.save(), "Save successful")

let reloaded = MetricsStore(directory: tempDir)
check(reloaded.days.count == 120, "Reload returns 120 days")
if let lastKey = sortedKeys.last {
    let original = store.days[lastKey]
    let restored = reloaded.days[lastKey]
    check(original?.hrvRmssd == restored?.hrvRmssd, "HRV survives roundtrip")
    check(original?.sleepSessions.count == restored?.sleepSessions.count, "Sleep sessions survive roundtrip")
    check((restored?.hrSamples.count ?? 0) > 0, "HR samples of the last day preserved")
}
let historyCheck = reloaded.history(before: sortedKeys.last!, days: 30)
check(historyCheck.count == 30, "history(before:) returns 30 days")
try? FileManager.default.removeItem(at: tempDir)

// MARK: Ergebnis

print("")
if failures.isEmpty {
    print("ALL TESTS PASSED ✅")
    exit(0)
} else {
    print("\(failures.count) TEST(S) FAILED ❌")
    for failure in failures {
        print("  – \(failure)")
    }
    exit(1)
}
