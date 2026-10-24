import Foundation
import AppKit

final class OverlayPanel: NSPanel {
    private let visualEffect: NSVisualEffectView
    private let dotView: NSView
    private let timerLabel: NSTextField
    private var timer: Timer?
    private var startTime: Date?
    private var pulseOn = true

    init() {
        let panelWidth: CGFloat = 160.0
        let panelHeight: CGFloat = 44.0
        let contentRect = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        // 1. Native visual effect view (dark frosted glass HUD)
        visualEffect = NSVisualEffectView(frame: contentRect)
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = panelHeight / 2.0
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 1.0
        visualEffect.layer?.borderColor = NSColor(white: 0.35, alpha: 0.5).cgColor

        // 2. Red recording dot
        let dotSize: CGFloat = 12.0
        let dotY = (panelHeight - dotSize) / 2.0
        dotView = NSView(frame: NSRect(x: 22.0, y: dotY, width: dotSize, height: dotSize))
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = dotSize / 2.0
        dotView.layer?.backgroundColor = NSColor.systemRed.cgColor
        dotView.layer?.shadowColor = NSColor.systemRed.cgColor
        dotView.layer?.shadowRadius = 4.0
        dotView.layer?.shadowOpacity = 0.8
        dotView.layer?.shadowOffset = .zero
        visualEffect.addSubview(dotView)

        // 3. Crisp white monospaced timer label
        let labelX: CGFloat = 44.0
        let labelWidth: CGFloat = panelWidth - labelX - 16.0
        let labelY = (panelHeight - 24.0) / 2.0
        timerLabel = NSTextField(labelWithString: "00:00")
        timerLabel.frame = NSRect(x: labelX, y: labelY, width: labelWidth, height: 24.0)
        timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 18.0, weight: .semibold)
        timerLabel.textColor = .white
        timerLabel.alignment = .left
        visualEffect.addSubview(timerLabel)

        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // System-level HUD Window layer (1500) floats over all apps, spaces, and full-screen windows
        self.level = NSWindow.Level(Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.ignoresMouseEvents = true

        self.contentView = visualEffect
    }

    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }

    func show() {
        DispatchQueue.main.async {
            self.updatePosition()
            self.startTimer()
            self.alphaValue = 1.0
            self.orderFrontRegardless()
            Logger.log("[OverlayPanel] HUD Pill visible at Top-Center (level=%ld)", self.level.rawValue)
        }
    }

    func hide() {
        DispatchQueue.main.async {
            self.stopTimer()
            self.orderOut(nil)
        }
    }

    private func updatePosition() {
        // Track the screen where the mouse / user focus resides
        let mouseLoc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let targetScreen = screen else { return }
        let visibleFrame = targetScreen.visibleFrame
        let panelWidth: CGFloat = 160.0
        let panelHeight: CGFloat = 44.0

        // Center horizontally at the top of the active screen (Dynamic Island / System HUD location)
        let originX = visibleFrame.midX - (panelWidth / 2.0)
        let originY = visibleFrame.maxY - panelHeight - 24.0

        self.setFrame(NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight), display: true)
    }

    private func startTimer() {
        startTime = Date()
        timerLabel.stringValue = "00:00"
        pulseOn = true
        updatePulse()

        stopTimer()
        let t = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        startTime = nil
    }

    private func tick() {
        guard let start = startTime else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        let mm = elapsed / 60
        let ss = elapsed % 60
        timerLabel.stringValue = String(format: "%02d:%02d", mm, ss)

        pulseOn.toggle()
        updatePulse()
    }

    private func updatePulse() {
        dotView.layer?.opacity = pulseOn ? 1.0 : 0.4
    }
}
