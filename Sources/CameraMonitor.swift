import CoreMediaIO
import Foundation

/// Reports when any camera is in use by any app (Zoom, Meet, FaceTime, …).
/// Only reads CoreMediaIO's "is running somewhere" flag; never opens the camera.
final class CameraMonitor {
    var onChange: ((Bool) -> Void)?
    private(set) var inUse = false
    private var watched: Set<CMIOObjectID> = []
    private var pendingOff: DispatchWorkItem?
    private var timer: Timer?
    private let offDelay: TimeInterval = 5   // ignore brief gaps, e.g. switching cameras

    func start() {
        refreshDevices()
        // Picks up newly attached cameras; also a safety net if a notification is missed.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
    }

    private func refreshDevices() {
        for id in Self.devices() where !watched.contains(id) {
            watched.insert(id)
            var addr = Self.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
            _ = CMIOObjectAddPropertyListenerBlock(id, &addr, .main) { [weak self] _, _ in
                self?.evaluate()
            }
        }
        evaluate()
    }

    private func evaluate() {
        if watched.contains(where: { Self.isRunning($0) }) {
            pendingOff?.cancel()
            pendingOff = nil
            if !inUse { inUse = true; onChange?(true) }
        } else if inUse, pendingOff == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingOff = nil
                if !self.watched.contains(where: { Self.isRunning($0) }) {
                    self.inUse = false
                    self.onChange?(false)
                }
            }
            pendingOff = work
            DispatchQueue.main.asyncAfter(deadline: .now() + offDelay, execute: work)
        }
    }

    // MARK: - CoreMediaIO helpers

    private static func address<T: BinaryInteger>(_ selector: T) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(selector),
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func devices() -> [CMIOObjectID] {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var addr = address(kCMIOHardwarePropertyDevices)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == 0, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &ids) == 0 else { return [] }
        return ids
    }

    private static func isRunning(_ id: CMIOObjectID) -> Bool {
        var addr = address(kCMIODevicePropertyDeviceIsRunningSomewhere)
        var value: UInt32 = 0, used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        guard CMIOObjectGetPropertyData(id, &addr, 0, nil, size, &used, &value) == 0 else { return false }
        return value != 0
    }
}
