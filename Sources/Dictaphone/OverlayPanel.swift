import Foundation
import AppKit

final class OverlayPanel: NSPanel {
    private let containerView: NSView
    private let dotView: NSView
    private let timerLabel: NSTextField
    private var timer: Timer?
    private var startTime: Date?
    private var pulseOn = true

    init() {
        let panelWidth: CGFloat = 136.0
        let panelHeight: CGFloat = 38.0
        let contentRect = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        // 1. Dark high-contrast background container (forced dark theme, never white)
        containerView = NSView(frame: contentRect)
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 0.95).cgColor
        containerView.layer?.cornerRadius = 14.0
        containerView.layer?.masksToBounds = true
        containerView.layer?.borderWidth = 1.0
        containerView.layer?.borderColor = NSColor(white: 0.30, alpha: 0.8).cgColor

        // 2. Bright glowing red recording dot
        let dotSize: CGFloat = 10.0
        let dotY = (panelHeight - dotSize) / 2.0
        dotView = NSView(frame: NSRect(x: 18.0, y: dotY, width: dotSize, height: dotSize))
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = dotSize / 2.0
        dotView.layer?.backgroundColor = NSColor.systemRed.cgColor
        dotView.layer?.shadowColor = NSColor.systemRed.cgColor
        dotView.layer?.shadowRadius = 4.0
        dotView.layer?.shadowOpacity = 0.9
        dotView.layer?.shadowOffset = .zero
        containerView.addSubview(dotView)

        // 3. Crisp, 100% white monospaced timer label (pure white on solid dark)
        let labelX: CGFloat = 38.0
        let labelWidth: CGFloat = panelWidth - labelX - 12.0
        let labelY = (panelHeight - 22.0) / 2.0
        timerLabel = NSTextField(labelWithString: "00:00")
        timerLabel.frame = NSRect(x: labelX, y: labelY, width: labelWidth, height: 22.0)
        timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 18.0, weight: .bold)
        timerLabel.textColor = .white
        timerLabel.backgroundColor = .clear
        timerLabel.isBezeled = false
        timerLabel.isEditable = false
        timerLabel.alignment = .left
        containerView.addSubview(timerLabel)

        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Enforce dark appearance on the panel
        self.appearance = NSAppearance(named: .darkAqua)

        // Level 1500 (assistiveTechHighWindow) floats above all spaces, full-screen windows, and apps
        self.level = NSWindow.Level(Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.ignoresMouseEvents = true

        self.contentView = containerView
    }

    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }

    func show() {
        DispatchQueue.main.async {
            self.updatePosition()
            self.startTimer()
            self.alphaValue = 1.0
            self.orderFrontRegardless()
            Logger.log("[OverlayPanel] HUD timer ordered front in top-right corner (level=%ld)", self.level.rawValue)
        }
    }

    func hide() {
        DispatchQueue.main.async {
            self.stopTimer()
            self.orderOut(nil)
        }
    }

    private func updatePosition() {
        // Track the screen containing the cursor
        let mouseLoc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let targetScreen = screen else { return }
        let visibleFrame = targetScreen.visibleFrame
        let panelWidth: CGFloat = 136.0
        let panelHeight: CGFloat = 38.0
        let margin: CGFloat = 20.0

        // Top-Right corner below menu bar
        let originX = visibleFrame.maxX - panelWidth - margin
        let originY = visibleFrame.maxY - panelHeight - margin

        self.setFrame(NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight), display: true)
    }

    private func startTimer() {
        startTime = Date()
        timerLabel.stringValue = "00:00"
        pulseOn = true
        dotView.layer?.opacity = 1.0

        stopTimer()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
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

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.timerLabel.stringValue = String(format: "%02d:%02d", mm, ss)
            self.pulseOn.toggle()
            self.dotView.layer?.opacity = self.pulseOn ? 1.0 : 0.35
        }
    }
}
