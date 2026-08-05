import Foundation
import Observation
import AuthenticationServices

/// Central app model: holds store, auth, settings, and the calculated
/// Whoop metrics (recovery, strain, sleep) for all views.
@MainActor
@Observable
final class AppModel {
    // MARK: - Settings (persisted in UserDefaults)

    private enum Keys {
        static let clientID = "google.clientID"
        static let onboarded = "app.onboarded"
        static let demoMode = "app.demoMode"
        static let daysBack = "sync.daysBack"
        static let hrDaysBack = "sync.hrDaysBack"
        static let sleepNeed = "calc.sleepNeedMinutes"
        static let age = "calc.age"
        static let maxHR = "calc.maxHROverride"
        static let lastSync = "sync.lastSyncAt"
    }

    var clientID: String {
        didSet { defaults.set(clientID, forKey: Keys.clientID) }
    }
    var onboarded: Bool {
        didSet { defaults.set(onboarded, forKey: Keys.onboarded) }
    }
    var demoMode: Bool {
        didSet { defaults.set(demoMode, forKey: Keys.demoMode) }
    }
    var daysBack: Int {
        didSet { defaults.set(daysBack, forKey: Keys.daysBack) }
    }
    var hrDaysBack: Int {
        didSet { defaults.set(hrDaysBack, forKey: Keys.hrDaysBack) }
    }
    var baseSleepNeedMinutes: Double {
        didSet {
            defaults.set(baseSleepNeedMinutes, forKey: Keys.sleepNeed)
            recomputeAll()
        }
    }
    var age: Int {
        didSet {
            defaults.set(age, forKey: Keys.age)
            recomputeAll()
        }
    }
    /// 0 = automatic (Tanaka formula)
    var maxHROverride: Double {
        didSet {
            defaults.set(maxHROverride, forKey: Keys.maxHR)
            recomputeAll()
        }
    }
    var lastSyncAt: Date? {
        didSet {
            if let lastSyncAt {
                defaults.set(lastSyncAt.timeIntervalSince1970, forKey: Keys.lastSync)
            } else {
                defaults.removeObject(forKey: Keys.lastSync)
            }
        }
    }

    // MARK: - Runtime State

    private(set) var syncing = false
    private(set) var syncMessage = ""
    private(set) var syncFraction: Double = 0
    var lastError: String?
    private(set) var syncLog: [SyncLogEntry] = []
    var selectedDayKey: String
    private(set) var profileName: String?

    // MARK: - Data & Derived Metrics

    let store: MetricsStore
    let auth = GoogleAuth()
    private(set) var strainResults: [String: StrainResult] = [:]
    private(set) var sleepAnalyses: [String: SleepAnalysis] = [:]
    private(set) var recoveryResults: [String: RecoveryResult] = [:]

    private let defaults = UserDefaults.standard

    init() {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pulse", isDirectory: true)
        store = MetricsStore(directory: directory)

        clientID = defaults.string(forKey: Keys.clientID) ?? ""
        onboarded = defaults.bool(forKey: Keys.onboarded)
        demoMode = defaults.bool(forKey: Keys.demoMode)
        daysBack = (defaults.object(forKey: Keys.daysBack) as? Int) ?? 60
        hrDaysBack = (defaults.object(forKey: Keys.hrDaysBack) as? Int) ?? 14
        baseSleepNeedMinutes = (defaults.object(forKey: Keys.sleepNeed) as? Double) ?? 456
        age = (defaults.object(forKey: Keys.age) as? Int) ?? 30
        maxHROverride = (defaults.object(forKey: Keys.maxHR) as? Double) ?? 0
        lastSyncAt = (defaults.object(forKey: Keys.lastSync) as? Double).map(Date.init(timeIntervalSince1970:))
        selectedDayKey = DayKey.today()

        recomputeAll()
    }

    // MARK: - Derived Configuration

    var oauthConfig: GoogleOAuthConfig {
        GoogleOAuthConfig(clientID: clientID)
    }

    var isConnected: Bool {
        auth.isConnected
    }

    var strainConfig: StrainConfig {
        StrainConfig(age: age, maxHROverride: maxHROverride > 0 ? maxHROverride : nil)
    }

    var sleepConfig: SleepEngineConfig {
        var config = SleepEngineConfig()
        config.baselineNeedMinutes = baseSleepNeedMinutes
        return config
    }

    var hasData: Bool {
        !store.days.isEmpty
    }

    var availableKeys: [String] {
        store.sortedKeys
    }

    // MARK: - Access for Views

    func record(for key: String) -> DayRecord? {
        store.days[key]
    }

    func recovery(for key: String) -> RecoveryResult? {
        recoveryResults[key]
    }

    func sleep(for key: String) -> SleepAnalysis? {
        sleepAnalyses[key]
    }

    func strain(for key: String) -> StrainResult? {
        strainResults[key]
    }

    var selectedRecord: DayRecord? {
        record(for: selectedDayKey)
    }

    /// Health monitor status for the selected day.
    var healthStatuses: [HealthMetricStatus] {
        guard let record = selectedRecord else { return [] }
        let history = store.history(before: selectedDayKey, days: 45)
        return HealthMonitor.evaluate(today: record, history: history)
    }

