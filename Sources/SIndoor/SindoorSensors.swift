#if os(iOS)
import CoreLocation
import CoreMotion
import Foundation

/// The phone's motion sensors fed to a locator (IV10, IQ20): steps from CMPedometer, the heading in the `north` frame
/// (a compass bearing: CMMotionManager's fused device motion, else CLLocationManager's heading) and barometric
/// pressure from CMAltimeter (hPa). Observations: `steps {n, heading_deg, frame: "north"}`,
/// `heading {deg, source: "fused", frame: "north"}` (or `source: "compass"`), `pressure {hpa}`. Nothing leaves the
/// phone.
///
/// It never asks for a permission on its own: steps and pressure need Motion & Fitness
/// (`NSMotionUsageDescription`); while it is not determined they are reported to `onError` as `permission_missing`
/// and stay off unless the app calls `requestMotionPermission()` first (which shows the system prompt).
public final class SindoorSensors: NSObject, CLLocationManagerDelegate {
    /// Each observation (feed `SindoorLocator.observe`).
    public var onObservation: (([String: Any]) -> Void)?
    public var onError: ((SindoorError) -> Void)?
    /// A heading observation is sent at most this often (s) and only after this change (degrees).
    public var headingInterval: TimeInterval = 0.5
    public var headingChangeDeg: Double = 3

    private let pedometer = CMPedometer()
    private let motion = CMMotionManager()
    private let altimeter = CMAltimeter()
    private var location: CLLocationManager?
    private let queue = OperationQueue()
    private var lastSteps = 0
    private var heading: Double?
    private var headingSource = "fused"
    private var lastHeadingSent: (deg: Double, at: Date)?
    private var feeding: SindoorLocator?
    private var estimateHandler: ((SindoorEstimate) -> Void)?
    public private(set) var running = false

    public override init() {
        queue.maxConcurrentOperationCount = 1
        queue.name = "sindoor.sensors"
        super.init()
    }

    /// The Motion & Fitness permission (steps, pressure).
    public static var motionAuthorization: CMAuthorizationStatus { CMPedometer.authorizationStatus() }

    /// Shows the Motion & Fitness prompt when not determined yet; calls back with whether motion data may be read.
    public func requestMotionPermission(_ done: @escaping (Bool) -> Void) {
        guard CMPedometer.isStepCountingAvailable() else { done(false); return }
        if Self.motionAuthorization != .notDetermined { done(Self.motionAuthorization == .authorized); return }
        pedometer.queryPedometerData(from: Date(timeIntervalSinceNow: -60), to: Date()) { _, _ in
            DispatchQueue.main.async { done(Self.motionAuthorization == .authorized) }
        }
    }

    /// Start the sensors; with `locator`, each observation is observed by it (estimates to `onEstimate`).
    public func start(feeding locator: SindoorLocator? = nil, onEstimate: ((SindoorEstimate) -> Void)? = nil) {
        stop()
        running = true
        feeding = locator
        estimateHandler = onEstimate
        startHeading()
        switch Self.motionAuthorization {
        case .authorized:
            startSteps()
            startPressure()
        case .notDetermined:
            onError?(SindoorError("permission_missing", "Motion & Fitness permission not asked yet (steps, pressure)"))
        default:
            onError?(SindoorError("permission_denied", "Motion & Fitness permission denied or restricted (steps, pressure)"))
        }
    }

    public func stop() {
        running = false
        pedometer.stopUpdates()
        motion.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        location?.stopUpdatingHeading()
        lastSteps = 0
        lastHeadingSent = nil
        feeding = nil
        estimateHandler = nil
    }

    deinit { stop() }

    private func emit(_ o: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running else { return }
            self.onObservation?(o)
            if let l = self.feeding {
                do {
                    if let e = try l.observe(o) { self.estimateHandler?(e) }
                } catch let e as SindoorError { self.onError?(e) } catch {}
            }
        }
    }

    // MARK: steps

    private func startSteps() {
        guard CMPedometer.isStepCountingAvailable() else {
            onError?(SindoorError("steps_unavailable", "this device counts no steps"))
            return
        }
        lastSteps = 0
        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            guard let self else { return }
            if let error { DispatchQueue.main.async { self.onError?(SindoorError("steps_failed", error.localizedDescription)) }; return }
            guard let data else { return }
            DispatchQueue.main.async {
                let total = data.numberOfSteps.intValue
                let n = total - self.lastSteps
                guard n > 0, let h = self.heading else { return }
                self.lastSteps = total
                self.emit(SindoorObservation.steps(n, headingDeg: h))
            }
        }
    }

    // MARK: heading

    private func startHeading() {
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let trueNorthOK = frames.contains(.xTrueNorthZVertical) && SindoorBeacons.locationAuthorized
        if motion.isDeviceMotionAvailable, trueNorthOK || frames.contains(.xMagneticNorthZVertical) {
            headingSource = "fused"
            motion.deviceMotionUpdateInterval = 0.1
            motion.startDeviceMotionUpdates(using: trueNorthOK ? .xTrueNorthZVertical : .xMagneticNorthZVertical, to: queue) { [weak self] m, _ in
                guard let m, m.heading >= 0 else { return }
                DispatchQueue.main.async { self?.took(heading: m.heading) }
            }
            return
        }
        guard CLLocationManager.headingAvailable() else {
            onError?(SindoorError("heading_unavailable", "this device has no compass"))
            return
        }
        headingSource = "compass"
        let l = location ?? CLLocationManager()
        l.delegate = self
        l.headingFilter = 1
        location = l
        l.startUpdatingHeading()
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateHeading h: CLHeading) {
        let deg = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
        guard deg >= 0 else { return }
        took(heading: deg)
    }

    private func took(heading deg: Double) {
        heading = deg
        let now = Date()
        if let l = lastHeadingSent {
            let d = abs(((deg - l.deg + 540).truncatingRemainder(dividingBy: 360)) - 180)
            if now.timeIntervalSince(l.at) < headingInterval || d < headingChangeDeg { return }
        }
        lastHeadingSent = (deg, now)
        emit(SindoorObservation.heading(deg, source: headingSource))
    }

    // MARK: pressure

    private func startPressure() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        altimeter.startRelativeAltitudeUpdates(to: queue) { [weak self] d, error in
            guard let self else { return }
            if let error { DispatchQueue.main.async { self.onError?(SindoorError("pressure_failed", error.localizedDescription)) }; return }
            guard let d else { return }
            self.emit(SindoorObservation.pressure(d.pressure.doubleValue * 10))
        }
    }
}
#endif
