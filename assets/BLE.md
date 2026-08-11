# Cyclometer — BLE Integration Specification
**Version:** 1.1  
**Date:** 2026-05-21  
**Updated:** 2026-05-22 — Sensor role model: speed/cadence split at pairing time; `SensorRole` replaces `SensorType.speedCadence`; `SpeedFeature` and `CadenceFeature` replace `SpeedCadenceFeature`  
**Status:** Draft — Pending M2 Engineering Spike Validation  
**Author:** Brian (UX Design) + Claude (Specification)  
**Companion Documents:** `PRD.md §9`, `DataModel.md`, `TCA.md`

---

## 1. Overview

Cyclometer communicates with all external sensors over **Bluetooth Low Energy (BLE)** via Apple's `CoreBluetooth` framework, wrapped in TCA-compatible `BluetoothClient` dependency clients. All BLE operations are abstracted behind protocol boundaries so that every feature is fully testable without physical hardware.

Four sensor roles are targeted for MVP. Speed and cadence use the same underlying BLE profile (CSC `0x1816`) but are treated as independent roles assigned by the rider at pairing time.

| Role | Protocol | Standard | Priority |
|---|---|---|---|
| Radar | Garmin Cycling Radar GATT | Garmin proprietary (publicly documented) | MVP |
| Heart Rate | Heart Rate Profile | Bluetooth SIG `0x180D` | MVP |
| Speed | Cycling Speed and Cadence (CSC) Profile | Bluetooth SIG `0x1816` | MVP |
| Cadence | Cycling Speed and Cadence (CSC) Profile | Bluetooth SIG `0x1816` | MVP |
| Power | Cycling Power Profile | Bluetooth SIG `0x1818` | Phase 3 |

**Speed and Cadence are separate roles, not a single combined sensor type.** A single physical device may serve both roles simultaneously (combo sensor), or a rider may use two separate CSC devices — one for each role. The underlying BLE profile (`0x1816`) and characteristic (`0x2A5B`) is the same in all cases; the CSC payload flags byte (`hasWheelData`, `hasCrankData`) determines which data fields are present in each notification.

---

## 2. Architecture — BLE in TCA

BLE in Cyclometer is structured as a **long-lived `AsyncStream` effect** within TCA, not a delegate callback pattern. Each sensor category has its own `DependencyClient`.

```
BluetoothClient (dependency)
    ├── scan() → AsyncStream<DiscoveredPeripheral>
    ├── connect(id:) → AsyncStream<ConnectionEvent>
    ├── notifications(for characteristicId:) → AsyncStream<Data>
    └── disconnect(id:)

Reducers consume these streams via .run { send in
    for await event in client.connect(peripheralId) { send(.connectionChanged(event)) }
}
```

### Why AsyncStream, not Combine?

- Composable Architecture uses structured concurrency natively
- `AsyncStream` integrates cleanly with `Effect.run` and TCA's `TestStore`
- No Combine cancellable management required — Task cancellation handles cleanup

---

## 3. Garmin Varia Radar — RTL515 / RCT715

### 3.1 GATT Service and Characteristic UUIDs

> **Validation required in M2 spike.** The UUIDs below are sourced from the Garmin BLE specification and open-source implementations (pycycling RDR module). They must be verified against physical hardware before M4 freeze.

| Name | UUID | Type |
|---|---|---|
| Cycling Radar Service | `6A4E3200-667B-11E3-949A-0800200C9A66` | Service |
| Radar Capability | `6A4E3201-667B-11E3-949A-0800200C9A66` | Characteristic — Read |
| Radar Alert | `6A4E3202-667B-11E3-949A-0800200C9A66` | Characteristic — Notify |

The unit may also expose the Battery Service (§14).

### 3.2 Alert Payload Parsing

The Radar Alert characteristic delivers notifications as a variable-length byte array.

```
Byte Layout:
┌────────┬─────────────┬───────────────────────────────────────────┐
│ Byte 0 │   Byte 1    │ Bytes 2–N (variable; 4 bytes per vehicle) │
│ Alert  │  Vehicle    │        Vehicle Records                    │
│ Level  │   Count     │                                           │
└────────┴─────────────┴───────────────────────────────────────────┘

Alert Level (Byte 0):
  0x00 = Clear (L0)
  0x01 = Advisory (L1)
  0x02 = Caution (L2)
  0x03 = Danger (L3)

Vehicle Count (Byte 1): 0x00–0x08

Vehicle Record (4 bytes each):
  Byte 0: Vehicle index (0-based)
  Byte 1: Distance (meters; 0–254; 255 = out of range)
  Byte 2: Closing speed (km/h; signed Int8; positive = approaching)
  Byte 3: Alert sub-level for this specific vehicle (0–3)
```

