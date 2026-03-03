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
    func enumerateProfiles() -> [ICCProfile] {
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

            for case let url as URL in enumerator {
                guard !seenPaths.contains(url) else { continue }
                let ext = url.pathExtension.lowercased()
                guard ext == "icc" || ext == "icm" else { continue }
                seenPaths.insert(url)
                if let profile = makeProfile(from: url) {
                    profiles.append(profile)
                }
            }
        }

        return profiles.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func makeProfile(from url: URL) -> ICCProfile? {
        let name: String
        let csType: String

        if let rawProfile = ColorSyncProfileCreateWithURL(url as CFURL, nil) {
            let profile = rawProfile.takeRetainedValue()
            if let rawDesc = ColorSyncProfileCopyDescriptionString(profile) {
                name = rawDesc.takeRetainedValue() as String
            } else {
                name = url.deletingPathExtension().lastPathComponent
            }
            csType = colorSpaceType(from: profile)
        } else {
            name = url.deletingPathExtension().lastPathComponent
            csType = "RGB"
        }

        return ICCProfile(name: name, path: url, colorSpaceType: csType)
    }

    private func colorSpaceType(from profile: ColorSyncProfile) -> String {
        guard let rawData = ColorSyncProfileCopyHeader(profile) else { return "RGB" }
        let data = rawData.takeRetainedValue() as Data
        // ICC header: data color space at byte offset 16, 4 bytes
        guard data.count >= 20 else { return "RGB" }
        let bytes = [UInt8](data[16..<20])
        let str = String(bytes: bytes, encoding: .ascii) ?? "RGB "
        switch str.trimmingCharacters(in: .whitespaces) {
        case "RGB":  return "RGB"
        case "CMYK": return "CMYK"
        case "GRAY": return "Gray"
        case "LAB":  return "Lab"
        case "XYZ":  return "XYZ"
        default:     return "RGB"
        }
    }

    // MARK: - Current Color Info

    /// Returns the human-readable color space name for the given display.
    func currentColorSpaceName(for displayID: CGDirectDisplayID) -> String {
        let colorSpace = CGDisplayCopyColorSpace(displayID)
        guard let cfName = colorSpace.name else { return "未知" }
        return humanReadable(cfName as String)
    }

    /// Returns a description like "内部 (8-bit)" for the display's current color mode.
    func colorModeDescription(for displayID: CGDirectDisplayID) -> String {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else { return "未知" }
        let encoding: String
        if let cfEnc = mode.pixelEncoding { encoding = cfEnc as String } else { encoding = "" }
        let bpc = bitsPerChannel(from: encoding)
        let source = CGDisplayIsBuiltin(displayID) != 0 ? "内部" : "外部"
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
