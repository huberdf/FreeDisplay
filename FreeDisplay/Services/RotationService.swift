import Foundation
import CoreGraphics
import IOKit
import IOKit.graphics

/// Service for reading and setting display rotation via IOKit.
/// Finds the IOFramebuffer by walking the IOKit registry from IODisplayConnect,
/// matching by vendor/model ID — same approach used by DDCService.
@MainActor
class RotationService {
    static let shared = RotationService()
    private init() {}

    // kIOFBSetTransform = 0x00000400 from <IOKit/graphics/IOGraphicsLib.h>
    private let kIOFBSetTransformOption: UInt32 = 0x00000400

    /// Returns the current rotation in degrees (0, 90, 180, or 270).
    func currentRotation(for displayID: CGDirectDisplayID) -> Int {
        Int(CGDisplayRotation(displayID))
    }

    /// Attempts to set the screen rotation using IOKit framebuffer transform.
    /// - Parameters:
    ///   - degrees: Rotation in degrees: 0, 90, 180, or 270.
    ///   - displayID: The target display.
    /// - Returns: true if the IOServiceRequestProbe call succeeded.
    @discardableResult
    func setRotation(_ degrees: Int, for displayID: CGDirectDisplayID) -> Bool {
        guard let framebuffer = framebufferService(for: displayID) else { return false }
        defer { IOObjectRelease(framebuffer) }

        // IOFBTransform rotation index: 0=0°, 1=90° CW, 2=180°, 3=270° CW
        let rotationIndex: UInt32
        switch degrees {
        case 90:  rotationIndex = 1
        case 180: rotationIndex = 2
        case 270: rotationIndex = 3
        default:  rotationIndex = 0
        }

        IORegistryEntrySetCFProperty(
            framebuffer,
            "IOFBTransform" as CFString,
            NSNumber(value: rotationIndex)
        )

        let result = IOServiceRequestProbe(framebuffer, kIOFBSetTransformOption)
        return result == KERN_SUCCESS
    }

    // MARK: - IOKit Registry Traversal (mirrors DDCService.framebufferService)

    /// Finds the IOFramebuffer service for a given display by matching vendor/model
    /// on the IODisplayConnect registry entry, then walking up to the parent framebuffer.
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
}
