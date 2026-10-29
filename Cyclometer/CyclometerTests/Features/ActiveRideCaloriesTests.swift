import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// W23's live estimate (#465): one point a minute of recording time, from the function, track and
/// rider the ride's Health workout is written with.
@MainActor
@Suite("ActiveRideFeature — active calories")
struct ActiveRideCaloriesTests {

    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
    private static let dateOfBirth = DateComponents(year: 1980, month: 6, day: 1)
    private static let rider = RideEnergy.Rider(kilograms: 75, dateOfBirth: dateOfBirth, sex: .male, on: fixedNow)

    /// A store whose clock the test moves, as the HR dropout suite's: the track's timestamps, and
    /// so the estimate, come from it.
    private func makeStore(
        now: LockIsolated<Date>,
        healthKitClient: HealthKitClient = .testValue,
        persistenceClient: PersistenceClient = .testValue,
        _ state: @autoclosure () -> ActiveRideFeature.State = ActiveRideFeature.State(recordingState: .active)
    ) -> TestStoreOf<ActiveRideFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            let store = TestStore(initialState: state()) {
                ActiveRideFeature()
            } withDependencies: {
                $0.continuousClock = TestClock()
                $0.hapticsClient = .testValue
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
                $0.locationClient = .testValue
                $0.healthKitClient = healthKitClient
                $0.persistenceClient = persistenceClient
                $0.date = DateGenerator { now.value }
                $0.uuid = .incrementing
                $0.defaultFileStorage = storage
            }
            store.exhaustivity = .off
            return store
        }
    }

    private static func fix(at date: Date) -> LocationUpdate {
        LocationUpdate(
            coordinate: Coordinate(latitude: 43.0731 + date.timeIntervalSince(fixedNow) * 0.000_07, longitude: -89.4012),
            altitude: 280,
            speed: 8.5,
            horizontalAccuracy: 5,
            heading: 0,
            timestamp: date
        )
    }

    /// `seconds` riding seconds, each with a fresh fix, moving `now` on as the 1 Hz timer would.
    private func ride(_ store: TestStoreOf<ActiveRideFeature>, now: LockIsolated<Date>, seconds: Int) async {
        for _ in 0..<seconds {
            now.withValue { $0 += 1 }
            await store.send(.locationUpdated(Self.fix(at: now.value)))
            await store.send(.elapsedTick)
        }
    }

    @Test("Health's body mass, date of birth and sex are read at the start, as the workout reads them")
    func riderFetchedAtStart() async {
        let now = LockIsolated(Self.fixedNow)
        let store = makeStore(now: now, healthKitClient: .mock(
            dateOfBirth: Self.dateOfBirth, bodyMassKilograms: 75, biologicalSex: .male
        ))

        await store.send(.task)
        await store.receive(\.energyRiderFetched) {
            $0.energyRider = .rider(RideEnergy.Rider(kilograms: 75, age: 46, sex: .male))
        }
        await store.skipInFlightEffects(strict: false)
    }

    @Test("With no body mass there is no estimate")
    func noBodyMassNoEstimate() async {
        let now = LockIsolated(Self.fixedNow)
        let store = makeStore(now: now)

        await store.send(.task)
        await store.receive(\.energyRiderFetched) {
            $0.energyRider = .noBodyMass
        }
        await store.send(.trackRecorder(.startRecording))
        await ride(store, now: now, seconds: 60)
        await store.skipInFlightEffects(strict: false)

        #expect(store.state.calories.isEmpty)
        #expect(store.state.caloriesMetrics.emptyReason == "Add your weight in the Health app to estimate active calories.")
    }

    @Test("One point a minute, and the last is the energy the ride's Health workout is written with")
    func minuteSeriesMatchesHealthWorkout() async throws {
        let now = LockIsolated(Self.fixedNow)
        let flushed = LockIsolated<[TrackPointDTO]>([])
        let store = makeStore(
            now: now,
            persistenceClient: .mock(onFlush: { points in flushed.withValue { $0 += points } })
        )

        await store.send(.energyRiderFetched(Self.rider))
        await store.send(.trackRecorder(.startRecording))
        await ride(store, now: now, seconds: 59)
        await store.skipInFlightEffects(strict: false)
        #expect(store.state.calories.isEmpty)

        await ride(store, now: now, seconds: 1)
        await store.receive(\.caloriesEstimated)
        #expect(store.state.calories.map(\.rideSeconds) == [60])

        await ride(store, now: now, seconds: 60)
        await store.receive(\.caloriesEstimated)
        #expect(store.state.calories.map(\.rideSeconds) == [60, 120])
        await store.skipInFlightEffects(strict: false)

        // What the recorder handed the store: the track the workout reads back, in time order as
        // the store returns it (a flush can overtake a second's append).
        let recorded = (flushed.value + (await store.dependencies.rideDataBuffer.drainForFlush()))
            .sorted { $0.timestamp < $1.timestamp }
        #expect(recorded == store.state.calorieTrack)
        let ride = OwedHealthWorkout(
            rideId: store.state.rideId, startedAt: Self.fixedNow, endedAt: now.value,
            distanceMeters: store.state.distanceMeters, movingSeconds: TimeInterval(store.state.elapsedSeconds)
        )
        let written = LockIsolated<[RideWorkout]>([])
        try await withDependencies {
            $0.persistenceClient = .mock(trackPoints: [ride.rideId: recorded])
            $0.healthKitClient = .mock(
                dateOfBirth: Self.dateOfBirth, bodyMassKilograms: 75, biologicalSex: .male,
                onSaveWorkout: { workout in written.withValue { $0.append(workout) } }
            )
        } operation: {
            try await RideHealthWorkout.write(ride)
        }
        let energy = try #require(written.value.first?.activeEnergyKilocalories)
        #expect(energy > 0)
        #expect(store.state.calories.last?.kilocalories == energy)
    }

    @Test("A pause holds the estimate, and the series goes on after the resume")
    func pauseHoldsTheEstimate() async {
        let now = LockIsolated(Self.fixedNow)
        let store = makeStore(now: now)

        await store.send(.energyRiderFetched(Self.rider))
        await store.send(.trackRecorder(.startRecording))
        await ride(store, now: now, seconds: 60)
        await store.receive(\.caloriesEstimated)
        let held = store.state.calories

        await store.send(.pauseTapped)
        await ride(store, now: now, seconds: 90)
        await store.skipInFlightEffects(strict: false)
        #expect(store.state.calories == held)

        await store.send(.resumeTapped)
        await ride(store, now: now, seconds: 60)
        await store.receive(\.caloriesEstimated)
        #expect(store.state.calories.map(\.rideSeconds) == [60, 120])
        #expect(store.state.calories[1].kilocalories > held[0].kilocalories)
        await store.skipInFlightEffects(strict: false)
    }

    @Test("Health answering after the first minute still gives that minute")
    func lateRiderRebuildsTheFirstMinute() async throws {
        let now = LockIsolated(Self.fixedNow)
        let store = makeStore(now: now)

        await store.send(.trackRecorder(.startRecording))
        await ride(store, now: now, seconds: 75)
        await store.send(.energyRiderFetched(Self.rider))
        await store.receive(\.caloriesRebuilt)
        #expect(store.state.calories == CalorieSeries.rebuild(
            track: store.state.calorieTrack, through: 75, rider: try #require(Self.rider)
        ))
        #expect(store.state.calories.map(\.rideSeconds) == [60])
        await store.skipInFlightEffects(strict: false)
    }

    @Test("A ride resumed after a kill rebuilds its series from the saved track")
    func resumeRebuildsFromSavedTrack() async throws {
        let rideId = UUID()
        // Ten minutes before the kill, ending an hour before the relaunch.
        let saved = (0..<600).map { second in
            TrackPointDTO(
                rideId: rideId,
                timestamp: Self.fixedNow.addingTimeInterval(Double(second) - 3_600),
                latitude: 43 + Double(second) * 0.000_07, longitude: -89.4,
                altitudeMeters: 280, horizontalAccuracyMeters: 5,
                speedMPS: 8.5, speedSource: .gps,
                heartRateSource: .none
            )
        }
        let resumed = ActiveRideFeature.State(resuming: RideSummaryUpdate(
            rideId: rideId, recordingState: .active,
            durationSeconds: 600, distanceMeters: 5_100, averageSpeedMPS: 8.5, maxSpeedMPS: 8.5
        ))
        let now = LockIsolated(Self.fixedNow)
        let store = makeStore(
            now: now,
            healthKitClient: .mock(bodyMassKilograms: 75),
            persistenceClient: .mock(trackPoints: [rideId: saved]),
            resumed
        )

        await store.send(.task)
        await store.receive(\.caloriesRebuilt)
        let rider = RideEnergy.Rider(kilograms: 75)
        #expect(store.state.calories == CalorieSeries.rebuild(track: saved, through: 600, rider: rider))
        #expect(store.state.calories.count == 10)
        #expect(store.state.calorieTrack == saved)

        // And the minute after the resume adds to it, over the whole ride.
        await ride(store, now: now, seconds: 60)
        await store.receive(\.caloriesEstimated)
        #expect(store.state.calories.map(\.rideSeconds).last == 660)
        #expect(store.state.calorieTrack.count == 660)
        await store.skipInFlightEffects(strict: false)
    }

    @Test("A resumed ride's minute waits for its saved track, and none means no minutes before the resume")
    func liveMinuteWaitsForSavedTrack() async {
        let resumed = ActiveRideFeature.State(resuming: RideSummaryUpdate(
            rideId: UUID(), recordingState: .active,
            durationSeconds: 30, distanceMeters: 255, averageSpeedMPS: 8.5, maxSpeedMPS: 8.5
        ))
        let now = LockIsolated(Self.fixedNow)
        let store = makeStore(now: now, resumed)

        await store.send(.energyRiderFetched(Self.rider))
        await store.send(.trackRecorder(.startRecording))
        await ride(store, now: now, seconds: 30)
        await store.skipInFlightEffects(strict: false)
        #expect(store.state.calories.isEmpty)

        // The read failed: no made-up minutes before the resume, even when Health answers after it.
        await store.send(.calorieTrackSeeded([])) {
            $0.isSavedTrackPending = false
            $0.isSavedTrackMissing = true
        }
        await store.send(.energyRiderFetched(Self.rider))
        await store.skipInFlightEffects(strict: false)
        #expect(store.state.calories.isEmpty)

        // The series starts at the resume's next minute.
        await ride(store, now: now, seconds: 60)
        await store.receive(\.caloriesEstimated)
        #expect(store.state.calories.map(\.rideSeconds) == [120])
        await store.skipInFlightEffects(strict: false)
    }
}