Swift parsing:
```swift
struct RadarAlertPayload: Sendable {
    let alertLevel: AlertLevel
    let vehicles: [RadarVehicle]

    init?(data: Data) {
        guard data.count >= 2 else { return nil }
        guard let level = AlertLevel(rawValue: Int(data[0])) else { return nil }
        self.alertLevel = level

        let vehicleCount = Int(data[1])
        guard data.count >= 2 + vehicleCount * 4 else { return nil }

        self.vehicles = (0..<vehicleCount).compactMap { i in
            let offset = 2 + i * 4
            guard offset + 3 < data.count else { return nil }
            let index = Int(data[offset])
            let distance = Double(data[offset + 1])
            let closingSpeed = Double(Int8(bitPattern: data[offset + 2]))
            guard let subLevel = AlertLevel(rawValue: Int(data[offset + 3])) else { return nil }
            return RadarVehicle(
                vehicleIndex: index,
                distanceMeters: distance,
                closingSpeedKph: closingSpeed,
                alertLevel: subLevel,
                estimatedSize: .unknown
            )
        }
    }
}
```

### 3.3 Radar Capability Characteristic

Read once on connect to determine device capabilities.

```swift
struct RadarCapabilityPayload: Sendable {
    let maximumVehicleCount: Int          // Typically 8 for RTL515/RCT715
    let supportsCameraControl: Bool       // true for RCT715 (has dashcam)
    let supportsAmplitudeData: Bool       // OQ11 — validate in M2 spike
    
    init?(data: Data) {
        guard data.count >= 1 else { return nil }
        self.maximumVehicleCount = Int(data[0] & 0x0F)
        self.supportsCameraControl = (data[0] & 0x10) != 0
        self.supportsAmplitudeData = (data[0] & 0x20) != 0  // Hypothetical; confirm in M2
    }
}
```

### 3.4 Alert Level → Cyclometer Level Mapping

| Varia Payload Byte 0 | Cyclometer AlertLevel | Action Trigger |
|---|---|---|
| `0x00` | `.clear` | All Clear tone (if prior state was L2/L3) |
| `0x01` | `.advisory` | L1 haptic |
| `0x02` | `.caution` | L2 haptic + Warning tone |
| `0x03` | `.danger` | L3 Core Haptics + Danger tone |

Alert level changes are debounced with a **3-second minimum re-trigger window** per level to prevent alert fatigue on busy roads.

---

## 4. BLE Heart Rate Profile

### 4.1 GATT

| Name | UUID | Type |
|---|---|---|
| Heart Rate Service | `0x180D` | Service |
| Heart Rate Measurement | `0x2A37` | Characteristic — Notify |
| Body Sensor Location | `0x2A38` | Characteristic — Read (optional) |

The strap may also expose the Battery Service (§14).

### 4.2 HR Measurement Payload

The HR Measurement characteristic uses a flags byte to indicate 8-bit vs 16-bit BPM encoding.

```swift
struct HRMeasurementPayload: Sendable {
    let bpm: Int
    let rrIntervals: [Double]             // milliseconds; present if bit 4 of flags set
    // RR intervals not used in MVP; parsed for potential Phase 2 HRV feature

    init?(data: Data) {
        guard data.count >= 2 else { return nil }
        let flags = data[0]
        let is16Bit = (flags & 0x01) != 0

        if is16Bit {
            guard data.count >= 3 else { return nil }
            self.bpm = Int(data[1]) | (Int(data[2]) << 8)
        } else {
            self.bpm = Int(data[1])
        }

        // Parse RR intervals if present (bits 4 set in flags)
        var intervals: [Double] = []
        if (flags & 0x10) != 0 {
            let startOffset = is16Bit ? 3 : 2
            var offset = startOffset
            while offset + 1 < data.count {
                let raw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
                intervals.append(Double(raw) / 1024.0 * 1000.0)  // Convert to ms
                offset += 2
            }
        }
        self.rrIntervals = intervals
    }
}
```

---

## 5. BLE Cycling Speed and Cadence (CSC) Profile

### 5.0 Role Assignment at Pairing (S11)

All CSC sensors (`0x1816`) go through role assignment when paired in S11 (Device Management) or S02 (Onboarding — Sensor Pairing).

**Pairing flow:**

```
1. App discovers peripheral advertising CSC service (0x1816)
2. App connects and reads CSC Feature characteristic (0x2A5C)
3. CSCCapabilities parsed from feature flags

   If requiresRoleSelection == true (supports both wheel + crank):
     → Present role sheet to rider:
         "What should this sensor do?"
         [Speed]   [Cadence]   [Both]
     → Rider selects role(s)

   If requiresRoleSelection == false (single capability):
     → Auto-assign: wheel-only → Speed; crank-only → Cadence
     → No prompt shown

4. Store PairedSensor record(s) in Preferences:
   - Role .speed  → pairedSpeedSensorId = peripheral.id
   - Role .cadence → pairedCadenceSensorId = peripheral.id
   - Role .both   → both fields set to same peripheral.id
```

