import Foundation
import HealthKit

/// Reads HealthKit and builds a `baseline.health/1` payload: the raw samples the page turns into daily
/// summaries with the same code that reads the Health export (HI.fromJSON in index.html).
/// Times are local wall-clock strings, so day boundaries match the phone, as in the export.
final class HealthReader {
    struct Failure: Error { let code: String }

    private let store = HKHealthStore()
    private var authorized = false

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
        var types = Set<HKObjectType>(quantities.map { HKQuantityType($0.0) })
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

    /// Samples for the days `from`...`to` (YYYY-MM-DD), starting at noon the day before so that night is whole.
    func payload(from: String, to: String) async throws -> [String: Any] {
        guard HKHealthStore.isHealthDataAvailable() else { throw Failure(code: "unavailable") }
        if !authorized {
            // iOS never says which types were refused; refused ones simply come back empty
            try await store.requestAuthorization(toShare: [], read: readTypes)
            authorized = true
        }
        guard let fromDay = day.date(from: from), let toDay = day.date(from: to) else { throw Failure(code: "sync-failed") }
        let cal = Calendar.current
        let start = cal.date(byAdding: .hour, value: -12, to: fromDay)!
        let end = min(cal.date(byAdding: .day, value: 1, to: toDay)!, Date())
        let window = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        var samples: [String: [[Any]]] = [:]
        var bp: [String: (sys: Double?, dia: Double?)] = [:]
        for (id, key, unit) in quantities {
            let found = try await read(HKQuantityType(id), window)
            for case let q as HKQuantitySample in found {
                var v = q.quantity.doubleValue(for: unit)
                let t = local.string(from: q.startDate), src = q.sourceRevision.source.name
                switch key {
                case "spo2", "bodyFat": v *= 100
                default: break
                }
                switch key {
                case "temp": samples["temp", default: []].append([local.string(from: q.endDate), v])
                case "steps", "active", "basal", "daylight", "caffeine": samples[key, default: []].append([t, v, src])
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

        for case let c as HKCategorySample in try await read(HKCategoryType(.sleepAnalysis), window) {
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
        for case let c as HKCategorySample in try await read(HKCategoryType(.mindfulSession), window) {
            samples["mindful", default: []].append([local.string(from: c.startDate), local.string(from: c.endDate)])
        }

        var workouts: [[String: Any]] = []
        for case let w as HKWorkout in try await read(HKObjectType.workoutType(), window) {
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
