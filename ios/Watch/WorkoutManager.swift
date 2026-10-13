import Foundation
import HealthKit
import WatchKit

/// Runs the HealthKit workout session: live heart rate and energy while you train, and the workout saved to Health at the end
/// when "Save to Apple Health" is on in the phone's Settings (otherwise the session is discarded; the phone keeps its own log).
@MainActor
final class WorkoutManager: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    let store = HKHealthStore()
    /// Set from the phone's context: whether finished workouts go to Apple Health.
    static let saveKey = "baseline.healthWrite"
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    @Published private(set) var running = false
    @Published private(set) var paused = false
    @Published private(set) var startDate: Date?
    @Published private(set) var heartRate: Double = 0
    @Published private(set) var avgHeartRate: Double = 0
    @Published private(set) var maxHeartRate: Double = 0
    @Published private(set) var kcal: Double = 0
    @Published private(set) var meters: Double = 0
    @Published private(set) var activity: HKWorkoutActivityType = .traditionalStrengthTraining

    func authorize() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKObjectType.workoutType()]
        try? await store.requestAuthorization(toShare: share, read: read)
    }

    func start(_ type: HKWorkoutActivityType, outdoor: Bool = false) async {
        guard !running else { return }
        await authorize()
        let config = HKWorkoutConfiguration()
        config.activityType = type
        config.locationType = outdoor ? .outdoor : .indoor
        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: config)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            s.delegate = self
            b.delegate = self
            session = s; builder = b
            activity = type
            heartRate = 0; avgHeartRate = 0; maxHeartRate = 0; kcal = 0; meters = 0
            let now = Date()
            startDate = now
            s.startActivity(with: now)
            try await b.beginCollection(at: now)
            running = true; paused = false
            wlog.notice("watch: workout started")
        } catch {
            wlog.error("watch: workout could not start: \(error.localizedDescription, privacy: .public)")
            // without HealthKit (simulator, refused) the strength tracker still works, just without heart rate
            startDate = Date(); running = true; paused = false
        }
    }

    func togglePause() {
        guard let s = session else { paused.toggle(); return }
        if paused { s.resume() } else { s.pause() }
    }

    /// Ends the session and, when saving is on, saves the workout to Health. Returns what the phone needs for its log.
    func end() async -> (avgHr: Int?, maxHr: Int?, kcal: Int?) {
        let summary = (avgHr: avgHeartRate > 0 ? Int(avgHeartRate.rounded()) : nil, maxHr: maxHeartRate > 0 ? Int(maxHeartRate.rounded()) : nil, kcal: kcal > 0 ? Int(kcal.rounded()) : nil)
        running = false; paused = false
        guard let s = session, let b = builder else { return summary }
        s.end()
        do {
            try await b.endCollection(at: Date())
            if UserDefaults.standard.bool(forKey: Self.saveKey) { _ = try await b.finishWorkout() } else { b.discardWorkout() }
        } catch {
            wlog.error("watch: workout could not be saved: \(error.localizedDescription, privacy: .public)")
        }
        session = nil; builder = nil
        return summary
    }

    /// Ends without saving anything to Health.
    func discard() {
        session?.end()
        builder?.discardWorkout()
        session = nil; builder = nil
        running = false; paused = false
    }

    // MARK: delegates (called off the main thread)

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in self.paused = toState == .paused }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        var hr: (Double, Double, Double)?
        var energy: Double?, dist: Double?
        for type in collectedTypes {
            guard let q = type as? HKQuantityType, let st = workoutBuilder.statistics(for: q) else { continue }
            switch q {
            case HKQuantityType(.heartRate):
                hr = (st.mostRecentQuantity()?.doubleValue(for: bpm) ?? 0, st.averageQuantity()?.doubleValue(for: bpm) ?? 0, st.maximumQuantity()?.doubleValue(for: bpm) ?? 0)
            case HKQuantityType(.activeEnergyBurned):
                energy = st.sumQuantity()?.doubleValue(for: .kilocalorie())
            case HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling):
                dist = st.sumQuantity()?.doubleValue(for: .meter())
            default: break
            }
        }
        Task { @MainActor in
            if let hr { self.heartRate = hr.0; self.avgHeartRate = hr.1; self.maxHeartRate = max(self.maxHeartRate, hr.2) }
            if let energy { self.kcal = energy }
            if let dist { self.meters = dist }
        }
    }
}