**Key rules:**
- The same physical device (same `CBPeripheral.identifier`) may fill both the Speed and Cadence roles simultaneously. Both `SpeedFeature` and `CadenceFeature` will connect to and subscribe to the same peripheral; each reads only its relevant data fields from the shared CSC notification stream.
- When a dedicated speed sensor and a combo sensor are both paired, and the combo is assigned Cadence-only, `SpeedFeature` connects to the dedicated sensor and `CadenceFeature` connects to the combo sensor. Both are active simultaneously.
- Role can be reassigned in S11 without re-pairing; the peripheral UUID is retained.

### 5.1 GATT

| Name | UUID | Type |
|---|---|---|
| Cycling Speed and Cadence Service | `0x1816` | Service |
| CSC Measurement | `0x2A5B` | Characteristic — Notify |
| CSC Feature | `0x2A5C` | Characteristic — Read |
| Sensor Location | `0x2A5D` | Characteristic — Read |

The sensor may also expose the Battery Service (§14).

### 5.2 CSC Measurement Payload

```swift
struct CSCMeasurementPayload: Sendable {
    // Wheel revolution data (speed)
    let cumulativeWheelRevolutions: UInt32?
    let lastWheelEventTime: UInt16?        // 1/1024s units

    // Crank revolution data (cadence)
    let cumulativeCrankRevolutions: UInt16?
    let lastCrankEventTime: UInt16?        // 1/1024s units

    init?(data: Data) {
        guard data.count >= 1 else { return nil }
        let flags = data[0]
        let hasWheelData = (flags & 0x01) != 0
        let hasCrankData = (flags & 0x02) != 0

        var offset = 1
        if hasWheelData {
            guard data.count >= offset + 6 else { return nil }
            cumulativeWheelRevolutions = UInt32(data[offset])
                | UInt32(data[offset + 1]) << 8
                | UInt32(data[offset + 2]) << 16
                | UInt32(data[offset + 3]) << 24
            lastWheelEventTime = UInt16(data[offset + 4]) | UInt16(data[offset + 5]) << 8
            offset += 6
        } else {
            cumulativeWheelRevolutions = nil
            lastWheelEventTime = nil
        }

        if hasCrankData {
            guard data.count >= offset + 4 else { return nil }
            cumulativeCrankRevolutions = UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
            lastCrankEventTime = UInt16(data[offset + 2]) | UInt16(data[offset + 3]) << 8
        } else {
            cumulativeCrankRevolutions = nil
            lastCrankEventTime = nil
        }
    }
}
```

### 5.3 Speed and Cadence Calculation

Speed and cadence are derived from successive measurement pairs using cumulative revolution delta and time delta. Each calculator is independent — `SpeedFeature` maintains its own wheel calculator state; `CadenceFeature` maintains its own crank calculator state. When one peripheral serves both roles, each feature holds a separate calculator instance reading from the same notification stream.

```swift
/// Independent calculator instances — one per role, not one per peripheral.
/// SpeedFeature holds CSCSpeedCalculator.
/// CadenceFeature holds CSCCadenceCalculator.
struct CSCCalculator: Sendable {  // shared base — specialised below
    var previousWheelRevs: UInt32 = 0
    var previousWheelEventTime: UInt16 = 0
    var previousCrankRevs: UInt16 = 0
    var previousCrankEventTime: UInt16 = 0
    var wheelCircumferenceMM: Int                // From UserProfile

    /// Returns speed in m/s. Returns nil if delta is invalid (sensor glitch, rollover edge case).
    mutating func updateSpeed(revs: UInt32, eventTime: UInt16) -> Double? {
        let revDelta = rolloverSafeSubtract32(revs, previousWheelRevs)
        let timeDelta = rolloverSafeSubtract16(eventTime, previousWheelEventTime)
        previousWheelRevs = revs
        previousWheelEventTime = eventTime

        guard timeDelta > 0, revDelta > 0 else { return nil }
        let timeSec = Double(timeDelta) / 1024.0
        let distanceM = Double(revDelta) * Double(wheelCircumferenceMM) / 1000.0
        return distanceM / timeSec
    }

    /// Returns cadence in RPM. Returns nil if delta is invalid.
    mutating func updateCadence(revs: UInt16, eventTime: UInt16) -> Double? {
        let revDelta = rolloverSafeSubtract16(revs, previousCrankRevs)
        let timeDelta = rolloverSafeSubtract16(eventTime, previousCrankEventTime)
        previousCrankRevs = revs
        previousCrankEventTime = eventTime

        guard timeDelta > 0 else { return nil }
        let timeSec = Double(timeDelta) / 1024.0
        return Double(revDelta) / timeSec * 60.0
    }

    private func rolloverSafeSubtract32(_ current: UInt32, _ previous: UInt32) -> UInt32 {
        current >= previous ? current - previous : UInt32.max - previous + current + 1
    }

    private func rolloverSafeSubtract16(_ current: UInt16, _ previous: UInt16) -> UInt16 {
        current >= previous ? current - previous : UInt16.max - previous + current + 1
    }
}
```

---

## 6. Connection State Machine

