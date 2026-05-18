import Foundation
import Combine
import NearbyInteraction

// MARK: - Protocol for Dependency Injection
@MainActor
protocol UWBManaging: AnyObject {
    
    func stopRangingForAllDevices()
    
    /// Start UWB ranging session with a peer
    func startRanging(to deviceID: UUID)

    /// Stop UWB ranging session with a peer
    func stopRanging(to deviceID: UUID)
    
    func registerPeer(to deviceID: UUID)
    
    func getDiscoveryTokenForDeviceSession(for deviceID: UUID) -> Data?

    /// Add discovery token for this peer
    func registerPeerDiscoveryToken(from device: UUID, token: NIDiscoveryToken)

    /// Check if UWB ranging is currently active for a given peer
    func isRanging(to deviceID: UUID) -> Bool
    
    var nearbyDevices: [UUID: DevicePositionCategory] { get }
    var nearbyDevicesPublisher: AnyPublisher<[UUID: DevicePositionCategory], Never> { get }

    var nearbyDistances: [UUID: Float] { get }
    var nearbyDistancesPublisher: AnyPublisher<[UUID: Float], Never> { get }
}

enum DevicePositionCategory: UInt8 {
    case InRange = 0x01
    case ApproxTouching = 0x02
    case OutOfRange = 0x03
    case Unknown = 0x04
}

// MARK: - UWB Manager Implementation
@MainActor
class UWBManager: NSObject, UWBManaging {
    
    var myDiscoveryToken: NIDiscoveryToken?
    
    
    @Published var nearbyDevices: [UUID: DevicePositionCategory] = [:]
    @Published var nearbyDistances: [UUID: Float] = [:]
    private var devicesWithUWBRanging: Set<UUID> = []

    var nearbyDevicesPublisher: AnyPublisher<[UUID: DevicePositionCategory], Never> {
        $nearbyDevices.eraseToAnyPublisher()
    }

    var nearbyDistancesPublisher: AnyPublisher<[UUID: Float], Never> {
        $nearbyDistances.eraseToAnyPublisher()
    }

    // MARK: - Configuration
    private struct DistanceThresholds {
        static let touchingDistance: Float = 0.05     // meters (5cm) - touching range
        static let maxDistance: Float = 0.5          // meters (50cm) - maximum proximity range
    }

    // MARK: - Properties
    private var deviceToNISession: [UUID: NISession] = [:]
    private var nearbyObjects: [UUID: NINearbyObject] = [:]
    private var deviceTokens: [UUID: NIDiscoveryToken] = [:]
    private var uwbService: IUWBService

    // MARK: - Init
    override init() {
        self.uwbService = UWBService()
        super.init()
    }
    
    func registerPeer(to deviceID: UUID) {
        guard deviceToNISession[deviceID] == nil else {
            print("UWB: NISession for device \(deviceID) already exists, skipping setup")
            return
        }

        let niSession = NISession()
        niSession.delegate = self
        
        if let token = niSession.discoveryToken {
            print("✅ UWB: Session initialized successfully")
            print("📍 UWB: Discovery token available (size: \(try! NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true).count) bytes)")
        } else {
            print("⚠️ UWB: Session initialized but NO DISCOVERY TOKEN available")
        }
        deviceToNISession[deviceID] = niSession
    }
    
    func getDiscoveryTokenForDeviceSession(for deviceID: UUID) -> Data? {
        // Lazy-register: peripheral read can arrive before we've connected as central to this device
        if deviceToNISession[deviceID] == nil {
            registerPeer(to: deviceID)
        }
        guard let token = deviceToNISession[deviceID]?.discoveryToken else {
            return nil
        }
        return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }
    

    // MARK: - Setup
    private func setupSession(to deviceID: UUID) {
        // Verify device supports UWB ranging via capability check
        let caps = NISession.deviceCapabilities
        guard caps.supportsPreciseDistanceMeasurement || caps.supportsDirectionMeasurement else {
            print("❌ UWB: UWB ranging is NOT SUPPORTED on this device")
            return
        }
        
        guard deviceToNISession[deviceID] == nil else {
            print("UWB: NISession for device \(deviceID) already exists, skipping setup")
            return
        }

        let niSession = NISession()
        niSession.delegate = self
        
        if let token = niSession.discoveryToken {
            print("✅ UWB: Session initialized successfully")
            print("📍 UWB: Discovery token available (size: \(try! NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true).count) bytes)")
        } else {
            print("⚠️ UWB: Session initialized but NO DISCOVERY TOKEN available")
        }
        deviceToNISession[deviceID] = niSession
    }

    
    func registerPeerDiscoveryToken(from deviceID: UUID, token discoveryToken: NIDiscoveryToken) {
        self.deviceTokens[deviceID] = discoveryToken
    }

    func isRanging(to deviceID: UUID) -> Bool {
        devicesWithUWBRanging.contains(deviceID)
    }

