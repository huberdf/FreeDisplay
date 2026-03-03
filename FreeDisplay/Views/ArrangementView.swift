import SwiftUI

/// Visual display arrangement view.
/// Shows all active displays as scaled thumbnails on a canvas.
/// Supports drag-to-reposition and "Set as main display" button for secondary displays.
struct ArrangementView: View {
    @EnvironmentObject var displayManager: DisplayManager
    @State private var draggedID: CGDirectDisplayID?
    @State private var dragOffset: CGSize = .zero

    private let canvasHeight: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Visual canvas
            GeometryReader { geo in
                ZStack {
                    // Grid background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.underPageBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )

                    // Display thumbnails
                    thumbnails(canvasSize: geo.size)
                }
            }
            .frame(height: canvasHeight)

            // "Set as main display" for non-main displays
            ForEach(displayManager.displays.filter { !$0.isMain }) { display in
                Button(action: {
                    let ok = ArrangementService.shared.setAsMainDisplay(
                        display.displayID,
                        among: displayManager.displays
                    )
                    if ok { displayManager.refreshDisplays() }
                }) {
                    Label("将 \(display.name) 设为主显示器", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func thumbnails(canvasSize: CGSize) -> some View {
        let layout = computeLayout(canvasSize: canvasSize)
        ForEach(displayManager.displays) { display in
            let rect = layout[display.displayID] ?? CGRect(x: canvasSize.width / 2, y: canvasSize.height / 2, width: 60, height: 40)
            let isDragged = draggedID == display.displayID
            DisplayThumbnailView(display: display, isDragged: isDragged)
                .frame(width: max(rect.width, 40), height: max(rect.height, 25))
                .position(
                    x: rect.midX + (isDragged ? dragOffset.width : 0),
                    y: rect.midY + (isDragged ? dragOffset.height : 0)
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            draggedID = display.displayID
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            applyDrag(for: display, translation: value.translation, layout: layout, canvasSize: canvasSize)
                            draggedID = nil
                            dragOffset = .zero
                        }
                )
        }
    }

    /// Computes the canvas-space rect for each display, scaled to fit the canvas.
    private func computeLayout(canvasSize: CGSize) -> [CGDirectDisplayID: CGRect] {
        let displays = displayManager.displays
        guard !displays.isEmpty else { return [:] }

        let allBounds = displays.map { CGDisplayBounds($0.displayID) }
        let minX = allBounds.map { $0.minX }.min() ?? 0
        let minY = allBounds.map { $0.minY }.min() ?? 0
        let maxX = allBounds.map { $0.maxX }.max() ?? 1
        let maxY = allBounds.map { $0.maxY }.max() ?? 1

        let totalW = maxX - minX
        let totalH = maxY - minY
        guard totalW > 0, totalH > 0 else { return [:] }

        let padding: CGFloat = 16
        let availW = canvasSize.width - padding * 2
        let availH = canvasSize.height - padding * 2

        let scale = min(availW / totalW, availH / totalH)
        let scaledW = totalW * scale
        let scaledH = totalH * scale
        let offsetX = padding + (availW - scaledW) / 2
        let offsetY = padding + (availH - scaledH) / 2

        var result: [CGDirectDisplayID: CGRect] = [:]
        for display in displays {
            let bounds = CGDisplayBounds(display.displayID)
            let x = offsetX + (bounds.minX - minX) * scale
            let y = offsetY + (bounds.minY - minY) * scale
            let w = bounds.width * scale
            let h = bounds.height * scale
            result[display.displayID] = CGRect(x: x, y: y, width: w, height: h)
        }
        return result
    }

    /// Converts the drag translation to screen coordinates and applies the new position.
    private func applyDrag(for display: DisplayInfo, translation: CGSize, layout: [CGDirectDisplayID: CGRect], canvasSize: CGSize) {
        let displays = displayManager.displays
        guard !displays.isEmpty else { return }

        let allBounds = displays.map { CGDisplayBounds($0.displayID) }
        let minX = allBounds.map { $0.minX }.min() ?? 0
        let minY = allBounds.map { $0.minY }.min() ?? 0
        let maxX = allBounds.map { $0.maxX }.max() ?? 1
        let maxY = allBounds.map { $0.maxY }.max() ?? 1

        let totalW = maxX - minX
        let totalH = maxY - minY
        guard totalW > 0, totalH > 0 else { return }

        let padding: CGFloat = 16
        let availW = canvasSize.width - padding * 2
        let availH = canvasSize.height - padding * 2
        let scale = min(availW / totalW, availH / totalH)
        guard scale > 0 else { return }

        let deltaX = Int(translation.width / scale)
        let deltaY = Int(translation.height / scale)
        let newX = Int(display.bounds.origin.x) + deltaX
        let newY = Int(display.bounds.origin.y) + deltaY

        let ok = ArrangementService.shared.setPosition(x: newX, y: newY, for: display.displayID)
        if ok { displayManager.refreshDisplays() }
    }
}

// MARK: - Display Thumbnail

private struct DisplayThumbnailView: View {
    let display: DisplayInfo
    let isDragged: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(display.isMain ? Color.blue.opacity(0.6) : Color.blue.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.blue.opacity(isDragged ? 1.0 : 0.7), lineWidth: isDragged ? 2 : 1)
                )
            VStack(spacing: 1) {
                Text(display.name)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if display.isMain {
                    Text("主")
                        .font(.system(size: 6))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .padding(2)
        }
        .shadow(radius: isDragged ? 4 : 0)
    }
}
