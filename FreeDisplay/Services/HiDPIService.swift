import Foundation
import CoreGraphics
import IOKit

@MainActor
final class HiDPIService: @unchecked Sendable {
    static let shared = HiDPIService()
    private init() {}

    private let overridesBase = URL(fileURLWithPath: "/Library/Displays/Contents/Resources/Overrides")

    // MARK: - Public API

    func isHiDPIEnabled(vendor: UInt32, product: UInt32) -> Bool {
        let plistURL = overridePlistURL(vendor: vendor, product: product)
        return FileManager.default.fileExists(atPath: plistURL.path)
    }

    func enableHiDPI(vendor: UInt32, product: UInt32, nativeWidth: Int, nativeHeight: Int) -> String? {
        let dir = overrideDir(vendor: vendor, product: product)
        let plistURL = overridePlistURL(vendor: vendor, product: product)

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return "无法创建 Override 目录：\(error.localizedDescription)（可能需要管理员权限）"
        }

        let scaledModes = generateScaledModes(nativeWidth: nativeWidth, nativeHeight: nativeHeight)
        let plist: [String: Any] = [
            "DisplayProductName": "FreeDisplay HiDPI Override",
            "scale-resolutions": scaledModes
        ]

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        } catch {
            return "写入 Override Plist 失败：\(error.localizedDescription)"
        }

        // Attempt to trigger display mode re-enumeration via IOServiceRequestProbe
        triggerDisplayReenumeration(vendor: vendor, product: product)

        return nil
    }

    func disableHiDPI(vendor: UInt32, product: UInt32) -> String? {
        let plistURL = overridePlistURL(vendor: vendor, product: product)
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return nil }
        do {
            try FileManager.default.removeItem(at: plistURL)
            return nil
        } catch {
            return "无法删除 Override Plist：\(error.localizedDescription)"
        }
    }

    /// Refreshes availableModes on the given DisplayInfo after enabling HiDPI.
    func refreshModes(for display: DisplayInfo) {
        display.availableModes = DisplayMode.availableModes(for: display.displayID)
        display.currentDisplayMode = DisplayMode.currentMode(for: display.displayID)
    }

    // MARK: - Helpers

    private func triggerDisplayReenumeration(vendor: UInt32, product: UInt32) {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IODisplayConnect")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let cfDict = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName))?.takeRetainedValue() else {
                continue
            }
            let dict = cfDict as NSDictionary

            let serviceVendor: UInt32
            let serviceProduct: UInt32

            if let v = dict["DisplayVendorID"] as? UInt32 {
                serviceVendor = v
            } else if let v = dict["DisplayVendorID"] as? Int {
                serviceVendor = UInt32(bitPattern: Int32(truncatingIfNeeded: v))
            } else { continue }

            if let p = dict["DisplayProductID"] as? UInt32 {
                serviceProduct = p
            } else if let p = dict["DisplayProductID"] as? Int {
                serviceProduct = UInt32(bitPattern: Int32(truncatingIfNeeded: p))
            } else { continue }

            guard serviceVendor == vendor && serviceProduct == product else { continue }

            IOServiceRequestProbe(service, 0)
            break
        }
    }

    private func overrideDir(vendor: UInt32, product: UInt32) -> URL {
        overridesBase
            .appendingPathComponent(String(format: "DisplayVendorID-%x", vendor))
    }

    private func overridePlistURL(vendor: UInt32, product: UInt32) -> URL {
        overrideDir(vendor: vendor, product: product)
            .appendingPathComponent(String(format: "DisplayProductID-%x", product))
    }

    private func generateScaledModes(nativeWidth: Int, nativeHeight: Int) -> [Data] {
        let scales: [Double] = [0.5, 0.625, 0.75, 1.0]
        var result: [Data] = []
        for scale in scales {
            let w = Int((Double(nativeWidth) * scale).rounded()) & ~1
            let h = Int((Double(nativeHeight) * scale).rounded()) & ~1
            guard w >= 800, h >= 600 else { continue }
            var bytes = [UInt8](repeating: 0, count: 8)
            bytes[0] = UInt8((w >> 24) & 0xFF)
            bytes[1] = UInt8((w >> 16) & 0xFF)
            bytes[2] = UInt8((w >> 8) & 0xFF)
            bytes[3] = UInt8(w & 0xFF)
            bytes[4] = UInt8((h >> 24) & 0xFF)
            bytes[5] = UInt8((h >> 16) & 0xFF)
            bytes[6] = UInt8((h >> 8) & 0xFF)
            bytes[7] = UInt8(h & 0xFF)
            result.append(Data(bytes))
        }
        return result
    }
}
