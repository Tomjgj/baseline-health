import Foundation
import HealthKit

/// Reads HealthKit and builds a `baseline.health/1` payload: the raw samples the page turns into daily
/// summaries with the same code that reads the Health export (HI.fromJSON in index.html).
/// Times are local wall-clock strings, so day boundaries match the phone, as in the export.
final class HealthReader {
    struct Failure: Error { let code: String }

    private let store = HKHealthStore()
    private var authorized = false
    private var observing = false
    /// Called (on any thread) when the watch has written new heart-rate or HRV readings to Health.
    var onNewReadings: (() -> Void)?

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

    private func authorize() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw Failure(code: "unavailable") }
        if authorized { return }
        // iOS never says which types were refused; refused ones simply come back empty
        try await store.requestAuthorization(toShare: [], read: readTypes)
        authorized = true
        observe()
    }

    /// Watch for new heart-rate and HRV readings while the app runs, so the page can refresh what it shows as "now".
    /// The watch measures heart rate every few minutes in the background (continuously during a workout) and hands
    /// the readings to the iPhone in batches, so they land here a little after they were taken.
    private func observe() {
        guard !observing else { return }
        observing = true
        for id in [HKQuantityTypeIdentifier.heartRate, .heartRateVariabilitySDNN] {
            let q = HKObserverQuery(sampleType: HKQuantityType(id), predicate: nil) { [weak self] _, completion, error in
                if error == nil { self?.onNewReadings?() }
                completion()
            }
            store.execute(q)
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
        for (key, unit, found) in rawResults {
            for case let q as HKQuantitySample in found {
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

    /// Sums or averages in fixed buckets, from Health's statistics: (bucket start, value) for buckets that have data.
    private func statistics(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date, minutes: Int, sum: Bool) async throws -> [(Date, Double)] {
        try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: HKQuantityType(id),
                                                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end, options: []),
                                                options: sum ? .cumulativeSum : .discreteAverage,
                                                anchorDate: Calendar.current.startOfDay(for: start),
                                                intervalComponents: DateComponents(minute: minutes))
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
