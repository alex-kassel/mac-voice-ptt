import Foundation
import AppKit

final class OverlayView: NSView {
    private var startTime: Date?
    private var timerText = "00:00"
    private var pulseOn = true
    private var timer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    func startTimer() {
        startTime = Date()
        timerText = "00:00"
        pulseOn = true
        needsDisplay = true

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateTick()
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
        startTime = nil
    }

    private func updateTick() {
        guard let start = startTime else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        let mm = elapsed / 60
        let ss = elapsed % 60
        timerText = String(format: "%02d:%02d", mm, ss)
        pulseOn.toggle()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds
        let height = bounds.size.height

        // Background rounded rectangle
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 14.0, yRadius: 14.0)
        NSColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 0.90).set()
        bgPath.fill()

        // Border
        NSColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 0.60).set()
        bgPath.lineWidth = 1.0
        bgPath.stroke()

        // Red recording dot
        let dotRadius: CGFloat = 6.0
        let dotCenter = NSPoint(x: 26.0, y: height / 2.0)
        let dotRect = NSRect(
            x: dotCenter.x - dotRadius,
            y: dotCenter.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
        let dotPath = NSBezierPath(ovalIn: dotRect)

        if pulseOn {
            NSColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 0.95).set()
        } else {
            NSColor(red: 0.8, green: 0.18, blue: 0.15, alpha: 0.80).set()
        }
        dotPath.fill()

        // Soft glow around the dot
        let glowRadius = dotRadius + 3.0
        let glowRect = NSRect(
            x: dotCenter.x - glowRadius,
            y: dotCenter.y - glowRadius,
            width: glowRadius * 2,
            height: glowRadius * 2
        )
        let glowPath = NSBezierPath(ovalIn: glowRect)
        NSColor(red: 1.0, green: 0.23, blue: 0.19, alpha: pulseOn ? 0.25 : 0.10).set()
        glowPath.fill()

        // Monospaced Timer text
        let font = NSFont.monospacedDigitSystemFont(ofSize: 20.0, weight: .regular)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(white: 0.95, alpha: 1.0)
        ]

        let attrString = NSAttributedString(string: timerText, attributes: textAttrs)
        let textSize = attrString.size()
        let textPoint = NSPoint(
            x: 42.0,
            y: (height - textSize.height) / 2.0 - 0.5
        )
        attrString.draw(at: textPoint)
    }
}

final class OverlayPanel: NSPanel {
    private let overlayView = OverlayView()

    init() {
        let contentRect = NSRect(x: 0, y: 0, width: 120, height: 38)
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false

        self.contentView = overlayView
    }

    func show() {
        DispatchQueue.main.async {
            self.updatePosition()
            self.overlayView.startTimer()
            self.orderFrontRegardless()
        }
    }

    func hide() {
        DispatchQueue.main.async {
            self.overlayView.stopTimer()
            self.orderOut(nil)
        }
    }

    private func updatePosition() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let targetScreen = screen else { return }
        let visibleFrame = targetScreen.visibleFrame
        let panelWidth: CGFloat = 120.0
        let panelHeight: CGFloat = 38.0
        let margin: CGFloat = 20.0

        let originX = visibleFrame.maxX - panelWidth - margin
        let originY = visibleFrame.maxY - panelHeight - margin

        self.setFrame(NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight), display: true)
    }
}
