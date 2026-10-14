import Foundation
import HealthKit

/// Saves what the person logs in Baseline to Apple Health, only once they turn that on in Settings (HealthOut in index.html
/// decides what goes in and asks for it here). Every sample carries the entry's id under `BaselineID`, so saving an entry again
/// first removes what was saved for it, and deleting an entry removes its samples. The sync skips the app's own samples when
/// reading (HealthReader), so nothing is counted twice.
final class HealthWriter {
    static let shared = HealthWriter()
    static let idKey = "BaselineID"
    private let store = HKHealthStore()

    private let types: [HKSampleType] = [
        HKQuantityType(.dietaryWater), HKQuantityType(.dietaryEnergyConsumed), HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryCarbohydrates), HKQuantityType(.dietaryFatTotal), HKQuantityType(.dietaryFiber),
        HKQuantityType(.bodyMass), HKQuantityType(.bodyFatPercentage), HKQuantityType(.waistCircumference),
        HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.distanceCycling), HKCategoryType(.sleepAnalysis),
    ]

    private let local: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()
    private func date(_ v: Any?) -> Date? {
        guard let s = v as? String, s.count >= 16 else { return nil }
        return local.date(from: String(s.prefix(16)))
    }
    private func number(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

    /// Asks for permission to write (the Health sheet shows only what hasn't been answered yet). True if writing anything is allowed.
    func authorize() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: Set(types), read: [])
        } catch {
            log.error("health write authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        return types.contains { store.authorizationStatus(for: $0) == .sharingAuthorized }
    }

    private func allowed(_ t: HKObjectType) -> Bool { store.authorizationStatus(for: t) == .sharingAuthorized }

    /// Saves the page's entries, replacing anything saved before under the same ids. Returns the ids saved and the ids that weren't.
    func save(_ items: [[String: Any]]) async -> (saved: [String], failed: [String]) {
        guard HKHealthStore.isHealthDataAvailable() else { return ([], items.compactMap { $0["id"] as? String }) }
        var saved: [String] = [], failed: [String] = []
        let ids = items.compactMap { $0["id"] as? String }
        await delete(ids)
        for item in items {
            guard let id = item["id"] as? String else { continue }
            do {
                try await save(item, id: id)
                saved.append(id)
            } catch {
                log.error("health write failed for \(item["kind"] as? String ?? "?", privacy: .public): \(error.localizedDescription, privacy: .public)")
                failed.append(id)
            }
        }
        return (saved, failed)
    }

    private struct Skipped: Error {}

    private func save(_ item: [String: Any], id: String) async throws {
        let meta: [String: Any] = [Self.idKey: id]
        func quantity(_ t: HKQuantityTypeIdentifier, _ v: Double?, _ unit: HKUnit, _ at: Date, _ extra: [String: Any] = [:]) -> HKQuantitySample? {
            guard let v, v > 0, allowed(HKQuantityType(t)) else { return nil }
            return HKQuantitySample(type: HKQuantityType(t), quantity: HKQuantity(unit: unit, doubleValue: v), start: at, end: at, metadata: meta.merging(extra) { a, _ in a })
        }
        switch item["kind"] as? String {
        case "water":
            guard let at = date(item["at"]), let s = quantity(.dietaryWater, number(item["ml"]), .literUnit(with: .milli), at) else { throw Skipped() }
            try await store.save(s)
        case "food":
            guard let at = date(item["at"]) else { throw Skipped() }
            let name: [String: Any] = [HKMetadataKeyFoodType: item["name"] as? String ?? "Food"]
            let samples = [
                quantity(.dietaryEnergyConsumed, number(item["kcal"]), .kilocalorie(), at, name),
                quantity(.dietaryProtein, number(item["p"]), .gram(), at, name),
                quantity(.dietaryCarbohydrates, number(item["c"]), .gram(), at, name),
                quantity(.dietaryFatTotal, number(item["f"]), .gram(), at, name),
                quantity(.dietaryFiber, number(item["fiber"]), .gram(), at, name),
            ].compactMap { $0 }
            guard !samples.isEmpty else { throw Skipped() }
            try await store.save(samples)
        case "body":
            guard let at = date(item["at"]) else { throw Skipped() }
            let samples = [
                quantity(.bodyMass, number(item["kg"]), .gramUnit(with: .kilo), at),
                quantity(.bodyFatPercentage, number(item["fat"]).map { $0 / 100 }, .percent(), at),
                quantity(.waistCircumference, number(item["waistCm"]), .meterUnit(with: .centi), at),
            ].compactMap { $0 }
            guard !samples.isEmpty else { throw Skipped() }
            try await store.save(samples)
        case "nap":
            let t = HKCategoryType(.sleepAnalysis)
            guard allowed(t), let a = date(item["start"]), let b = date(item["end"]), b > a else { throw Skipped() }
            try await store.save(HKCategorySample(type: t, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, start: a, end: b, metadata: meta))
        case "workout":
            guard allowed(HKObjectType.workoutType()), let a = date(item["start"]), let b = date(item["end"]), b > a else { throw Skipped() }
            let type = Self.activity(item["type"] as? String ?? "")
            let config = HKWorkoutConfiguration()
            config.activityType = type
            let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
            try await builder.beginCollection(at: a)
            var samples: [HKSample] = []
            if let kcal = number(item["kcal"]), kcal > 0, allowed(HKQuantityType(.activeEnergyBurned)) {
                samples.append(HKQuantitySample(type: HKQuantityType(.activeEnergyBurned), quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal), start: a, end: b, metadata: meta))
            }
            if let km = number(item["km"]), km > 0 {
                let t: HKQuantityTypeIdentifier = type == .cycling ? .distanceCycling : .distanceWalkingRunning
                if allowed(HKQuantityType(t)) {
                    samples.append(HKQuantitySample(type: HKQuantityType(t), quantity: HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: km), start: a, end: b, metadata: meta))
                }
            }
            if !samples.isEmpty { try await builder.addSamples(samples) }
            var wm = meta
            if let name = item["name"] as? String, !name.isEmpty { wm[HKMetadataKeyWorkoutBrandName] = name }
            try await builder.addMetadata(wm)
            try await builder.endCollection(at: b)
            _ = try await builder.finishWorkout()
        default:
            throw Skipped()
        }
    }

    /// Deletes what was saved for these entries, in every type Baseline writes.
    func delete(_ ids: [String]) async {
        guard !ids.isEmpty, HKHealthStore.isHealthDataAvailable() else { return }
        let match = HKQuery.predicateForObjects(withMetadataKey: Self.idKey, allowedValues: ids)
        for t in types where allowed(t) { await deleteObjects(t, match) }
    }

    /// Deletes everything Baseline ever saved to Health (from this app, carrying an entry id).
    func deleteAll() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let match = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForObjects(withMetadataKey: Self.idKey),
        ])
        for t in types where allowed(t) { await deleteObjects(t, match) }
    }

    private func deleteObjects(_ t: HKObjectType, _ predicate: NSPredicate) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            store.deleteObjects(of: t, predicate: predicate) { _, _, error in
                if let error, (error as? HKError)?.code != .errorNoData {
                    log.error("health delete failed: \(error.localizedDescription, privacy: .public)")
                }
                cont.resume()
            }
        }
    }

    /// The page's workout types ("Strength", "Running", HealthKit names it read earlier…) as HealthKit activities.
    static func activity(_ name: String) -> HKWorkoutActivityType {
        let n = name.lowercased()
        let table: [(String, HKWorkoutActivityType)] = [
            ("strength", .traditionalStrengthTraining), ("functional", .functionalStrengthTraining), ("hiit", .highIntensityIntervalTraining),
            ("high intensity", .highIntensityIntervalTraining), ("run", .running), ("walk", .walking), ("hik", .hiking), ("cycl", .cycling),
            ("ride", .cycling), ("bike", .cycling), ("swim", .swimming), ("row", .rowing), ("ellip", .elliptical), ("yoga", .yoga),
            ("pilates", .pilates), ("stretch", .flexibility), ("mobility", .flexibility), ("core", .coreTraining), ("dance", .cardioDance),
            ("box", .boxing), ("climb", .climbing), ("stair", .stairClimbing), ("soccer", .soccer), ("football", .soccer),
            ("basketball", .basketball), ("tennis", .tennis), ("ski", .downhillSkiing), ("snowboard", .snowboarding),
        ]
        return table.first { n.contains($0.0) }?.1 ?? .other
    }
}
