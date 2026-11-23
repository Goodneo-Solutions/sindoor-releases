#if os(iOS)
import CoreBluetooth
import CoreLocation
import Foundation

/// BLE beacons heard by the phone (IV14, IQ12): the site's iBeacons ranged by CoreLocation (Core Bluetooth scans hide
/// iBeacon frames on iOS) and Eddystone-UID beacons by Core Bluetooth (service data 0xFEAA). One `ble` observation per
/// second with the beacons heard in it (`{t, kind: ble, beacons: [{id, rssi, tx?}]}`); readings stay on the phone.
///
/// It never asks for a permission: the app asks for location When In Use (iBeacons) and declares Bluetooth
/// (`NSBluetoothAlwaysUsageDescription`, Eddystone) first; a missing one is reported to `onError` as
/// `permission_missing` / `permission_denied` (or `location_off`, `ranging_unavailable`, `bluetooth_off`,
/// `bluetooth_unsupported`) and that source stays off.
public final class SindoorBeacons: NSObject, CLLocationManagerDelegate, CBCentralManagerDelegate {
    public static let eddystoneService = CBUUID(string: "FEAA")

    /// iBeacon proximity UUIDs to range (lower case).
    public let uuids: [String]
    /// Listen for Eddystone-UID beacons too.
    public let eddystone: Bool
    /// How often the heard beacons are handed over (s).
    public let interval: TimeInterval

    /// Each round's beacons as an observation (feed `SindoorLocator.observe`).
    public var onObservation: (([String: Any]) -> Void)?
    /// Each round's beacons.
    public var onReadings: (([SindoorBeaconReading]) -> Void)?
    public var onError: ((SindoorError) -> Void)?

    private var location: CLLocationManager?
    private var central: CBCentralManager?
    private var constraints: [CLBeaconIdentityConstraint] = []
    private var round: [SindoorBeaconReading] = []
    private var timer: Timer?
    private var running = false
    private var feeding: SindoorLocator?
    private var estimateHandler: ((SindoorEstimate) -> Void)?

    /// The site's beacons: its iBeacon UUIDs, Eddystone when it has any `ed:` beacon.
    public convenience init(site: SindoorSite, interval: TimeInterval = 1) throws {
        let b = try site.beacons()
        let ed = b.contains { ("\($0["id"] ?? "")").lowercased().hasPrefix("ed:") }
        self.init(uuids: SindoorBeaconID.iBeaconUUIDs(b), eddystone: ed, interval: interval)
    }

    public init(uuids: [String], eddystone: Bool = true, interval: TimeInterval = 1) {
        self.uuids = Array(Set(uuids.map { $0.lowercased() })).sorted()
        self.eddystone = eddystone
        self.interval = interval
        super.init()
    }

    /// Whether the app may range iBeacons now (location When In Use or Always).
    public static var locationAuthorized: Bool {
        switch CLLocationManager().authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    /// Start listening; with `locator`, each round is observed by it (estimates to `onEstimate`).
    public func start(feeding locator: SindoorLocator? = nil, onEstimate: ((SindoorEstimate) -> Void)? = nil) {
        stop()
        running = true
        feeding = locator
        estimateHandler = onEstimate
        startRanging()
        if eddystone { central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false]) }
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.flush() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        if let m = location { for c in constraints { m.stopRangingBeacons(satisfying: c) } }
        constraints = []
        central?.stopScan()
        central = nil
        round = []
        feeding = nil
        estimateHandler = nil
    }

    deinit { timer?.invalidate() }

    private func flush() {
        let seen = SindoorBeaconID.merge(round)
        round = []
        guard !seen.isEmpty else { return }
        onReadings?(seen)
        let o = SindoorObservation.ble(seen)
        onObservation?(o)
        if let l = feeding {
            do {
                if let e = try l.observe(o) { estimateHandler?(e) }
            } catch let e as SindoorError { onError?(e) } catch {}
        }
    }

    // MARK: iBeacons

    private func refusal() -> SindoorError? {
        if !CLLocationManager.isRangingAvailable() { return SindoorError("ranging_unavailable", "this device cannot range beacons") }
        if !CLLocationManager.locationServicesEnabled() { return SindoorError("location_off", "Location Services are off") }
        switch (location ?? CLLocationManager()).authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return nil
        case .notDetermined: return SindoorError("permission_missing", "location permission not asked yet (iBeacons)")
        default: return SindoorError("permission_denied", "location permission denied or restricted (iBeacons)")
        }
    }

    private func startRanging() {
        let ids = uuids.compactMap { UUID(uuidString: $0) }
        guard !ids.isEmpty else { return }
        let m = location ?? CLLocationManager()
        m.delegate = self
        location = m
        if let e = refusal() { onError?(e); return }
        constraints = ids.map { CLBeaconIdentityConstraint(uuid: $0) }
        for c in constraints { m.startRangingBeacons(satisfying: c) }
    }

    public func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        for b in beacons where b.rssi != 0 {
            round.append(SindoorBeaconReading(id: SindoorBeaconID.iBeacon(uuid: b.uuid.uuidString, major: b.major.intValue, minor: b.minor.intValue), rssi: Double(b.rssi)))
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailRangingFor beaconConstraint: CLBeaconIdentityConstraint, error: Error) {
        onError?(SindoorError("ranging_failed", error.localizedDescription))
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard running, !uuids.isEmpty else { return }
        if constraints.isEmpty { if refusal() == nil { startRanging() } } else if let e = refusal() {
            for c in constraints { manager.stopRangingBeacons(satisfying: c) }
            constraints = []
            onError?(e)
        }
    }

    // MARK: Eddystone

    public func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:
            c.scanForPeripherals(withServices: [Self.eddystoneService], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        case .unauthorized:
            onError?(SindoorError(CBManager.authorization == .notDetermined ? "permission_missing" : "permission_denied", "Bluetooth permission missing or denied (Eddystone)"))
        case .poweredOff:
            onError?(SindoorError("bluetooth_off", "Bluetooth is off"))
        case .unsupported:
            onError?(SindoorError("bluetooth_unsupported", "this device has no Bluetooth LE"))
        default:
            break
        }
    }

    public func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        guard let sd = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data], let d = sd[Self.eddystoneService],
              let uid = SindoorBeaconID.eddystoneUID(serviceData: d) else { return }
        let r = rssi.doubleValue
        guard r < 0, r > -127 else { return }
        round.append(SindoorBeaconReading(id: uid.id, rssi: r, tx: uid.tx))
    }
}
#endif
