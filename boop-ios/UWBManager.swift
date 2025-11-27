import Foundation
import NearbyInteraction
import simd

// MARK: - Protocol for Dependency Injection
protocol UWBManaging: AnyObject {
    /// Determines if the device is pointed at another device using UWB
    /// Combines angle alignment, height similarity, and proximity detection
    /// **Detection**: Uses UWB distance (≤50cm) + horizontal/vertical angle alignment
    /// **Accuracy**: ~10cm distance, ~5° angle precision
    /// - Parameter deviceID: The UUID of the device to check
    /// - Returns: True if pointed at the device with aligned angles
    func isPointingAt(deviceID: UUID) -> Bool

    /// Determines if another device is nearby based on distance only (no angle checking)
    /// **Detection**: Uses UWB distance measurement only (≤50cm)
    /// - Parameter deviceID: The UUID of the device to check
    /// - Returns: True if device is within proximity range, regardless of pointing direction
    func isNearby(deviceID: UUID) -> Bool

    /// Determines if devices are approximately touching (≤10cm) and pointed at each other
    /// **Detection**: Distance ≤10cm AND angles aligned (horizontal ≤15°, vertical ≤10°)
    /// **Use case**: Physical "boop" interaction between devices
    /// - Parameter deviceID: The UUID of the device to check
    /// - Returns: True if devices are touching distance with aligned angles
    func isApproximatelyTouching(deviceID: UUID) -> Bool

    /// Start UWB ranging session with a peer
    func startRanging(to deviceID: UUID, token: NIDiscoveryToken)

    /// Stop UWB ranging session with a peer
    func stopRanging(to deviceID: UUID)

    /// Get the current discovery token for this device
    var discoveryToken: NIDiscoveryToken? { get }
}

// MARK: - UWB Manager Implementation
class UWBManager: NSObject, UWBManaging {

    // MARK: - Configuration
    private struct PointingThresholds {
        static let touchingDistance: Float = 0.1     // meters (10cm) - touching range
        static let maxDistance: Float = 0.5          // meters (50cm) - maximum for pointing
        static let maxHorizontalAngle: Float = 15.0  // degrees - pointing cone
        static let maxVerticalAngle: Float = 10.0    // degrees - height alignment
    }

    // MARK: - Properties
    private var niSession: NISession?
    private var nearbyObjects: [UUID: NINearbyObject] = [:]
    private var deviceTokens: [UUID: NIDiscoveryToken] = [:]

    var discoveryToken: NIDiscoveryToken? {
        return niSession?.discoveryToken
    }

    // MARK: - Init
    override init() {
        super.init()
        setupSession()
    }

    // MARK: - Setup
    private func setupSession() {
        niSession = NISession()
        niSession?.delegate = self
        print("📍 UWB: Session initialized")
    }

    // MARK: - Public Methods
    func isPointingAt(deviceID: UUID) -> Bool {
        guard let object = nearbyObjects[deviceID] else {
            // No UWB data available for this device
            return false
        }

        // Check distance - must be within pointing range
        guard let distance = object.distance else {
            return false
        }

        // Check distance bound - not too far
        if distance > PointingThresholds.maxDistance {
            return false
        }

        // Check direction - must be aligned horizontally and vertically
        guard let direction = object.direction else {
            // No direction data, fallback to distance only
            return distance <= PointingThresholds.maxDistance
        }

        // Extract horizontal and vertical angles
        let horizontalAngle = abs(atan2(direction.y, direction.x) * 180 / .pi)
        let verticalAngle = abs(atan2(direction.z,
            sqrt(direction.x * direction.x + direction.y * direction.y)) * 180 / .pi)

        let isAngleAligned = horizontalAngle <= PointingThresholds.maxHorizontalAngle
        let isHeightAligned = verticalAngle <= PointingThresholds.maxVerticalAngle

        let isPointing = isAngleAligned && isHeightAligned

        if isPointing {
            print("📍 UWB: Pointing at \(deviceID.uuidString.prefix(8)) - distance: \(distance)m, h-angle: \(horizontalAngle)°, v-angle: \(verticalAngle)°")
        }

        return isPointing
    }

