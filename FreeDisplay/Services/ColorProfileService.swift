import Foundation
import CoreGraphics
@preconcurrency import ColorSync

/// ICC color profile model.
struct ICCProfile: Identifiable, Equatable {
    let id: UUID
    let name: String
    let path: URL
    let colorSpaceType: String  // "RGB", "CMYK", "Gray", etc.

    init(name: String, path: URL, colorSpaceType: String) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.colorSpaceType = colorSpaceType
    }

    /// Convenience failable initializer: loads profile metadata from a file URL.
    init?(url: URL) {
        guard let profile = ColorProfileService.makeProfile(from: url) else { return nil }
        self = profile
    }

    static func == (lhs: ICCProfile, rhs: ICCProfile) -> Bool {
        lhs.path == rhs.path
    }
}

/// Service for ICC color profile enumeration and switching.
/// Uses ColorSync framework + file system scanning.
final class ColorProfileService: @unchecked Sendable {
    static let shared = ColorProfileService()
    private init() {}

    // MARK: - Profile Enumeration

    /// Returns all installed ICC profiles sorted alphabetically.
    func enumerateProfiles() async -> [ICCProfile] {
        await Task.detached(priority: .userInitiated) {
            var profiles: [ICCProfile] = []
            let searchURLs: [URL] = [
                URL(fileURLWithPath: "/Library/ColorSync/Profiles"),
                URL(fileURLWithPath: "/System/Library/ColorSync/Profiles"),
                URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent("Library/ColorSync/Profiles")
            ]

            var seenPaths = Set<URL>()
            let fm = FileManager.default

            for dir in searchURLs {
                guard let enumerator = fm.enumerator(
                    at: dir,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                while let url = enumerator.nextObject() as? URL {
                    guard !seenPaths.contains(url) else { continue }
                    let ext = url.pathExtension.lowercased()
                    guard ext == "icc" || ext == "icm" else { continue }
                    seenPaths.insert(url)
                    if let profile = Self.makeProfileImpl(from: url) {
                        profiles.append(profile)
                    }
                }
            }

            return profiles.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }.value
    }

    static func makeProfile(from url: URL) -> ICCProfile? {
        makeProfileImpl(from: url)
    }

    private static func makeProfileImpl(from url: URL) -> ICCProfile? {
        guard let rawProfile = ColorSyncProfileCreateWithURL(url as CFURL, nil) else { return nil }
        let profile = rawProfile.takeRetainedValue()

        // Only RGB display-class profiles can be assigned to a display. Applying a CMYK, gray,
        // Lab/XYZ, abstract or named-color profile makes WindowServer's color space registry
        // abort the app (assertion in SkyLight), so those are not offered.
        guard headerTag(profile, offset: 12) == "mntr",
              headerTag(profile, offset: 16) == "RGB " else { return nil }

        let name: String
        if let rawDesc = ColorSyncProfileCopyDescriptionString(profile) {
            name = rawDesc.takeRetainedValue() as String
        } else {
            name = url.deletingPathExtension().lastPathComponent
        }
        return ICCProfile(name: name, path: url, colorSpaceType: colorSpaceType(from: profile))
    }

    private static func colorSpaceType(from profile: ColorSyncProfile) -> String {
        switch headerTag(profile, offset: 16)?.trimmingCharacters(in: .whitespaces) {
        case "RGB":  return "RGB"
        case "CMYK": return "CMYK"
        case "GRAY": return "Gray"
        case "Lab":  return "Lab"
        case "XYZ":  return "XYZ"
        default:     return "RGB"
        }
    }

    /// Reads a 4-character signature from the ICC header (offset 12 = device class,
    /// 16 = data color space). Uses the raw big-endian profile bytes:
    /// ColorSyncProfileCopyHeader returns fields byte-swapped to host order ("BGR " for RGB).
    private static func headerTag(_ profile: ColorSyncProfile, offset: Int) -> String? {
        guard let raw = ColorSyncProfileCopyData(profile, nil)?.takeRetainedValue() as Data?,
              raw.count >= offset + 4 else { return nil }
        let bytes = [UInt8](raw[raw.startIndex + offset ..< raw.startIndex + offset + 4])
        // Non-printable bytes mean a corrupt or non-standard header.
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 <= 0x7E }) else { return nil }
        return String(bytes: bytes, encoding: .ascii)
    }

    // MARK: - Current Color Info

    /// Returns the human-readable color space name for the given display.
    func currentColorSpaceName(for displayID: CGDirectDisplayID) -> String {
        let colorSpace = CGDisplayCopyColorSpace(displayID)
        // Prefer the active ICC profile's description: display-specific profiles
        // (e.g. EDID-generated "GF270M") have no CGColorSpace name, and this matches
        // the names shown in the profile list.
        if let data = colorSpace.copyICCData(),
           let profile = ColorSyncProfileCreate(data, nil)?.takeRetainedValue(),
           let desc = ColorSyncProfileCopyDescriptionString(profile)?.takeRetainedValue() {
            return desc as String
        }
        guard let cfName = colorSpace.name else { return L("Bilinmiyor", "Unknown") }
        return humanReadable(cfName as String)
    }

    /// Returns a description like "Dahili (8-bit)" for the display's current color mode.
    func colorModeDescription(for displayID: CGDirectDisplayID) -> String {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else { return L("Bilinmiyor", "Unknown") }
        let encoding: String
        if let cfEnc = mode.pixelEncoding { encoding = cfEnc as String } else { encoding = "" }
        let bpc = bitsPerChannel(from: encoding)
        let source = CGDisplayIsBuiltin(displayID) != 0 ? L("Dahili", "Internal") : L("Harici", "External")
        return "\(source) (\(bpc)-bit)"
    }

    private func bitsPerChannel(from encoding: String) -> Int {
        let rCount = encoding.filter { $0 == "R" }.count
        if rCount > 0 { return rCount }
        let dCount = encoding.filter { $0 == "D" }.count
        return dCount >= 30 ? 10 : 8
    }

    // Bridge CGColorSpace CFString constants to Swift String for comparison
    private func humanReadable(_ name: String) -> String {
        if name == (CGColorSpace.displayP3 as String)           { return "Display P3" }
        if name == (CGColorSpace.sRGB as String)                { return "sRGB IEC61966-2.1" }
        if name == (CGColorSpace.adobeRGB1998 as String)        { return "Adobe RGB (1998)" }
        if name == (CGColorSpace.genericRGBLinear as String)    { return "Generic RGB Linear" }
        if name == (CGColorSpace.extendedSRGB as String)        { return "Extended sRGB" }
        if name == (CGColorSpace.linearSRGB as String)          { return "Linear sRGB" }
        if name == (CGColorSpace.extendedLinearSRGB as String)  { return "Extended Linear sRGB" }
        if name == (CGColorSpace.genericGrayGamma2_2 as String) { return "Generic Gray Gamma 2.2" }
        if name.hasPrefix("kCGColorSpace") {
            return String(name.dropFirst("kCGColorSpace".count))
        }
        return name
    }

    // MARK: - Current Profile URL

    /// Returns the file URL of the currently active ICC profile for the given display, if available.
    func currentProfileURL(for displayID: CGDirectDisplayID) -> URL? {
        guard let rawUUID = CGDisplayCreateUUIDFromDisplayID(displayID) else { return nil }
        let uuid = rawUUID.takeRetainedValue()

        guard let deviceClass = kColorSyncDisplayDeviceClass?.takeUnretainedValue(),
              let profileIDKey = kColorSyncDeviceDefaultProfileID?.takeUnretainedValue()
        else { return nil }

        guard let rawInfo = ColorSyncDeviceCopyDeviceInfo(deviceClass, uuid) else { return nil }
        let info = rawInfo.takeRetainedValue() as NSDictionary

        // Determine the active mode name from FactoryProfiles[DeviceDefaultProfileID].
        // Both CustomProfiles and FactoryProfiles use this mode name as their key.
        let factoryProfiles = info["FactoryProfiles"] as? NSDictionary
        let activeModeName = factoryProfiles?[profileIDKey] as? String

        // CustomProfiles: keys are mode names, values are NSURL directly.
        if let modeName = activeModeName,
           let customProfiles = info["CustomProfiles"] as? NSDictionary,
           let url = customProfiles[modeName] as? NSURL {
            return url as URL
        }

        // Fall back to FactoryProfiles: the mode entry is a dict with a DeviceProfileURL string.
        if let modeName = activeModeName,
           let modeDict = factoryProfiles?[modeName] as? NSDictionary,
           let urlString = modeDict["DeviceProfileURL"] as? String {
            return URL(string: urlString)
        }

        return nil
    }

    // MARK: - Profile Switching

    /// Sets the ICC profile for the given display using ColorSync.
    /// Returns true on success.
    @discardableResult
    func setProfile(_ profile: ICCProfile, for displayID: CGDirectDisplayID) -> Bool {
        guard let rawUUID = CGDisplayCreateUUIDFromDisplayID(displayID) else { return false }
        let uuid = rawUUID.takeRetainedValue()

        // kColorSyncDisplayDeviceClass and kColorSyncDeviceDefaultProfileID are
        // Unmanaged<CFString>? in the current SDK; use takeUnretainedValue() to borrow them.
        guard let deviceClass = kColorSyncDisplayDeviceClass?.takeUnretainedValue(),
              let profileIDKey = kColorSyncDeviceDefaultProfileID?.takeUnretainedValue()
        else { return false }

        let profileInfo: NSDictionary = [profileIDKey: profile.path as NSURL]

        return ColorSyncDeviceSetCustomProfiles(
            deviceClass,
            uuid,
            profileInfo as CFDictionary
        )
    }
}
