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
        guard NISession.isSupported else {
            print("❌ UWB: NISession is NOT SUPPORTED on this device")
            return
        }

        niSession = NISession()
        niSession?.delegate = self

        if let token = niSession?.discoveryToken {
            print("✅ UWB: Session initialized successfully")
            print("📍 UWB: Discovery token available (size: \(try! NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true).count) bytes)")
        } else {
            print("⚠️ UWB: Session initialized but NO DISCOVERY TOKEN available")
        }
    }

    // MARK: - Public Methods
    func isPointingAt(deviceID: UUID) -> Bool {
        print("🔍 UWB: isPointingAt(\(deviceID.uuidString.prefix(8))) called")

        guard let object = nearbyObjects[deviceID] else {
            // No UWB data available for this device
            print("❌ UWB: isPointingAt(\(deviceID.uuidString.prefix(8))) - NO UWB DATA (not in nearbyObjects)")
            return false
        }

        // Check distance - must be within pointing range
        guard let distance = object.distance else {
            print("❌ UWB: isPointingAt(\(deviceID.uuidString.prefix(8))) - NO DISTANCE DATA")
            return false
        }

        print("📏 UWB: isPointingAt(\(deviceID.uuidString.prefix(8))) - distance: \(String(format: "%.3f", distance))m (max: \(PointingThresholds.maxDistance)m)")

        // Check distance bound - not too far
        if distance > PointingThresholds.maxDistance {
            print("❌ UWB: isPointingAt(\(deviceID.uuidString.prefix(8))) - TOO FAR (distance: \(String(format: "%.3f", distance))m > \(PointingThresholds.maxDistance)m)")
            return false
        }

        // Check direction - must be aligned horizontally and vertically
        guard let direction = object.direction else {
            // No direction data, fallback to distance only
            print("⚠️ UWB: isPointingAt(\(deviceID.uuidString.prefix(8))) - NO DIRECTION DATA, using distance only: \(distance <= PointingThresholds.maxDistance)")
            return distance <= PointingThresholds.maxDistance
        }

        // Log raw direction vector
        print("📐 UWB: isPointingAt(\(deviceID.uuidString.prefix(8))) - Raw direction vector: x=\(String(format: "%.4f", direction.x)), y=\(String(format: "%.4f", direction.y)), z=\(String(format: "%.4f", direction.z))")

        // Extract horizontal and vertical angles
        let horizontalAngle = abs(atan2(direction.y, direction.x) * 180 / .pi)
        let verticalAngle = abs(atan2(direction.z,
            sqrt(direction.x * direction.x + direction.y * direction.y)) * 180 / .pi)

        let isAngleAligned = horizontalAngle <= PointingThresholds.maxHorizontalAngle
        let isHeightAligned = verticalAngle <= PointingThresholds.maxVerticalAngle

        print("📐 UWB: isPointingAt(\(deviceID.uuidString.prefix(8))) - h-angle: \(String(format: "%.2f", horizontalAngle))° (max: \(PointingThresholds.maxHorizontalAngle)°) [\(isAngleAligned ? "✓" : "✗")]")
        print("📐 UWB: isPointingAt(\(deviceID.uuidString.prefix(8))) - v-angle: \(String(format: "%.2f", verticalAngle))° (max: \(PointingThresholds.maxVerticalAngle)°) [\(isHeightAligned ? "✓" : "✗")]")

        let isPointing = isAngleAligned && isHeightAligned

        if isPointing {
            print("✅ UWB: isPointingAt(\(deviceID.uuidString.prefix(8))) - POINTING CONFIRMED")
        } else {
            print("❌ UWB: isPointingAt(\(deviceID.uuidString.prefix(8))) - NOT POINTING (angles not aligned)")
        }

        return isPointing
    }

    func isNearby(deviceID: UUID) -> Bool {
        print("🔍 UWB: isNearby(\(deviceID.uuidString.prefix(8))) called")

        guard let object = nearbyObjects[deviceID] else {
            // No UWB data available for this device
            print("❌ UWB: isNearby(\(deviceID.uuidString.prefix(8))) - NO UWB DATA (not in nearbyObjects)")
            return false
        }

        // Check distance only - no angle requirements
        guard let distance = object.distance else {
            print("❌ UWB: isNearby(\(deviceID.uuidString.prefix(8))) - NO DISTANCE DATA")
            return false
        }

        print("📏 UWB: isNearby(\(deviceID.uuidString.prefix(8))) - distance: \(String(format: "%.3f", distance))m (max: \(PointingThresholds.maxDistance)m)")

        // Check distance bound - not too far
        let isInRange = distance <= PointingThresholds.maxDistance

        if isInRange {
            print("✅ UWB: isNearby(\(deviceID.uuidString.prefix(8))) - IN RANGE")
        } else {
            print("❌ UWB: isNearby(\(deviceID.uuidString.prefix(8))) - OUT OF RANGE")
        }

        return isInRange
    }

    func isApproximatelyTouching(deviceID: UUID) -> Bool {
        print("🔍 UWB: isApproximatelyTouching(\(deviceID.uuidString.prefix(8))) called")

        guard let object = nearbyObjects[deviceID] else {
            // No UWB data available for this device
            print("❌ UWB: isApproximatelyTouching(\(deviceID.uuidString.prefix(8))) - NO UWB DATA (not in nearbyObjects)")
            return false
        }

        // Check distance - must be within touching range
        guard let distance = object.distance else {
            print("❌ UWB: isApproximatelyTouching(\(deviceID.uuidString.prefix(8))) - NO DISTANCE DATA")
            return false
        }

        print("📏 UWB: isApproximatelyTouching(\(deviceID.uuidString.prefix(8))) - distance: \(String(format: "%.3f", distance))m (max touching: \(PointingThresholds.touchingDistance)m)")

        // Must be within 10cm
        if distance > PointingThresholds.touchingDistance {
            print("❌ UWB: isApproximatelyTouching(\(deviceID.uuidString.prefix(8))) - TOO FAR (distance: \(String(format: "%.3f", distance))m > \(PointingThresholds.touchingDistance)m)")
            return false
        }

        // Check direction - must be aligned horizontally and vertically
        guard let direction = object.direction else {
            // No direction data, consider touching if distance is close enough
            print("⚠️ UWB: isApproximatelyTouching(\(deviceID.uuidString.prefix(8))) - NO DIRECTION DATA, considering as touching based on distance")
            print("✅ UWB: isApproximatelyTouching(\(deviceID.uuidString.prefix(8)) - TOUCHING CONFIRMED (no angle check)")
            return true
        }

        // Log raw direction vector
        print("📐 UWB: isApproximatelyTouching(\(deviceID.uuidString.prefix(8))) - Raw direction vector: x=\(String(format: "%.4f", direction.x)), y=\(String(format: "%.4f", direction.y)), z=\(String(format: "%.4f", direction.z))")

        // Extract horizontal and vertical angles
        let horizontalAngle = abs(atan2(direction.y, direction.x) * 180 / .pi)
        let verticalAngle = abs(atan2(direction.z,
            sqrt(direction.x * direction.x + direction.y * direction.y)) * 180 / .pi)

        let isAngleAligned = horizontalAngle <= PointingThresholds.maxHorizontalAngle
        let isHeightAligned = verticalAngle <= PointingThresholds.maxVerticalAngle

        print("📐 UWB: isApproximatelyTouching(\(deviceID.uuidString.prefix(8))) - h-angle: \(String(format: "%.2f", horizontalAngle))° (max: \(PointingThresholds.maxHorizontalAngle)°) [\(isAngleAligned ? "✓" : "✗")]")
        print("📐 UWB: isApproximatelyTouching(\(deviceID.uuidString.prefix(8))) - v-angle: \(String(format: "%.2f", verticalAngle))° (max: \(PointingThresholds.maxVerticalAngle)°) [\(isHeightAligned ? "✓" : "✗")]")

        let isTouching = isAngleAligned && isHeightAligned

        if isTouching {
            print("✅ UWB: isApproximatelyTouching(\(deviceID.uuidString.prefix(8))) - TOUCHING CONFIRMED")
        } else {
            print("❌ UWB: isApproximatelyTouching(\(deviceID.uuidString.prefix(8))) - NOT TOUCHING (angles not aligned)")
        }

        return isTouching
    }

    func startRanging(to deviceID: UUID, token: NIDiscoveryToken) {
        print("📍 UWB: startRanging() called for \(deviceID.uuidString.prefix(8))")

        guard let session = niSession else {
            print("❌ UWB: Cannot start ranging - NISession is nil")
            return
        }

        print("📍 UWB: NISession exists, storing token and creating config...")
        deviceTokens[deviceID] = token

        print("📍 UWB: deviceTokens now has \(deviceTokens.count) token(s)")
        print("📍 UWB: nearbyObjects currently has \(nearbyObjects.count) object(s)")

        do {
            let config = NINearbyPeerConfiguration(peerToken: token)
            print("📍 UWB: Created NINearbyPeerConfiguration successfully")

            session.run(config)
            print("✅ UWB: Called session.run() - ranging started to \(deviceID.uuidString.prefix(8))")
            print("📍 UWB: Total devices in ranging: \(deviceTokens.count)")
        } catch {
            print("❌ UWB: Error in startRanging: \(error.localizedDescription)")
        }
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

    // MARK: - Diagnostics
    func printDiagnostics() {
        print("🔍 UWB: === DIAGNOSTICS ===")
        print("🔍 UWB: NISession supported: \(NISession.isSupported)")
        print("🔍 UWB: NISession exists: \(niSession != nil)")
        print("🔍 UWB: Discovery token exists: \(niSession?.discoveryToken != nil)")
        print("🔍 UWB: Device tokens count: \(deviceTokens.count)")
        print("🔍 UWB: Nearby objects count: \(nearbyObjects.count)")
        if !deviceTokens.isEmpty {
            print("🔍 UWB: Devices with tokens:")
            for (deviceID, _) in deviceTokens {
                print("   - \(deviceID.uuidString.prefix(8))")
            }
        }
        if !nearbyObjects.isEmpty {
            print("🔍 UWB: Nearby objects:")
            for (deviceID, object) in nearbyObjects {
                print("   - \(deviceID.uuidString.prefix(8)): distance=\(object.distance?.description ?? "nil"), direction=\(object.direction != nil ? "available" : "nil")")
            }
        }
        print("🔍 UWB: ==================")
    }
}