Each BLE peripheral (Radar, HR, CSC) manages its own connection state independently. The state machine is identical for all sensor types.

```
                    ┌──────────────┐
          ┌────────▶│ disconnected │◀────────────────────────┐
          │         └──────┬───────┘                         │
          │                │ scan()                          │
          │ timeout/       ▼                                 │
          │ user      ┌─────────┐                       connection
          │ unpair    │ scanning │                       permanently
          │           └────┬────┘                       lost / user
          │                │ peripheral discovered           unpaired
          │                ▼                                 │
          │         ┌────────────┐                           │
          │         │ connecting │                           │
          │         └─────┬──────┘                          │
          │ failed        │ connected                        │
          └───────────────┼──────────────────────────────────┘
                          ▼
                   ┌───────────┐
                   │ connected │ ──▶ enable notifications
                   └─────┬─────┘
                         │ notifications enabled
                         ▼
                  ┌─────────────┐
                  │   active    │ ──▶ data streaming
                  └──────┬──────┘
                         │ signal loss
                         ▼
                  ┌──────────────┐
                  │ reconnecting │ (exponential backoff)
                  └──────┬───────┘
                         │ reconnected
                         ▼
                  ┌─────────────┐
                  │   active    │
                  └─────────────┘
```

### 6.1 Reconnection Policy (Exponential Backoff)

```swift
struct ReconnectionPolicy: Sendable {
    static let initialDelay: TimeInterval = 1.0
    static let maxDelay: TimeInterval = 30.0
    static let maxAttempts = 10

    var attemptCount: Int = 0

    mutating func nextDelay() -> TimeInterval? {
        guard attemptCount < Self.maxAttempts else { return nil } // Give up
        let delay = min(Self.initialDelay * pow(2.0, Double(attemptCount)), Self.maxDelay)
        attemptCount += 1
        return delay
    }

    mutating func reset() { attemptCount = 0 }
}
```

After `maxAttempts` the sensor is considered lost and transitions to `disconnected`. A non-intrusive banner is shown: "Radar sensor not found — reconnect in Sensors."

### 6.2 Disconnection During Active Ride

| Sensor Role | Consequence | Recovery |
|---|---|---|
| Radar | Sidebar shows "Radar offline" grayed state; L1 advisory haptic fires once | Auto-reconnect (backoff) |
| HR | Source switches to Apple Watch (if available); source badge updates; banner shown | Auto-reconnect (backoff) |
| Speed | Source switches to GPS-derived speed; source badge updates; banner shown | Auto-reconnect (backoff) |
| Cadence | Cadence widget shows "--"; no fallback source available | Auto-reconnect (backoff) |

**Shared peripheral disconnection:** If one peripheral serves both Speed and Cadence roles, disconnection triggers both consequences simultaneously — GPS speed fallback activates and cadence shows "--" — in a single banner: "Speed sensor disconnected — using GPS speed; cadence unavailable."

---

## 7. BluetoothClient Protocol — TCA Dependency

```swift
import Dependencies
import Foundation

/// TCA dependency client for all BLE operations.
/// The live implementation uses CoreBluetooth.
/// The test/preview implementation uses mock data generators.
@DependencyClient
struct BluetoothClient: Sendable {

    // MARK: - Scanning

    /// Start scanning for peripherals advertising the specified service UUIDs.
    var startScan: @Sendable ([CBUUID]) async -> Void = { _ in }

    /// Stop scanning.
    var stopScan: @Sendable () async -> Void = {}

    /// Stream of discovered peripherals. Emits on each new advertisement.
    var discoveredPeripherals: @Sendable () -> AsyncStream<DiscoveredPeripheral> = {
        AsyncStream { _ in }
    }

    // MARK: - Connection

    /// Connect to a peripheral by UUID. Returns a stream of connection events.
    var connect: @Sendable (UUID) -> AsyncStream<BLEConnectionEvent> = { _ in
        AsyncStream { _ in }
    }

    /// Disconnect from a peripheral.
    var disconnect: @Sendable (UUID) async -> Void = { _ in }

    // MARK: - Data

    /// Enable notifications for a characteristic and receive data stream.
    /// peripheralId: UUID of the connected peripheral.
    /// characteristicUUID: the CBUUID of the characteristic to subscribe to.
    var notifications: @Sendable (UUID, CBUUID) -> AsyncStream<Data> = { _, _ in
        AsyncStream { _ in }
    }

    /// One-time read of a characteristic (for capability reads on connect).
    var readCharacteristic: @Sendable (UUID, CBUUID) async throws -> Data = { _, _ in Data() }
}

struct DiscoveredPeripheral: Sendable, Identifiable {
    let id: UUID                          // CBPeripheral.identifier
    let name: String?
    let rssi: Int
    let advertisedServiceUUIDs: [CBUUID]
    var cscCapabilities: CSCCapabilities? // Non-nil for CSC sensors; drives role assignment UI
}

/// Capabilities read from CSC Feature characteristic (0x2A5C) on connect.
struct CSCCapabilities: Sendable {
    let supportsWheelRevolutions: Bool    // bit 0 — can serve Speed role
    let supportsCrankRevolutions: Bool    // bit 1 — can serve Cadence role

    init(featureData: Data) {
        let flags = featureData.first ?? 0
        supportsWheelRevolutions = (flags & 0x01) != 0
        supportsCrankRevolutions = (flags & 0x02) != 0
    }

    /// Role assignment behavior based on capabilities:
    /// - Both true  → ask rider: Speed, Cadence, or Both
    /// - Wheel only → auto-assign Speed; no question asked
    /// - Crank only → auto-assign Cadence; no question asked
    var requiresRoleSelection: Bool { supportsWheelRevolutions && supportsCrankRevolutions }
}

/// The role a BLE peripheral plays in Cyclometer.
/// Speed and Cadence are separate roles even when served by a single physical CSC device.
enum SensorRole: String, Codable, Sendable {
    case radar
    case heartRate
    case speed      // CSC profile — reads wheel revolution data only
    case cadence    // CSC profile — reads crank revolution data only
    case power      // Phase 3
    case unknown
}

enum BLEConnectionEvent: Sendable {
    case connected
    case notificationsEnabled
    case disconnected(reason: BLEDisconnectReason)
    case reconnecting(attempt: Int, delay: TimeInterval)
}

enum BLEDisconnectReason: Sendable {
    case signalLoss, userInitiated, pairingFailed, unknownError(code: Int)
}
```

