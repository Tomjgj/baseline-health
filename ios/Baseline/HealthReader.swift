import CoreLocation
import Foundation
import HealthKit
import WidgetKit

/// Reads HealthKit and builds a `baseline.health/1` payload: the raw samples the page turns into daily
/// summaries with the same code that reads the Health export (HI.fromJSON in index.html).
/// Times are local wall-clock strings, so day boundaries match the phone, as in the export.
final class HealthReader {
    struct Failure: Error { let code: String }

    /// One reader for the app, so the observers registered at launch (AppDelegate) are the ones the page's requests use.
    static let shared = HealthReader()

    private let store = HKHealthStore()
    private var authorized = false
    private var observing = false
    /// Set once the person has been asked for Health access, so later launches register the observers straight away.
    private static let askedKey = "baseline.healthAsked"
    /// Marks the water samples the app writes, so a removed log can find its sample again.
    private static let waterKey = "BaselineID"
    /// Called (on any thread) when Health has new data: watch readings, last night's sleep, a workout, water.
    var onNewReadings: (() -> Void)?

    private init() {}

    // what the app reads, with the unit each value is sent in
    private let quantities: [(HKQuantityTypeIdentifier, String, HKUnit)] = [
        (.heartRate, "hr", HKUnit.count().unitDivided(by: .minute())),
        (.restingHeartRate, "rhr", HKUnit.count().unitDivided(by: .minute())),
        (.heartRateVariabilitySDNN, "hrv", HKUnit.secondUnit(with: .milli)),
        (.respiratoryRate, "resp", HKUnit.count().unitDivided(by: .minute())),
        (.oxygenSaturation, "spo2", HKUnit.percent()),
        (.appleSleepingWristTemperature, "temp", HKUnit.degreeCelsius()),
        (.vo2Max, "vo2", HKUnit(from: "ml/kg*min")),
        (.stepCount, "steps", HKUnit.count()),
        (.activeEnergyBurned, "active", HKUnit.kilocalorie()),
        (.basalEnergyBurned, "basal", HKUnit.kilocalorie()),
        (.timeInDaylight, "daylight", HKUnit.minute()),
        (.dietaryCaffeine, "caffeine", HKUnit.gramUnit(with: .milli)),
        (.dietaryWater, "water", HKUnit.literUnit(with: .milli)),
        (.numberOfAlcoholicBeverages, "alcohol", HKUnit.count()),
        (.bloodPressureSystolic, "bpSys", HKUnit.millimeterOfMercury()),
        (.bloodPressureDiastolic, "bpDia", HKUnit.millimeterOfMercury()),
        (.bodyMass, "weight", HKUnit.gramUnit(with: .kilo)),
        (.bodyFatPercentage, "bodyFat", HKUnit.percent()),
        (.leanBodyMass, "lean", HKUnit.gramUnit(with: .kilo)),
        (.waistCircumference, "waist", HKUnit.meterUnit(with: .centi)),
        (.dietaryEnergyConsumed, "dKcal", HKUnit.kilocalorie()),
        (.dietaryProtein, "dP", HKUnit.gram()),
        (.dietaryCarbohydrates, "dC", HKUnit.gram()),
        (.dietaryFatTotal, "dF", HKUnit.gram()),
    ]

    private lazy var readTypes: Set<HKObjectType> = {
        var types = Set<HKObjectType>(quantities.map { HKQuantityType($0.0) as HKObjectType })
        types.insert(HKQuantityType(.height))
        types.insert(HKCategoryType(.sleepAnalysis))
        types.insert(HKCategoryType(.mindfulSession))
        types.insert(HKObjectType.workoutType())
        types.insert(HKCharacteristicType(.dateOfBirth))
        types.insert(HKCharacteristicType(.biologicalSex))
        return types
    }()

    private let local: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()
    private let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Whether the person has answered the Health sheet already, so the page can skip its welcome.
    var hasAsked: Bool { UserDefaults.standard.bool(forKey: Self.askedKey) }

    /// What a workout's own page reads on top of the sync: the route and the distance covered along the way. New installs are
    /// asked for these with everything else; earlier ones the first time a workout opens.
    private static let detailTypes: Set<HKObjectType> = [HKSeriesType.workoutRoute(), HKQuantityType(.distanceWalkingRunning),
                                                         HKQuantityType(.distanceCycling), HKQuantityType(.distanceSwimming)]

