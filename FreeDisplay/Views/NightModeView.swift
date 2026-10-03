import SwiftUI

/// "Night Mode" section: Off / On / Scheduled, start and end times, and a warmth slider.
struct NightModeView: View {
    @ObservedObject private var service = NightModeService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $service.mode) {
                Text(L("Kapalı", "Off")).tag(NightModeService.Mode.off)
                Text(L("Açık", "On")).tag(NightModeService.Mode.on)
                Text(L("Zamanlı", "Schedule")).tag(NightModeService.Mode.scheduled)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .help(L("Gece modunu kapat, aç veya günlük zamanla", "Turn night mode off, on, or run it on a daily schedule"))

            if service.mode == .scheduled {
                HStack(spacing: 6) {
                    NightModeTimeField(label: L("Başlangıç", "From"), minutes: $service.startMinutes)
                    Spacer(minLength: 8)
                    NightModeTimeField(label: L("Bitiş", "To"), minutes: $service.endMinutes)
                }
            }

            if service.mode != .off {
                HStack(spacing: 6) {
                    Image(systemName: "sun.max")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                    Slider(value: $service.warmth, in: 0...1)
                        .controlSize(.small)
                        .accessibilityLabel(L("Sıcaklık", "Warmth"))
                    Image(systemName: "flame")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .accessibilityHidden(true)
                }
                .help(L("Filtrenin ne kadar sıcak (turuncu) olacağı", "How warm (orange) the filter is"))
            }

            Text(statusText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .animation(.easeInOut(duration: 0.2), value: service.mode)
    }

    private var statusText: String {
        switch service.mode {
        case .off:
            return L("Mavi ışığı azaltmak için ekran renklerini ısıtır", "Warms screen colors to reduce blue light")
        case .on:
            return L("Gece modu açık", "Night mode is on")
        case .scheduled:
            if service.isActive {
                return L("Şu an açık · bitiş \(NightModeService.timeString(service.endMinutes))",
                         "On now · until \(NightModeService.timeString(service.endMinutes))")
            } else if service.startMinutes == service.endMinutes {
                return L("Başlangıç ve bitiş aynı olamaz", "Start and end times must differ")
            } else {
                return L("Şu an kapalı · başlangıç \(NightModeService.timeString(service.startMinutes))",
                         "Off now · starts at \(NightModeService.timeString(service.startMinutes))")
            }
        }
    }

    /// Short label for the collapsed row in MenuBarView.
    static func subtitle(for service: NightModeService) -> String {
        switch service.mode {
        case .off:
            return L("Kapalı", "Off")
        case .on:
            return L("Açık", "On")
        case .scheduled:
            return "\(NightModeService.timeString(service.startMinutes))–\(NightModeService.timeString(service.endMinutes))"
        }
    }
}

// MARK: - NightModeTimeField

/// Labeled hour:minute field bound to minutes after midnight.
private struct NightModeTimeField: View {
    let label: String
    @Binding var minutes: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            DatePicker(
                "",
                selection: Binding(
                    get: { NightModeService.date(forMinutes: minutes) },
                    set: { minutes = NightModeService.minutes(from: $0) }
                ),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.field)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .accessibilityLabel(label)
        }
    }
}