### 7.1 TCA Dependency Registration

```swift
extension BluetoothClient: DependencyKey {
    static let liveValue = BluetoothClient.live   // CoreBluetooth implementation
    static let testValue = BluetoothClient.mock   // Mock streams for TestStore
    static let previewValue = BluetoothClient.preview // Pre-scripted scenarios for Xcode Previews
}

extension DependencyValues {
    var bluetooth: BluetoothClient {
        get { self[BluetoothClient.self] }
        set { self[BluetoothClient.self] = newValue }
    }
}
```

---

## 8. Sensor Discovery — Service UUID Lookup

During scan, Cyclometer advertises interest in all three sensor service UUIDs simultaneously. Discovered peripherals are classified by the services they advertise.

```swift
extension BluetoothClient {
    enum ServiceUUIDs {
        static let radar = CBUUID(string: "6A4E3200-667B-11E3-949A-0800200C9A66")
        static let heartRate = CBUUID(string: "180D")
        static let cyclingSpeedCadence = CBUUID(string: "1816")
        static let cyclingPower = CBUUID(string: "1818")  // Phase 3

        static var allMVP: [CBUUID] { [radar, heartRate, cyclingSpeedCadence] }
    }

    enum CharacteristicUUIDs {
        // Radar
        static let radarCapability = CBUUID(string: "6A4E3201-667B-11E3-949A-0800200C9A66")
        static let radarAlert = CBUUID(string: "6A4E3202-667B-11E3-949A-0800200C9A66")

        // Heart Rate
        static let hrMeasurement = CBUUID(string: "2A37")
        static let bodySensorLocation = CBUUID(string: "2A38")

        // CSC
        static let cscMeasurement = CBUUID(string: "2A5B")
        static let cscFeature = CBUUID(string: "2A5C")
    }
}
```

---

## 9. Mock Client — Testing and Previews

```swift
extension BluetoothClient {
    /// Mock client with controllable event streams for TCA TestStore and Xcode Previews.
    static func mock(
        scenario: MockBLEScenario = .singleVehicleApproach
    ) -> BluetoothClient {
        var client = BluetoothClient()
        client.notifications = { peripheralId, characteristic in
            AsyncStream { continuation in
                Task {
                    for payload in scenario.payloadSequence(for: characteristic) {
                        try? await Task.sleep(for: .milliseconds(500))
                        continuation.yield(payload)
                    }
                    continuation.finish()
                }
            }
        }
        // ... connect, disconnect, scan mocks
        return client
    }
}

enum MockBLEScenario {
    case noVehicles             // L0 throughout; all clear tones only
    case singleVehicleApproach  // L1 → L2 → L3 → L0 sequence; primary testing scenario
    case multipleVehicles       // 4 simultaneous vehicles at varying distances
    case sensorDisconnect       // Connects, streams 10 points, then disconnects
    case reconnectSuccess       // Disconnects, then reconnects after 3 backoff attempts
    case hrOnlyRide             // HR only; no speed/cadence; GPS speed fallback
    case allSensorsActive       // All three sensor types simultaneously

    func payloadSequence(for characteristic: CBUUID) -> [Data] {
        // Returns pre-scripted Data payloads for the given characteristic
        // Used by TestStore and Previews
        switch (self, characteristic) {
        case (.singleVehicleApproach, BluetoothClient.CharacteristicUUIDs.radarAlert):
            return MockPayloads.singleVehicleApproach
        case (.noVehicles, BluetoothClient.CharacteristicUUIDs.radarAlert):
            return MockPayloads.noVehicles
        default:
            return []
        }
    }
}

enum MockPayloads {
    // L1: 1 vehicle at 80m, 20 km/h closing
    static let singleVehicleApproach: [Data] = [
        Data([0x01, 0x01, 0x00, 80, 20, 0x01]),  // L1, 1 vehicle, index 0, 80m, 20 km/h, advisory
        Data([0x02, 0x01, 0x00, 50, 35, 0x02]),  // L2, 1 vehicle, 50m, 35 km/h, caution
        Data([0x03, 0x01, 0x00, 20, 55, 0x03]),  // L3, 1 vehicle, 20m, 55 km/h, danger
        Data([0x00, 0x00]),                       // L0, 0 vehicles, clear
    ]

    static let noVehicles: [Data] = Array(repeating: Data([0x00, 0x00]), count: 20)
}
```