    func isNearby(deviceID: UUID) -> Bool {
        guard let object = nearbyObjects[deviceID] else {
            // No UWB data available for this device
            return false
        }

        // Check distance only - no angle requirements
        guard let distance = object.distance else {
            return false
        }

        // Check distance bound - not too far
        let isInRange = distance <= PointingThresholds.maxDistance

        if isInRange {
            print("📍 UWB: \(deviceID.uuidString.prefix(8)) nearby - distance: \(distance)m")
        }

        return isInRange
    }

    func isApproximatelyTouching(deviceID: UUID) -> Bool {
        guard let object = nearbyObjects[deviceID] else {
            // No UWB data available for this device
            return false
        }

        // Check distance - must be within touching range
        guard let distance = object.distance else {
            return false
        }

        // Must be within 10cm
        if distance > PointingThresholds.touchingDistance {
            return false
        }

        // Check direction - must be aligned horizontally and vertically
        guard let direction = object.direction else {
            // No direction data, consider touching if distance is close enough
            print("📍 UWB: \(deviceID.uuidString.prefix(8)) touching (no angle data) - distance: \(distance)m")
            return true
        }

        // Extract horizontal and vertical angles
        let horizontalAngle = abs(atan2(direction.y, direction.x) * 180 / .pi)
        let verticalAngle = abs(atan2(direction.z,
            sqrt(direction.x * direction.x + direction.y * direction.y)) * 180 / .pi)

        let isAngleAligned = horizontalAngle <= PointingThresholds.maxHorizontalAngle
        let isHeightAligned = verticalAngle <= PointingThresholds.maxVerticalAngle

        let isTouching = isAngleAligned && isHeightAligned

        if isTouching {
            print("📍 UWB: Touching \(deviceID.uuidString.prefix(8)) - distance: \(distance)m, h-angle: \(horizontalAngle)°, v-angle: \(verticalAngle)°")
        }

        return isTouching
    }

    func startRanging(to deviceID: UUID, token: NIDiscoveryToken) {
        deviceTokens[deviceID] = token

        let config = NINearbyPeerConfiguration(peerToken: token)
        niSession?.run(config)

        print("📍 UWB: Started ranging to \(deviceID.uuidString.prefix(8))")
    }

    func stopRanging(to deviceID: UUID) {
        deviceTokens.removeValue(forKey: deviceID)
        nearbyObjects.removeValue(forKey: deviceID)

        // If no more devices, invalidate session
        if deviceTokens.isEmpty {
            niSession?.invalidate()
            setupSession() // Recreate for next use
        }

        print("📍 UWB: Stopped ranging to \(deviceID.uuidString.prefix(8))")
    }

    // MARK: - Helper
    private func deviceID(for token: NIDiscoveryToken) -> UUID? {
        return deviceTokens.first(where: { $0.value == token })?.key
    }
}

// MARK: - NISession Delegate
extension UWBManager: NISessionDelegate {
    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        Task { @MainActor in
            for object in nearbyObjects {
                let token = object.discoveryToken
                guard let deviceID = deviceID(for: token) else {
                    continue
                }

                self.nearbyObjects[deviceID] = object

                if let distance = object.distance,
                   let direction = object.direction {
                    let horizontalAngle = abs(atan2(direction.y, direction.x) * 180 / .pi)
                    let verticalAngle = abs(atan2(direction.z,
                        sqrt(direction.x * direction.x + direction.y * direction.y)) * 180 / .pi)

                    print("📏 UWB: \(deviceID.uuidString.prefix(8)) - \(distance)m, h: \(horizontalAngle)°, v: \(verticalAngle)°")
                }
            }
        }
    }

    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        Task { @MainActor in
            for object in nearbyObjects {
                let token = object.discoveryToken
                guard let deviceID = deviceID(for: token) else {
                    continue
                }

                self.nearbyObjects.removeValue(forKey: deviceID)
                print("📍 UWB: Lost connection to \(deviceID.uuidString.prefix(8)), reason: \(reason.rawValue)")
            }
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        Task { @MainActor in
            print("⚠️ UWB: Session invalidated - \(error.localizedDescription)")
            nearbyObjects.removeAll()
        }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {
        Task { @MainActor in
            print("⚠️ UWB: Session suspended")
        }
    }

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        Task { @MainActor in
            print("✅ UWB: Session resumed")
        }
    }
}