// MARK: - NISession Delegate
extension UWBManager: NISessionDelegate {
    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        Task { @MainActor in
            print("📡 UWB: Session didUpdate called with \(nearbyObjects.count) object(s)")
            for object in nearbyObjects {
                let token = object.discoveryToken
                guard let deviceID = deviceID(for: token) else {
                    print("⚠️ UWB: Received update for unknown token")
                    continue
                }

                self.nearbyObjects[deviceID] = object

                if let distance = object.distance {
                    if let direction = object.direction {
                        // Full data available
                        let horizontalAngle = abs(atan2(direction.y, direction.x) * 180 / .pi)
                        let verticalAngle = abs(atan2(direction.z,
                            sqrt(direction.x * direction.x + direction.y * direction.y)) * 180 / .pi)

                        print("📏 UWB: UPDATE \(deviceID.uuidString.prefix(8)) - distance: \(String(format: "%.3f", distance))m")
                        print("📐 UWB: UPDATE \(deviceID.uuidString.prefix(8)) - Raw vector: x=\(String(format: "%.4f", direction.x)), y=\(String(format: "%.4f", direction.y)), z=\(String(format: "%.4f", direction.z))")
                        print("📐 UWB: UPDATE \(deviceID.uuidString.prefix(8)) - h-angle: \(String(format: "%.2f", horizontalAngle))°, v-angle: \(String(format: "%.2f", verticalAngle))°")
                    } else {
                        // Distance only, no direction
                        print("📏 UWB: UPDATE \(deviceID.uuidString.prefix(8)) - distance: \(String(format: "%.3f", distance))m (NO DIRECTION DATA)")
                    }
                } else {
                    print("⚠️ UWB: UPDATE \(deviceID.uuidString.prefix(8)) - NO DISTANCE DATA")
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