---

## 10. OQ2 — Garmin SDK Evaluation Criteria (M2 Spike)

During M2, the engineering team must evaluate whether Garmin's `ConnectIQ` mobile SDK (or any Garmin-specific iOS framework) provides a meaningful abstraction over raw CoreBluetooth for Varia integration.

**Evaluation matrix:**

| Criterion | Raw CoreBluetooth | Garmin SDK (if available) |
|---|---|---|
| UUID discovery validation | Manual hardware testing | SDK may provide correct UUIDs |
| Payload parsing documentation | pycycling + open-source reference | SDK may provide typed payloads |
| Reconnection handling | Custom implementation required | SDK may handle transparently |
| TestStore compatibility | Full (mock client wraps it) | May require adapter layer |
| Dependency footprint | Zero (framework built-in) | Adds third-party dependency |
| Garmin BLE Program requirement | May still be required for private chars | SDK access may require program membership |

**Recommendation trigger:** If the Garmin SDK provides validated UUID constants and typed payload parsing for the RTL515/RCT715, adoption is justified. If it's primarily a device management layer (ConnectIQ app distribution), raw CoreBluetooth remains the correct approach.

**M2 spike deliverable:** One-page SDK evaluation report with go/no-go recommendation, appended to this document.

---

## 11. BLE Permissions and Privacy