    func startRanging(to deviceID: UUID) {
        
        let caps = NISession.deviceCapabilities
        print("precise distance:", caps.supportsPreciseDistanceMeasurement)
        print("direction:", caps.supportsDirectionMeasurement)
        
        print("📍 UWB: deviceTokens now has \(deviceTokens.count) token(s)")
        print("📍 UWB: nearbyObjects currently has \(nearbyObjects.count) object(s)")
        
        guard let peerToken = deviceTokens[deviceID] else {
            print("📍 UWB: Cannot Range to device : \(deviceID); peer discovery token not found")
            return
        }
        let config = NINearbyPeerConfiguration(peerToken: peerToken)
        print("📍 UWB: Created NINearbyPeerConfiguration successfully")

        deviceToNISession[deviceID]?.run(config)
        devicesWithUWBRanging.insert(deviceID)
        print("✅ UWB: Called session.run() - ranging started")
        print("📍 UWB: Total devices in ranging: \(devicesWithUWBRanging.count)")
    }


    func stopRanging(to deviceID: UUID) {
        let niSession = deviceToNISession[deviceID]
        niSession?.invalidate()
        deviceToNISession.removeValue(forKey: deviceID)
        deviceTokens.removeValue(forKey: deviceID)
        nearbyObjects.removeValue(forKey: deviceID)
        nearbyDevices.removeValue(forKey: deviceID)
        nearbyDistances.removeValue(forKey: deviceID)
        devicesWithUWBRanging.remove(deviceID)

        print("📍 UWB: Stopped ranging to \(deviceID.uuidString.prefix(8))")
    }
    
    func stopRangingForAllDevices() {
        deviceTokens.removeAll()
        nearbyDevices.removeAll()
        nearbyDistances.removeAll()
        nearbyObjects.removeAll()
        devicesWithUWBRanging.removeAll()
        for (_, niSession) in deviceToNISession {
            niSession.invalidate()
        }
        deviceToNISession.removeAll()
        print("📍 UWB: Stopped ranging for all devices")
    }
    
    
    private func getPositionCategory(updatedObject: NINearbyObject) -> DevicePositionCategory{
        var positionState = DevicePositionCategory.Unknown
        if uwbService.isApproximatelyTouching(
            nearbyObject: updatedObject) {
            positionState = DevicePositionCategory.ApproxTouching
        } else if uwbService.isNearby(nearbyObject: updatedObject) {
            positionState = DevicePositionCategory.InRange
        } else {
            positionState = DevicePositionCategory.OutOfRange
        }
        return positionState
    }

    // MARK: - Helper
    private func deviceID(for token: NIDiscoveryToken) -> UUID? {
        return deviceTokens.first(where: { $0.value == token })?.key
    }
    
    private func deviceID(for session: NISession) -> UUID? {
        return deviceToNISession.first(where: { $0.value == session })?.key
    }

    // MARK: - Diagnostics
    func printDiagnostics() {
        print("🔍 UWB: === DIAGNOSTICS ===")
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
                let positionCategory = self.getPositionCategory(updatedObject: object)

                switch positionCategory {
                    case DevicePositionCategory.ApproxTouching:
                        nearbyDevices[deviceID] = DevicePositionCategory.ApproxTouching
                    case DevicePositionCategory.InRange:
                        nearbyDevices[deviceID] = DevicePositionCategory.InRange
                    default:
                        nearbyDevices[deviceID] = DevicePositionCategory.OutOfRange
                }

                if let distance = object.distance {
                    nearbyDistances[deviceID] = distance
                    print("📏 UWB: UPDATE \(deviceID.uuidString.prefix(8)) - distance: \(String(format: "%.3f", distance))m")
                } else {
                    nearbyDistances.removeValue(forKey: deviceID)
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
                self.nearbyDevices.removeValue(forKey: deviceID)
                self.nearbyDistances.removeValue(forKey: deviceID)
                session.invalidate()
                print("📍 UWB: Lost connection to \(deviceID.uuidString.prefix(8)), reason: \(reason.rawValue)")
            }
            printDiagnostics()
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        Task { @MainActor in
            print("⚠️ UWB: Session invalidated - \(error.localizedDescription)")
            guard let disconnectedDeviceID = deviceID(for: session) else {
                return
            }
            deviceToNISession.removeValue(forKey: disconnectedDeviceID)
            nearbyObjects.removeValue(forKey: disconnectedDeviceID)
            nearbyDevices.removeValue(forKey: disconnectedDeviceID)
            nearbyDistances.removeValue(forKey: disconnectedDeviceID)
            deviceTokens.removeValue(forKey: disconnectedDeviceID)
            devicesWithUWBRanging.remove(disconnectedDeviceID)
        }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {
        Task { @MainActor in
            print("⚠️ UWB: Session suspended")
            printDiagnostics()
        }
    }

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        Task { @MainActor in
            print("✅ UWB: Session resumed")
            printDiagnostics()
            self.deviceTokens.forEach { (deviceId: UUID, token: NIDiscoveryToken) in
                self.startRanging(to: deviceId)
            }
        }
    }
    

    nonisolated func sessionDidStartRunning(_ session: NISession) {
        Task { @MainActor in
            print("UWB: Session did start running")
            print("UWB: Session received by delegate callback: \(session)")
            printDiagnostics()
        }
    }
}
