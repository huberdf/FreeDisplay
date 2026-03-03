import Foundation
import CoreGraphics
import IOKit
import IOKit.i2c
import IOKit.graphics

/// DDC/CI I2C communication service for external displays.
/// All I2C operations run on a private background queue to avoid blocking UI.
final class DDCService: @unchecked Sendable {
    static let shared = DDCService()

    // VCP feature codes (DDC/CI standard)
    static let brightnessVCP: UInt8 = 0x10
    static let contrastVCP: UInt8   = 0x12
    static let powerVCP: UInt8      = 0xD6

    private let ddcQueue = DispatchQueue(label: "com.freedisplay.ddc", qos: .userInitiated)

    // MARK: - VCP Read Cache (5-second TTL)

    private struct VCPCacheEntry {
        let current: UInt16
        let max: UInt16
        let timestamp: Date
        var isExpired: Bool { Date().timeIntervalSince(timestamp) > 5.0 }
    }

    private var vcpCache: [CGDirectDisplayID: [UInt8: VCPCacheEntry]] = [:]
    private let cacheLock = NSLock()

    private init() {}

    // MARK: - IOKit Registry Traversal

    /// Finds the IOFramebuffer service for a given external display by matching
    /// vendor and model numbers via the IODisplayConnect registry entry.
    /// Returns a retained io_service_t — caller must IOObjectRelease.
    private func framebufferService(for displayID: CGDirectDisplayID) -> io_service_t? {
        let vendor = CGDisplayVendorNumber(displayID)
        let model  = CGDisplayModelNumber(displayID)

        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iter
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iter) }

            guard let cfDict = IODisplayCreateInfoDictionary(
                service,
                IOOptionBits(kIODisplayOnlyPreferredName)
            )?.takeRetainedValue() as? NSDictionary else { continue }

            // Extract vendor and model IDs (may be stored as UInt32 or Int)
            let sVendor: UInt32
            let sModel: UInt32
            if let v = cfDict["DisplayVendorID"] as? UInt32 { sVendor = v }
            else if let v = cfDict["DisplayVendorID"] as? Int {
                sVendor = UInt32(bitPattern: Int32(truncatingIfNeeded: v))
            } else { continue }

            if let m = cfDict["DisplayProductID"] as? UInt32 { sModel = m }
            else if let m = cfDict["DisplayProductID"] as? Int {
                sModel = UInt32(bitPattern: Int32(truncatingIfNeeded: m))
            } else { continue }

            guard sVendor == vendor && sModel == model else { continue }

            // Walk up to parent IOFramebuffer
            var parent: io_service_t = 0
            guard IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS,
                  parent != 0 else { continue }
            // Caller must release parent
            return parent
        }
        return nil
    }

    // MARK: - DDC Checksum

    /// Computes DDC/CI checksum: XOR of destination address + all buffer bytes.
    private func ddcChecksum(destAddress: UInt8, bytes: [UInt8]) -> UInt8 {
        var cs: UInt8 = destAddress
        for b in bytes { cs ^= b }
        return cs
    }

    // MARK: - Synchronous DDC I/O (called on ddcQueue)

    /// Synchronous DDC write (VCP Set). Returns true on success.
    private func writeSynchronous(displayID: CGDirectDisplayID, command: UInt8, value: UInt16) -> Bool {
        guard let fb = framebufferService(for: displayID) else { return false }
        defer { IOObjectRelease(fb) }

        var iface: io_service_t = 0
        guard IOFBCopyI2CInterfaceForBus(fb, 0, &iface) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iface) }

        var conn: IOI2CConnectRef?
        guard IOI2CInterfaceOpen(iface, IOOptionBits(0), &conn) == KERN_SUCCESS,
              let conn = conn else { return false }
        defer { IOI2CInterfaceClose(conn, IOOptionBits(0)) }

        // Build DDC/CI Set VCP packet:
        // [0x51, 0x84, 0x03, VCP, val_hi, val_lo, checksum]
        var buf: [UInt8] = [
            0x51,
            0x84,
            0x03,
            command,
            UInt8(value >> 8),
            UInt8(value & 0xFF)
        ]
        buf.append(ddcChecksum(destAddress: 0x6E, bytes: buf))
        let bufCount = buf.count  // capture before mutable borrow

        return buf.withUnsafeMutableBytes { raw -> Bool in
            guard let ptr = raw.baseAddress else { return false }
            var req = IOI2CRequest()
            req.commFlags           = 0
            req.sendAddress         = 0x6E
            req.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
            req.sendSubAddress      = 0
            req.sendBuffer          = UInt(bitPattern: ptr)
            req.sendBytes           = UInt32(bufCount)
            req.replyTransactionType = IOOptionBits(kIOI2CNoTransactionType)
            req.replyBytes          = 0
            req.minReplyDelay       = 10_000_000 // 10ms
            return IOI2CSendRequest(conn, IOOptionBits(0), &req) == KERN_SUCCESS
        }
    }

    /// Synchronous DDC read (VCP Get). Returns (current, max) or nil on failure.
    private func readSynchronous(displayID: CGDirectDisplayID, command: UInt8) -> (current: UInt16, max: UInt16)? {
        guard let fb = framebufferService(for: displayID) else { return nil }
        defer { IOObjectRelease(fb) }

        var iface: io_service_t = 0
        guard IOFBCopyI2CInterfaceForBus(fb, 0, &iface) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iface) }

        var conn: IOI2CConnectRef?
        guard IOI2CInterfaceOpen(iface, IOOptionBits(0), &conn) == KERN_SUCCESS,
              let conn = conn else { return nil }
        defer { IOI2CInterfaceClose(conn, IOOptionBits(0)) }

        // Build DDC/CI Get VCP request:
        // [0x51, 0x82, 0x01, VCP, checksum]
        var sendBuf: [UInt8] = [0x51, 0x82, 0x01, command]
        sendBuf.append(ddcChecksum(destAddress: 0x6E, bytes: sendBuf))

        var replyBuf = [UInt8](repeating: 0, count: 12)
        var result: (current: UInt16, max: UInt16)? = nil

        // Capture counts before mutable borrows to avoid exclusive-access violations
        let sendCount  = sendBuf.count
        let replyCount = replyBuf.count

        sendBuf.withUnsafeMutableBytes { sendRaw in
            replyBuf.withUnsafeMutableBytes { replyRaw in
                guard let sp = sendRaw.baseAddress,
                      let rp = replyRaw.baseAddress else { return }

                var req = IOI2CRequest()
                req.commFlags           = 0
                req.sendAddress         = 0x6E
                req.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
                req.sendSubAddress      = 0
                req.sendBuffer          = UInt(bitPattern: sp)
                req.sendBytes           = UInt32(sendCount)
                req.replyAddress        = 0x6F
                req.replyTransactionType = IOOptionBits(kIOI2CDDCciReplyTransactionType)
                req.replySubAddress     = 0
                req.replyBuffer         = UInt(bitPattern: rp)
                req.replyBytes          = UInt32(replyCount)
                req.minReplyDelay       = 50_000_000 // 50ms

                guard IOI2CSendRequest(conn, IOOptionBits(0), &req) == KERN_SUCCESS,
                      req.result == KERN_SUCCESS else { return }

                // DDC/CI VCP reply layout:
                // [0x6E, 0x88, 0x02, errCode, VCPcode, type, max_hi, max_lo, cur_hi, cur_lo, chk]
                // Read via raw pointer to avoid overlapping-access when replyBuf is mutably borrowed.
                let rb = replyRaw.bindMemory(to: UInt8.self)
                let maxVal = (UInt16(rb[6]) << 8) | UInt16(rb[7])
                let curVal = (UInt16(rb[8]) << 8) | UInt16(rb[9])
                result = (current: curVal, max: maxVal)
            }
        }
        return result
    }

    // MARK: - Public Async API (with retry)

    /// Asynchronously write a VCP value, retrying up to 3 times.
    /// Invalidates the cache for the written VCP code on success.
    func writeAsync(
        displayID: CGDirectDisplayID,
        command: UInt8,
        value: UInt16,
        completion: ((Bool) -> Void)? = nil
    ) {
        ddcQueue.async {
            for attempt in 0..<3 {
                if self.writeSynchronous(displayID: displayID, command: command, value: value) {
                    // Invalidate cached value so next read reflects the new setting
                    self.cacheLock.lock()
                    self.vcpCache[displayID]?[command] = nil
                    self.cacheLock.unlock()
                    completion?(true)
                    return
                }
                if attempt < 2 { Thread.sleep(forTimeInterval: 0.05) }
            }
            completion?(false)
        }
    }

    /// Asynchronously read a VCP value.
    /// Returns a cached result if available and not expired (5-second TTL).
    func readAsync(
        displayID: CGDirectDisplayID,
        command: UInt8,
        completion: @escaping ((current: UInt16, max: UInt16)?) -> Void
    ) {
        // Fast path: return cached value if still fresh
        cacheLock.lock()
        if let entry = vcpCache[displayID]?[command], !entry.isExpired {
            cacheLock.unlock()
            completion((current: entry.current, max: entry.max))
            return
        }
        cacheLock.unlock()

        ddcQueue.async {
            for attempt in 0..<3 {
                if let r = self.readSynchronous(displayID: displayID, command: command) {
                    self.cacheLock.lock()
                    if self.vcpCache[displayID] == nil { self.vcpCache[displayID] = [:] }
                    self.vcpCache[displayID]![command] = VCPCacheEntry(
                        current: r.current, max: r.max, timestamp: Date()
                    )
                    self.cacheLock.unlock()
                    completion(r)
                    return
                }
                if attempt < 2 { Thread.sleep(forTimeInterval: 0.05) }
            }
            completion(nil)
        }
    }

    /// Reads a batch of common VCP codes and calls completion on the main thread with the results.
    /// Only meaningful for external displays; built-in displays will return an empty dict.
    func readBatchVCPCodes(
        displayID: CGDirectDisplayID,
        completion: @escaping ([UInt8: UInt16]) -> Void
    ) {
        let codes: [UInt8] = [0x10, 0x12, 0x14, 0x16, 0x18, 0x1A, 0x60, 0x62, 0x87, 0xD6, 0xDC]
        ddcQueue.async {
            var result: [UInt8: UInt16] = [:]
            for code in codes {
                if let r = self.readSynchronous(displayID: displayID, command: code) {
                    result[code] = r.current
                    self.cacheLock.lock()
                    if self.vcpCache[displayID] == nil { self.vcpCache[displayID] = [:] }
                    self.vcpCache[displayID]![code] = VCPCacheEntry(
                        current: r.current, max: r.max, timestamp: Date()
                    )
                    self.cacheLock.unlock()
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
