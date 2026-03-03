import Foundation
import CoreGraphics
import IOKit

@MainActor
class DisplayInfo: ObservableObject, Identifiable {
    let id: CGDirectDisplayID
    let displayID: CGDirectDisplayID
    @Published var name: String
    @Published var isBuiltin: Bool
    @Published var isMain: Bool
    @Published var isOnline: Bool
    @Published var isEnabled: Bool
    @Published var bounds: CGRect
    @Published var pixelWidth: Int
    @Published var pixelHeight: Int
    @Published var rotation: Double
    @Published var brightness: Double
    @Published var availableModes: [DisplayMode]
    @Published var currentDisplayMode: DisplayMode?
    @Published var ddcValues: [UInt8: UInt16] = [:]
    let vendorNumber: UInt32
    let modelNumber: UInt32
    let serialNumber: UInt32

    init(displayID: CGDirectDisplayID) {
        self.id = displayID
        self.displayID = displayID
        let builtin = CGDisplayIsBuiltin(displayID) != 0
        self.isBuiltin = builtin
        self.isMain = CGDisplayIsMain(displayID) != 0
        self.isOnline = CGDisplayIsOnline(displayID) != 0
        self.isEnabled = CGDisplayIsActive(displayID) != 0
        self.bounds = CGDisplayBounds(displayID)
        self.pixelWidth = CGDisplayPixelsWide(displayID)
        self.pixelHeight = CGDisplayPixelsHigh(displayID)
        self.rotation = CGDisplayRotation(displayID)
        self.brightness = 50.0  // Updated async by BrightnessService.refreshBrightness
        self.availableModes = DisplayMode.availableModes(for: displayID)
        self.currentDisplayMode = DisplayMode.currentMode(for: displayID)
        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        self.vendorNumber = vendor
        self.modelNumber = model
        self.serialNumber = CGDisplaySerialNumber(displayID)

        // Resolve real display name using local variables (self cannot be used fully until all properties are initialized)
        if builtin {
            self.name = "内建显示屏"
        } else {
            self.name = DisplayInfo.lookupDisplayName(vendor: vendor, model: model) ?? "Display \(displayID)"
        }
    }

    /// Look up the product name for an external display using IOKit.
    private static func lookupDisplayName(vendor: UInt32, model: UInt32) -> String? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IODisplayConnect")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
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

            // Match by vendor and model
            let serviceVendor: UInt32
            let serviceModel: UInt32

            if let v = dict["DisplayVendorID"] as? UInt32 {
                serviceVendor = v
            } else if let v = dict["DisplayVendorID"] as? Int {
                serviceVendor = UInt32(bitPattern: Int32(truncatingIfNeeded: v))
            } else {
                continue
            }

            if let m = dict["DisplayProductID"] as? UInt32 {
                serviceModel = m
            } else if let m = dict["DisplayProductID"] as? Int {
                serviceModel = UInt32(bitPattern: Int32(truncatingIfNeeded: m))
            } else {
                continue
            }

            guard serviceVendor == vendor && serviceModel == model else {
                continue
            }

            // Extract the product name from the locale->name dictionary
            if let productNames = dict["DisplayProductName"] as? [String: String],
               let firstName = productNames.values.first {
                return firstName
            }
        }

        return nil
    }
}