### Required Info.plist Keys

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Cyclometer uses Bluetooth to connect to your cycling sensors including, heart rate sensor, speed, cadence, power, and radar.</string>
```

`NSBluetoothPeripheralUsageDescription` is **not** required. It was deprecated in iOS 13 and applies only to apps acting as a BLE *peripheral*; Cyclometer is central-only. An earlier revision of this spec listed it in error.

Background mode declarations are covered in §13.

### CBCentralManagerState Handling

```swift
switch centralManager.state {
case .poweredOn:
    // Begin scan or reconnect
case .poweredOff:
    // Inform user; suspend all BLE operations
case .unauthorized:
    // Direct user to Settings; show onboarding permission prompt
case .unsupported:
    // Device does not support BLE — should not occur on any supported iPhone
case .resetting, .unknown:
    // Wait for state update; retry
}
```

App must **not crash** when Bluetooth permission is denied. The `RadarFeature` gracefully shows "Radar not available — enable Bluetooth in Settings" when CBCentralManager reports `.unauthorized`.

---

## 12. Testing Acceptance Criteria

| Test | Assertion |
|---|---|
| Radar payload parses correctly for 0–8 vehicles | `RadarAlertPayload(data:)` returns correct `AlertLevel` and `[RadarVehicle]` for all vehicle counts |
| Malformed payload returns nil | Payloads with insufficient bytes return `nil` gracefully |
| CSC speed calculation correct | Known revolution/time pairs produce correct m/s (within 0.01 m/s) |
| CSC rollover handled | `UInt32.max` → `0x0000` revolution sequence computes correct positive delta |
| CSC cadence calculation correct | Known crank revolution/time pairs produce correct RPM |
| HR payload parses 8-bit BPM | Single byte BPM read correctly |
| HR payload parses 16-bit BPM | Two-byte BPM read correctly per flags |
| Reconnection backoff sequence | Delays follow 1s, 2s, 4s, 8s, 16s, 30s, 30s... pattern |
| Speed disconnection during ride | GPS fallback activates; source badge updates; banner shown |
| Cadence disconnection during ride | Cadence shows "--"; no fallback; banner shown |
| Shared peripheral disconnection | Both speed fallback and cadence "--" fire; single combined banner |
| CSC capabilities: wheel-only sensor | Auto-assigned Speed role; no role sheet shown |
| CSC capabilities: crank-only sensor | Auto-assigned Cadence role; no role sheet shown |
| CSC capabilities: combo sensor | Role sheet shown with Speed / Cadence / Both options |
| Combo sensor assigned Both | SpeedFeature and CadenceFeature both connect to same peripheral UUID |
| Speed-only peripheral + combo Cadence-only | Both features active simultaneously on different peripherals |
| Radar sidebar hidden when no radar paired | `RadarFeature.State.isPaired == false` → sidebar absent |
| Radar sidebar shows offline state | `RadarFeature.State.connectionState == .reconnecting` → grayed offline indicator |
| All scenarios testable via MockBLEScenario | TestStore can run all 7 mock scenarios without hardware |

---

## 13. Background Execution and State Restoration

> **Decision note — issue #71 (M6 spike).** Recorded 2026-08-03. This section is the output of the
> spike; it is a decision record, not a design proposal. Later milestones may supersede it, but should
> do so explicitly rather than by drift.

### 13.1 Status of the evidence

The spike's questions were answered **by reasoning from documented platform behavior, not by
measurement on hardware.** No physical iPhone with a paired Varia / HR strap / CSC sensor was available
when this note was written. Q1–Q3 below are therefore marked *unverified* and each carries a concrete
test to run when hardware is available. The decisions in §13.3 are deliberately biased toward the
option that is safe if the reasoning turns out to be wrong.

### 13.2 Questions

**Q1 — With only the `location` background mode, do CoreBluetooth notifications keep arriving while the app is backgrounded?** *(unverified)*

Probably yes, for the duration of a ride. `LocationClient` sets `allowsBackgroundLocationUpdates = true`
and `pausesLocationUpdatesAutomatically = false`, so an active ride keeps the process *running* rather
than suspended, and CoreBluetooth delegate callbacks continue to be delivered to a running process.
The failure mode is not backgrounding but *suspension*, and location updates prevent suspension.

This is load-bearing but fragile: it means BLE liveness is a side effect of the GPS session. If a rider
denies location, or a future non-recording mode runs without GPS, BLE would silently stop working in the
background. That fragility is the reason §13.3 adopts `bluetooth-central` even though Q1 alone may not
require it.

> **To verify:** start a ride, lock the screen for 10+ minutes, then `log collect --device --last 1h`
> and filter subsystem `com.xavier.cyclometer`. The sensor clients log every notification, so a
> continuous stream of `speed`/`cadence`/`hr` lines across the locked window confirms it.

**Q2 — Does scanning work while backgrounded without `bluetooth-central`?** *(unverified)*

No. Background scanning is gated on the `bluetooth-central` background mode independently of whether
the process is alive. This is the question that decides the milestone: a rider who starts a ride with a
sensor powered off, pockets the phone, and then powers the sensor on will never see it discovered.

Note that when background scanning *is* permitted, it operates under two restrictions the current
implementation already satisfies: an explicit service-UUID filter is required (`BLECentral.rescan`
always passes one), and `CBCentralManagerScanOptionAllowDuplicatesKey` is ignored (never set).

> **To verify:** start a ride with the CSC sensor powered off, lock the screen, power the sensor on,
> and watch for the `discovered "…"` log line.

**Q3 — Does reconnection work while backgrounded?** *(unverified)*

Yes, and it is the most robust of the three. `startReconnect` re-issues `connect(peripheralID:)` rather
than rescanning, and a pending connection request placed while the peripheral is out of range stays
pending and completes when it returns — iOS honors this even when the app is not running. `BLECentral`
retains discovered peripherals in `discovered`, so reconnect-by-UUID needs no fresh scan.

> **To verify:** with the screen locked, power-cycle a connected sensor and confirm the backoff-ladder
> log lines appear and the sensor returns to `.active`.

**Q4 — Does an `.ambient`-category tone play while backgrounded?**

No — and this is a real gap in the current audio design, not merely a background-mode question.
`AudioClient.liveValue` is still stubs, so nothing is broken *yet*, but Audio.md §"AVAudioSession
Configuration" specifies `.ambient` for the All Clear and Warning tones so they respect the silent
switch. The `.ambient` category is both silenced by the hardware switch *and* non-functional for
background playback. Under the spec as written, **a rider with the phone in a jersey pocket and the
screen locked would hear no Warning tone** — which is precisely the scenario Audio.md's
"jersey-pocket audible" requirement targets.

Adding the `audio` background mode is necessary but not sufficient to fix this: `.ambient` will still
not play backgrounded. The resolution requires an M4 decision about the L2 category, and iOS provides
no API to read the silent-switch position, so "respect the switch" and "play while backgrounded" cannot
both be satisfied by category choice alone. **Handed to M4 (#33) as an open design question.**

### 13.3 Decisions

**1. Adopt `bluetooth-central`. — Done, this issue.**

Q2 is the reason. The cost is one `Info.plist` key; the alternative is a category of silent mid-ride
failure that no test would catch. It also decouples BLE liveness from the GPS session, removing the
Q1 fragility.

**2. Adopt `audio`. — Done, this issue.**

Required for any ride-time alert tone to be audible with the screen locked. The plist key is claimed
here so M4 does not have to relitigate the background-mode question while designing tone playback;
the `.ambient` problem in Q4 is M4's to resolve.

**3. Defer `CBCentralManager` state restoration to M7. — Deferred.**

State restoration matters only when iOS *terminates* the app and later relaunches it into the
background on a BLE event. Today that relaunch would reconnect a radar into an app with no ride to
attach it to: `CoreDataStack` has no checkpointing, so PRD §12's "CoreData checkpoint every 30 seconds"
is unimplemented and a terminated ride is already lost. Restoring the BLE half of a state whose other
half is gone buys nothing a rider can perceive.

This is not a claim that restoration is unnecessary — it is a claim that it is **premature**. It is
also cheap to reverse, being one options dictionary at a single call site.

> **Revisit trigger:** M7, when TrackPoint recording and CoreData checkpointing land. Restoration
> becomes worthwhile at exactly the point where a terminated ride is recoverable.

### 13.4 What adopting restoration would require

Recorded now so the M7 issue can be written from it rather than re-derived.

| Change | Location |
|---|---|
| Pass `CBCentralManagerOptionRestoreIdentifierKey` at manager construction | `BLECentral.init` — `Clients/BLE/BLEClient.swift` |
| Implement `centralManager(_:willRestoreState:)`, rehydrating `discovered` from `CBCentralManagerRestoredStatePeripheralsKey` | `BLECentral` |
| Reassign `peripheral.delegate = self` on every restored peripheral — CoreBluetooth does not restore delegates | `BLECentral` |
| Rebuild `connectionOwners`, which is **not** restorable from CoreBluetooth — the owner set is Cyclometer's own ref-count and must be reconstructed from persisted `PairedSensor` records (#67) | `BLECentral` + persistence |
| Rebuild per-client state: `CSCClientState.slots` (roles, calculators, names) and the radar client's target peripheral | `BLECSCClient`, `VariaRadarClient` |
| Re-establish notification subscriptions, or verify restored peripherals arrive with `isNotifying` already true | all three sensor clients |
| Decide restoration behavior when no ride is active — a relaunch that reconnects sensors with no ride running should stand down rather than hold connections open | `AppFeature` |

The fourth row is the substantive one and the reason this waits for #67: the connection ref-count is a
Cyclometer invariant with no CoreBluetooth equivalent, so restoration is not well-defined until paired
sensors are persisted.

### 13.5 Resulting `Info.plist`

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>bluetooth-central</string>
    <string>location</string>
</array>
```