    /// Values of a metric for the last `count` days up to the selected day.
    func trend(_ count: Int, endingAt key: String? = nil, _ value: (DayRecord) -> Double?) -> [(key: String, value: Double)] {
        let end = key ?? selectedDayKey
        let start = DayKey.addDays(end, -(count - 1))
        return DayKey.keys(from: start, to: end).compactMap { dayKey in
            guard let record = store.days[dayKey], let v = value(record) else { return nil }
            return (dayKey, v)
        }
    }

    // MARK: - Recomputation

    func recomputeAll() {
        var strains: [String: StrainResult] = [:]
        var strainScalar: [String: Double] = [:]
        for (key, record) in store.days {
            let result = StrainEngine.dayStrain(record: record, restingHR: record.restingHR, config: strainConfig)
            strains[key] = result
            strainScalar[key] = result.strain
        }
        strainResults = strains

        sleepAnalyses = SleepEngine.analyze(days: store.days, config: sleepConfig, strainByDay: strainScalar)

        // Write workout strains into the records
        for (_, record) in store.days where !record.workouts.isEmpty {
            var updated = record
            for index in updated.workouts.indices {
                updated.workouts[index].strain = StrainEngine.workoutStrain(
                    workout: updated.workouts[index],
                    daySamples: record.hrSamples,
                    restingHR: record.restingHR,
                    config: strainConfig
                )
            }
            store.upsert(updated)
        }

        // Recovery chronologically with growing history
        var recoveries: [String: RecoveryResult] = [:]
        var history: [DayRecord] = []
        let keys = store.sortedKeys
        history.reserveCapacity(keys.count)
        for key in keys {
            guard let record = store.days[key] else { continue }
            recoveries[key] = RecoveryEngine.compute(
                dateKey: key,
                today: record,
                history: history,
                sleepPerformance: sleepAnalyses[key]?.performance
            )
            history.append(record)
        }
        recoveryResults = recoveries

        if store.days[selectedDayKey] == nil, let last = keys.last {
            selectedDayKey = last
        }
    }

    // MARK: - Actions

    func startDemo() {
        store.replaceAll(DemoData.generate(daysBack: 120, seed: 42))
        store.save()
        demoMode = true
        onboarded = true
        selectedDayKey = DayKey.today()
        lastError = nil
        recomputeAll()
    }

    func connect() async {
        lastError = nil
        let config = oauthConfig
        guard config.isValid, let scheme = config.reversedClientScheme else {
            lastError = AuthError.invalidClientID.errorDescription
            return
        }
        let pkce = PKCE()
        let state = UUID().uuidString
        guard let url = auth.authorizationURL(config: config, pkce: pkce, state: state) else {
            lastError = "Authorization URL could not be created."
            return
        }
        do {
            let callback = try await WebAuthenticator.shared.authenticate(url: url, callbackScheme: scheme)
            guard let code = GoogleAuth.extractCode(from: callback, expectedState: state) else {
                lastError = "No valid authorization code received."
                return
            }
            _ = try await auth.exchange(code: code, pkce: pkce, config: config)
            if demoMode {
                store.wipe()
                demoMode = false
            }
            onboarded = true
            recomputeAll()
            await syncNow()
        } catch let error as AuthError {
            lastError = error.errorDescription
        } catch {
            let nsError = error as NSError
            let cancelled = nsError.domain == ASWebAuthenticationSessionError.errorDomain
                && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
            if !cancelled {
                lastError = error.localizedDescription
            }
        }
    }

    func syncNow() async {
        guard !syncing else { return }
        guard isConnected else {
            lastError = AuthError.notConnected.errorDescription
            return
        }
        syncing = true
        syncMessage = "Starting…"
        syncFraction = 0
        defer { syncing = false }

        let client = HealthAPIClient(auth: auth, config: oauthConfig)
        let engine = SyncEngine(client: client)
        
        let dailyOutcome = await engine.syncDailyMetrics(
            existingDays: store.days,
            daysBack: daysBack
        ) { [weak self] progress in
            Task { @MainActor in
                self?.syncMessage = progress.message
                self?.syncFraction = progress.fraction * 0.5 // Scale to first 50%
            }
        }
        
        // Save intermediate state in case of cancellation or crash
        store.replaceAll(dailyOutcome.updatedDays)
        store.save()
        syncLog = dailyOutcome.log
        profileName = dailyOutcome.profile?.displayName ?? profileName
        recomputeAll()

        if Task.isCancelled {
            syncing = false
            return
        }

        let hrOutcome = await engine.syncIntradayHeartRate(
            existingDays: store.days,
            hrDaysBack: hrDaysBack,
            maxConcurrent: 4
        ) { [weak self] progress in
            Task { @MainActor in
                self?.syncMessage = progress.message
                self?.syncFraction = 0.5 + progress.fraction * 0.5 // Scale to second 50%
            }
        }

        if Task.isCancelled {
            syncing = false
            return
        }

        store.replaceAll(hrOutcome.updatedDays)
        store.save()
        syncLog.append(contentsOf: hrOutcome.log)
        
        lastSyncAt = Date()
        recomputeAll()

        if dailyOutcome.hadErrors || hrOutcome.hadErrors {
            lastError = "Sync completed with warnings – details in the sync log."
        }
    }

    func disconnect() {
        auth.disconnect()
    }

    func resetAll() {
        store.wipe()
        syncLog = []
        lastSyncAt = nil
        demoMode = false
        onboarded = false
        profileName = nil
        lastError = nil
        recomputeAll()
    }
}