    private func authorize() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw Failure(code: "unavailable") }
        if authorized { return }
        // iOS never says which types were refused; refused ones simply come back empty. Writing is asked for separately, when the
        // person turns on "Save to Apple Health" (HealthWriter).
        let read = hasAsked ? readTypes : readTypes.union(Self.detailTypes)
        try await store.requestAuthorization(toShare: [], read: read)
        authorized = true
        UserDefaults.standard.set(true, forKey: Self.askedKey)
        observe()
    }

    // MARK: new data, also in the background

    /// Called at launch: once the person has answered the Health sheet, the observers go back on before the page asks for anything,
    /// so a background launch by Health is handled too.
    func startObserving() {
        if UserDefaults.standard.bool(forKey: Self.askedKey) { observe() }
    }

    /// Watch Health for new data. Heart rate only while the app runs (for the page's "now"); the rest also wakes the app in the
    /// background: sleep and workouts as soon as they're saved, HRV, resting heart rate and water at most hourly.
    /// The watch hands its readings to the iPhone in batches, so they land here a little after they were taken.
    private func observe() {
        DispatchQueue.main.async {
            guard !self.observing else { return }
            self.observing = true
            let watched: [(HKSampleType, HKUpdateFrequency?)] = [
                (HKQuantityType(.heartRate), nil),
                (HKQuantityType(.heartRateVariabilitySDNN), .hourly),
                (HKQuantityType(.restingHeartRate), .hourly),
                (HKCategoryType(.sleepAnalysis), .immediate),
                (HKObjectType.workoutType(), .immediate),
                (HKQuantityType(.dietaryWater), .hourly),
            ]
            for (type, frequency) in watched {
                let sleep = type.identifier == HKCategoryTypeIdentifier.sleepAnalysis.rawValue
                let q = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                    guard let self, error == nil else { completion(); return }
                    self.newData(sleep: sleep, completion: completion)
                }
                self.store.execute(q)
                if let frequency {
                    self.store.enableBackgroundDelivery(for: type, frequency: frequency) { ok, error in
                        if !ok { log.error("background delivery off for \(type.identifier, privacy: .public): \(error?.localizedDescription ?? "", privacy: .public)") }
                    }
                }
            }
        }
    }

    /// Widgets reload, the page (if it's loaded) syncs, and new sleep may mean the morning notification is due.
    /// Health waits for `completion` before it lets the app sleep again.
    private func newData(sleep: Bool, completion: @escaping () -> Void) {
        DispatchQueue.main.async { WidgetCenter.shared.reloadAllTimelines() }
        onNewReadings?()
        guard sleep else { completion(); return }
        Task {
            await morningCheck()
            completion()
        }
    }

    private static let morningLock = NSLock()
    private static var morningBusy = false

    /// Once a morning (4:00 to 13:00), when last night's sleep has arrived: at least 3 hours asleep, ending in the last 3 hours.
    private func morningCheck() async {
        guard Prefs.morning else { return }
        // the sleep observer can fire twice in a row; only one check runs at a time
        let busy = Self.morningLock.withLock { () -> Bool in
            let was = Self.morningBusy
            Self.morningBusy = true
            return was
        }
        guard !busy else { return }
        defer { Self.morningLock.withLock { Self.morningBusy = false } }

        let now = Date(), cal = Calendar.current
        let today = day.string(from: now)
        guard (4..<13).contains(cal.component(.hour, from: now)), Prefs.morningNotified != today,
              let yesterday = cal.date(byAdding: .day, value: -1, to: now),
              let start = cal.date(bySettingHour: 18, minute: 0, second: 0, of: yesterday) else { return }
        let window = HKQuery.predicateForSamples(withStart: start, end: now, options: [])
        guard let found = try? await read(HKCategoryType(.sleepAnalysis), window) else { return }
        let asleepValues = Set([HKCategoryValueSleepAnalysis.asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM].map(\.rawValue))
        // the iPhone and the watch can both record the same night, so overlapping stretches count once
        let spans = found.compactMap { s -> (Date, Date)? in
            guard let c = s as? HKCategorySample, asleepValues.contains(c.value) else { return nil }
            let from = max(c.startDate, start)
            return c.endDate > from ? (from, c.endDate) : nil
        }.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for s in spans {
            if let c = current, s.0 <= c.1 {
                current = (c.0, max(c.1, s.1))
            } else {
                if let c = current { total += c.1.timeIntervalSince(c.0) }
                current = s
            }
        }
        if let c = current { total += c.1.timeIntervalSince(c.0) }
        guard total >= 3 * 3600, let last = spans.map(\.1).max(), now.timeIntervalSince(last) <= 3 * 3600 else { return }
        Prefs.morningNotified = today
        let minutes = Int(total / 60)
        Notifier.post(key: "morning", title: "Your recovery is ready",
                      body: "You slept \(minutes / 60)h \(String(format: "%02d", minutes % 60))m. Open Baseline to see today's recovery.")
        log.notice("morning notification posted")
    }

    // MARK: water, written to Health

    /// Saves a water log as a dietary water sample at its time, tagged with the page's id. Returns false when Health
    /// isn't available or the person didn't allow writing water.
    func saveWater(key: String, ml: Double, at: Date) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(), ml > 0, (try? await authorize()) != nil else { return false }
        let type = HKQuantityType(.dietaryWater)
        guard store.authorizationStatus(for: type) == .sharingAuthorized else { return false }
        // the sync identifier makes a repeated save replace the first one instead of adding a second sample
        let metadata: [String: Any] = [Self.waterKey: key, HKMetadataKeySyncIdentifier: "baseline.water." + key, HKMetadataKeySyncVersion: 1]
        let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml), start: at, end: at, metadata: metadata)
        return await withCheckedContinuation { cont in
            store.save(sample) { ok, error in
                if let error { log.error("water not saved: \(error.localizedDescription, privacy: .public)") }
                cont.resume(returning: ok)
            }
        }
    }

    /// Deletes the sample saved for that water log (the app can only delete its own samples).
    func deleteWater(key: String) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let type = HKQuantityType(.dietaryWater)
        guard store.authorizationStatus(for: type) == .sharingAuthorized else { return false }
        let match = HKQuery.predicateForObjects(withMetadataKey: Self.waterKey, allowedValues: [key])
        return await withCheckedContinuation { cont in
            store.deleteObjects(of: type, predicate: match) { ok, _, _ in cont.resume(returning: ok) }
        }
    }

    /// The heart-rate readings of the last 3 hours and the HRV readings of the last 6, oldest first, as [[time, value]].
    func latest() async throws -> [String: Any] {
        try await authorize()
        let now = Date()
        var out: [String: Any] = ["at": local.string(from: now)]
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let wanted: [(HKQuantityTypeIdentifier, String, HKUnit, Double)] = [(.heartRate, "hr", bpm, 3), (.heartRateVariabilitySDNN, "hrv", HKUnit.secondUnit(with: .milli), 6)]
        for (id, key, unit, hours) in wanted {
            let window = HKQuery.predicateForSamples(withStart: now.addingTimeInterval(-hours * 3600), end: nil, options: [])
            out[key] = try await read(HKQuantityType(id), window).compactMap { s -> [Any]? in
                guard let q = s as? HKQuantitySample else { return nil }
                return [local.string(from: q.startDate), q.quantity.doubleValue(for: unit)]
            }
        }
        return out
    }

    /// Samples for the days `from`...`to` (YYYY-MM-DD), starting at noon the day before so that night is whole.
    func payload(from: String, to: String) async throws -> [String: Any] {
        try await authorize()
        guard let fromDay = day.date(from: from), let toDay = day.date(from: to) else { throw Failure(code: "sync-failed") }
        let cal = Calendar.current
        let start = cal.date(byAdding: .hour, value: -12, to: fromDay)!
        let end = min(cal.date(byAdding: .day, value: 1, to: toDay)!, Date())
        let window = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        var samples: [String: [[Any]]] = [:]
        var bp: [String: (sys: Double?, dia: Double?)] = [:]

        // Totals (steps, energy, daylight) come from Health's own statistics in half-hour buckets: Health already merges
        // iPhone and Watch without double counting, and it's far less data than every sample. Heart rate is averaged per
        // minute, which keeps zones and lows intact but sends 60 values for a workout hour instead of 700.
        let bpm = HKUnit.count().unitDivided(by: .minute())
        async let hrPts = statistics(.heartRate, unit: bpm, start: start, end: end, minutes: 1, sum: false)
        async let stepPts = statistics(.stepCount, unit: .count(), start: start, end: end, minutes: 30, sum: true)
        async let activePts = statistics(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end, minutes: 30, sum: true)
        async let basalPts = statistics(.basalEnergyBurned, unit: .kilocalorie(), start: start, end: end, minutes: 30, sum: true)
        async let daylightPts = statistics(.timeInDaylight, unit: .minute(), start: start, end: end, minutes: 30, sum: true)
        async let sleepFound = read(HKCategoryType(.sleepAnalysis), window)
        async let mindfulFound = read(HKCategoryType(.mindfulSession), window)
        async let workoutFound = read(HKObjectType.workoutType(), window)
        // everything else, read in parallel
        let viaStats: Set<String> = ["hr", "steps", "active", "basal", "daylight"]
        let rawResults = try await withThrowingTaskGroup(of: (String, HKUnit, [HKSample]).self) { group -> [(String, HKUnit, [HKSample])] in
            for (id, key, unit) in quantities where !viaStats.contains(key) {
                group.addTask { (key, unit, try await self.read(HKQuantityType(id), window)) }
            }
            var all: [(String, HKUnit, [HKSample])] = []
            for try await r in group { all.append(r) }
            return all
        }
        let hrList = try await hrPts
        samples["hr"] = hrList.map { [local.string(from: $0.0), $0.1] }
        let steps = try await stepPts, active = try await activePts, basal = try await basalPts, daylight = try await daylightPts
        for (key, pts) in [("steps", steps), ("active", active), ("basal", basal), ("daylight", daylight)] {
            samples[key] = pts.map { [local.string(from: $0.0), $0.1, "Health"] }
        }
        let ownBundle = Bundle.main.bundleIdentifier
        for (key, unit, found) in rawResults {
            for case let q as HKQuantitySample in found {
                // what the app saved itself (water, food, weigh-ins; HealthWriter) is already in the page's log
                if q.sourceRevision.source.bundleIdentifier == ownBundle { continue }
                var v = q.quantity.doubleValue(for: unit)
                let t = local.string(from: q.startDate), src = q.sourceRevision.source.name
                switch key {
                case "spo2", "bodyFat": v *= 100
                default: break
                }
                switch key {
                case "temp": samples["temp", default: []].append([local.string(from: q.endDate), v])
                case "caffeine", "water": samples[key, default: []].append([t, v, src])
                case "bpSys": bp[t, default: (nil, nil)].sys = v
                case "bpDia": bp[t, default: (nil, nil)].dia = v
                case "weight", "bodyFat", "lean", "waist": samples["body", default: []].append([t, key, v])
                case "dKcal", "dP", "dC", "dF":
                    let k = ["dKcal": "kcal", "dP": "p", "dC": "c", "dF": "f"][key]!
                    samples["diet", default: []].append([t, k, v, src])
                default: samples[key, default: []].append([t, v])
                }
            }
        }
        for (t, r) in bp { if let s = r.sys, let d = r.dia { samples["bp", default: []].append([t, s, d]) } }

        for case let c as HKCategorySample in try await sleepFound {
            // naps logged in Baseline and saved from here are already in the page's log
            if c.sourceRevision.source.bundleIdentifier == ownBundle { continue }
            let stage: String
            switch HKCategoryValueSleepAnalysis(rawValue: c.value) ?? .asleepUnspecified {
            case .inBed: stage = "inBed"
            case .awake: stage = "awake"
            case .asleepREM: stage = "rem"
            case .asleepCore: stage = "core"
            case .asleepDeep: stage = "deep"
            default: stage = "asleep"
            }
            samples["sleep", default: []].append([local.string(from: c.startDate), local.string(from: c.endDate), stage, c.sourceRevision.source.name])
        }
        for case let c as HKCategorySample in try await mindfulFound {
            samples["mindful", default: []].append([local.string(from: c.startDate), local.string(from: c.endDate)])
        }

        var workouts: [[String: Any]] = []
        for case let w as HKWorkout in try await workoutFound {
            // workouts logged on the iPhone and saved from here are already in the page's log (the watch app's have their own source)
            if w.sourceRevision.source.bundleIdentifier == ownBundle { continue }
            var o: [String: Any] = ["start": local.string(from: w.startDate), "end": local.string(from: w.endDate),
                                    "type": Self.workoutName(w.workoutActivityType), "min": w.duration / 60, "source": w.sourceRevision.source.name]
            if let e = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity() { o["kcal"] = e.doubleValue(for: .kilocalorie()) }
            for d in [HKQuantityTypeIdentifier.distanceWalkingRunning, .distanceCycling, .distanceSwimming] {
                if let km = w.statistics(for: HKQuantityType(d))?.sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo)), km > 0 { o["km"] = km }
            }
            let hrUnit = HKUnit.count().unitDivided(by: .minute())
            if let hr = w.statistics(for: HKQuantityType(.heartRate)) {
                if let a = hr.averageQuantity() { o["avgHr"] = a.doubleValue(for: hrUnit) }
                if let m = hr.maximumQuantity() { o["maxHr"] = m.doubleValue(for: hrUnit) }
            }
            workouts.append(o)
        }

        var me: [String: Any] = [:]
        if let dob = try? store.dateOfBirthComponents(), let date = cal.date(from: dob) { me["birthDate"] = day.string(from: date) }
        if let sex = try? store.biologicalSex().biologicalSex { if sex == .male { me["sex"] = "male" } else if sex == .female { me["sex"] = "female" } }
        let heights = try await read(HKQuantityType(.height), nil, limit: 1, newestFirst: true)
        if let h = heights.first as? HKQuantitySample { me["heightCm"] = h.quantity.doubleValue(for: .meterUnit(with: .centi)) }

        return ["format": "baseline.health/1", "from": from, "to": to, "me": me, "samples": samples, "workouts": workouts]
    }

    // MARK: one workout in detail

    /// The workout that best overlaps `start`...`end` (local times, as the sync sends them), in detail, for its page:
    /// heart rate every 10 seconds, the distance covered so far every 10 seconds, the route (at most 500 points), and what the
    /// watch noted: elevation climbed, weather, indoors. Times are seconds from the start. The route's locations come back as
    /// well, so the caller can draw the map.
    func workoutDetail(start: String, end: String) async throws -> (payload: [String: Any], route: [CLLocation]) {
        try await authorize()
        // asks only for what hasn't been asked before; nothing shows when the answers are in
        try? await store.requestAuthorization(toShare: [], read: Self.detailTypes)
        guard let s = local.date(from: start), let e = local.date(from: end) else { throw Failure(code: "bad_request") }
        let around = HKQuery.predicateForSamples(withStart: s.addingTimeInterval(-180), end: e.addingTimeInterval(180), options: [])
        let found = try await read(HKObjectType.workoutType(), around).compactMap { $0 as? HKWorkout }
        let overlap = { (w: HKWorkout) in min(w.endDate, e).timeIntervalSince(max(w.startDate, s)) }
        guard let w = found.max(by: { overlap($0) < overlap($1) }), overlap(w) > 0 else { throw Failure(code: "not_found") }
        let t0 = w.startDate, sec = { (d: Date) in (d.timeIntervalSince(t0)).rounded() }

        var out: [String: Any] = ["start": local.string(from: w.startDate), "end": local.string(from: w.endDate), "min": w.duration / 60]
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hr = try await statistics(.heartRate, unit: bpm, start: w.startDate, end: w.endDate, every: DateComponents(second: 10), sum: false, anchor: t0)
        out["hr"] = hr.map { [sec($0.0), $0.1.rounded()] }

        let distanceType: HKQuantityTypeIdentifier = switch w.workoutActivityType {
        case .cycling: .distanceCycling
        case .swimming: .distanceSwimming
        default: .distanceWalkingRunning
        }
        var covered = 0.0
        let dist = try await statistics(distanceType, unit: .meter(), start: w.startDate, end: w.endDate, every: DateComponents(second: 10), sum: true, anchor: t0)
        out["dist"] = dist.map { b -> [Double] in covered += b.1; return [sec(b.0) + 10, covered.rounded()] }
        if let steps = try? await statistics(.stepCount, unit: .count(), start: w.startDate, end: w.endDate, every: DateComponents(day: 1), sum: true, anchor: t0),
           !steps.isEmpty {
            out["steps"] = steps.reduce(0) { $0 + $1.1 }.rounded()
        }

        let meta = w.metadata ?? [:]
        if let q = meta[HKMetadataKeyElevationAscended] as? HKQuantity { out["climb"] = q.doubleValue(for: .meter()).rounded() }
        if let q = meta[HKMetadataKeyWeatherTemperature] as? HKQuantity { out["tempC"] = (q.doubleValue(for: .degreeCelsius()) * 10).rounded() / 10 }
        if let q = meta[HKMetadataKeyWeatherHumidity] as? HKQuantity { out["humidity"] = (q.doubleValue(for: .percent()) * 100).rounded() }
        if let indoor = meta[HKMetadataKeyIndoorWorkout] as? Bool { out["indoor"] = indoor }

        // the route: its points in order, without the inaccurate ones, thinned to 500
        var all: [CLLocation] = []
        for case let r as HKWorkoutRoute in try await read(HKSeriesType.workoutRoute(), HKQuery.predicateForObjects(from: w)) {
            all += (try? await locations(of: r)) ?? []
        }
        all = all.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50 }.sorted { $0.timestamp < $1.timestamp }
        var along = [0.0]
        for i in all.indices.dropFirst() { along.append(along[i - 1] + all[i].distance(from: all[i - 1])) }
        let keep = all.count <= 500 ? Array(all.indices) : (0..<500).map { Int((Double($0) * Double(all.count - 1) / 499).rounded()) }
        let route = keep.map { all[$0] }
        if route.count > 1 {
            out["route"] = keep.map { i -> [Double] in
                let l = all[i]
                return [sec(l.timestamp), (l.coordinate.latitude * 1e6).rounded() / 1e6, (l.coordinate.longitude * 1e6).rounded() / 1e6,
                        l.verticalAccuracy >= 0 ? (l.altitude * 10).rounded() / 10 : -9999, along[i].rounded()]
            }
        }
        return (out, route.count > 1 ? route : [])
    }

    /// Every location of a route, in the batches Health hands them over.
    private func locations(of route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation { cont in
            var all: [CLLocation] = []
            var finished = false
            let q = HKWorkoutRouteQuery(route: route) { _, batch, done, error in
                guard !finished else { return }
                if let error { finished = true; cont.resume(throwing: error); return }
                all += batch ?? []
                if done { finished = true; cont.resume(returning: all) }
            }
            store.execute(q)
        }
    }

    /// Sums or averages in fixed buckets, from Health's statistics: (bucket start, value) for buckets that have data.
    private func statistics(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date, minutes: Int, sum: Bool) async throws -> [(Date, Double)] {
        try await statistics(id, unit: unit, start: start, end: end, every: DateComponents(minute: minutes), sum: sum, anchor: Calendar.current.startOfDay(for: start))
    }

    private func statistics(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date, every: DateComponents, sum: Bool, anchor: Date) async throws -> [(Date, Double)] {
        try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: HKQuantityType(id),
                                                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end, options: []),
                                                options: sum ? .cumulativeSum : .discreteAverage,
                                                anchorDate: anchor,
                                                intervalComponents: every)
            q.initialResultsHandler = { _, results, error in
                if let error = error as? HKError, error.code == .errorAuthorizationDenied || error.code == .errorAuthorizationNotDetermined || error.code == .errorNoData {
                    cont.resume(returning: []); return
                }
                if let error { cont.resume(throwing: error); return }
                var out: [(Date, Double)] = []
                results?.enumerateStatistics(from: start, to: end) { s, _ in
                    if let v = (sum ? s.sumQuantity() : s.averageQuantity())?.doubleValue(for: unit), v > 0 { out.append((s.startDate, v)) }
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    private func read(_ type: HKSampleType, _ predicate: NSPredicate?, limit: Int = HKObjectQueryNoLimit, newestFirst: Bool = false) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { cont in
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: !newestFirst)]
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: sort) { _, results, error in
                // a type the person didn't allow returns no samples rather than an error
                if let error = error as? HKError, error.code == .errorAuthorizationDenied || error.code == .errorAuthorizationNotDetermined { cont.resume(returning: []); return }
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: results ?? [])
            }
            store.execute(q)
        }
    }

    /// Names the page's workoutName() already knows how to tidy (it splits camel case).
    static func workoutName(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .traditionalStrengthTraining: return "TraditionalStrengthTraining"
        case .functionalStrengthTraining: return "FunctionalStrengthTraining"
        case .highIntensityIntervalTraining: return "HighIntensityIntervalTraining"
        case .coreTraining: return "CoreTraining"
        case .crossTraining: return "CrossTraining"
        case .mixedCardio: return "MixedCardio"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .flexibility: return "Flexibility"
        case .cooldown: return "Cooldown"
        case .mindAndBody: return "MindAndBody"
        case .soccer: return "Soccer"
        case .basketball: return "Basketball"
        case .tennis: return "Tennis"
        case .tableTennis: return "TableTennis"
        case .badminton: return "Badminton"
        case .volleyball: return "Volleyball"
        case .socialDance, .cardioDance: return "Dance"
        case .martialArts: return "MartialArts"
        case .boxing: return "Boxing"
        case .climbing: return "Climbing"
        case .stairClimbing: return "StairClimbing"
        case .downhillSkiing: return "DownhillSkiing"
        case .snowboarding: return "Snowboarding"
        default: return "Workout"
        }
    }
}