No restore identifier is set, consistent with decision 3.

---

## 14. Battery Service (0x180F)

Every sensor profile in this spec sits on a device that may also expose the Bluetooth SIG
Battery Service. Battery level therefore belongs to the *peripheral*, not to the radar, HR or
CSC profile — all three clients run one shared handshake (`BatteryService` in
`Clients/BLE/BatteryService.swift`) rather than three copies of it.

### 14.1 GATT

| Name | UUID | Type |
|---|---|---|
| Battery Service | `0x180F` | Service |
| Battery Level | `0x2A19` | Characteristic — Read, optionally Notify |

Not advertised, so it does not join any scan filter: it is discovered after connect.

### 14.2 Payload

One byte, `0`–`100` percent. Values above 100 are rejected rather than clamped — a sensor
answering `0xFF` is reporting a fault, not a full charge, and a bogus "255%" on a sensor row is
worse than no battery label.

### 14.3 Read policy — read once per connection, notify where offered

On `.connected` the client includes `0x180F` in the same `discoverServices` call as its own
profile service. A second call would work, but `didDiscoverServices` broadcasts the peripheral's
*full* accumulated service list, so it would re-fire the profile characteristic's
discover → notify chain.

Once `0x2A19` is discovered the client issues both a `readValue` and a
`setNotifyValue(true, …)`. The read guarantees a level on sensors that only support reads; the
subscription keeps it live on the majority that push on change. A sensor that does not support
notify ignores the subscription and the connect-time reading stands. No polling: battery moves
slowly, and the Start sheet is opened at the point in a ride where a fresh value matters.

The level is cleared on disconnect. It is re-read on reconnect rather than held, so a row never
shows a level that predates the gap.

### 14.4 Exposure

| Client | Endpoint | Granularity |
|---|---|---|
| `VariaRadarClient` | `batteryLevel() -> AsyncStream<Int?>` | The one radar |
| `BLEHRClient` | `batteryLevel() -> AsyncStream<Int?>` | The one strap |
| `BLECSCClient` | `batteryLevel(SensorRole) -> AsyncStream<Int?>` | Per role — speed and cadence can be different devices |

All replay on subscribe, as the connection-state streams do. Replay matters more here: the level
is read once per connection, so a subscriber arriving afterwards would otherwise learn nothing
until the next reconnect. `nil` means unknown — disconnected, or a sensor without `0x180F`.

`BLECSCClient.DiscoveredSensor` also carries `batteryPercent` for the per-device rows on S11.

Rendered by `SensorBatteryLabel` (UX.md §S05.1 "the battery level if supported"), which picks the
SF Symbol by level and tints at or below 20% with `cyRatingBad`.

---

*Cyclometer BLE Integration Spec v1.2 · 2026-08-03*
