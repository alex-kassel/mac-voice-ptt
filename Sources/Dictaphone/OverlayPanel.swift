import Foundation
import AppKit

final class OverlayPanel: NSPanel {
    private let containerView: NSView
    private let dotView: NSView
    private let timerLabel: NSTextField
    private var timerSource: DispatchSourceTimer?
    private var startTime: Date?
    private var pulseOn = true
    private var isProcessing = false

    init() {
        let panelWidth: CGFloat = 144.0
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

        // 2. Indicator dot / icon (red for recording, cyan for processing, green for done)
        let dotSize: CGFloat = 10.0
        let dotY = (panelHeight - dotSize) / 2.0
        dotView = NSView(frame: NSRect(x: 16.0, y: dotY, width: dotSize, height: dotSize))
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = dotSize / 2.0
        dotView.layer?.backgroundColor = NSColor.systemRed.cgColor
        dotView.layer?.shadowColor = NSColor.systemRed.cgColor
        dotView.layer?.shadowRadius = 4.0
        dotView.layer?.shadowOpacity = 0.9
        dotView.layer?.shadowOffset = .zero
        containerView.addSubview(dotView)

        // 3. Crisp white label
        let labelX: CGFloat = 34.0
        let labelWidth: CGFloat = panelWidth - labelX - 10.0
        let labelY = (panelHeight - 22.0) / 2.0
        timerLabel = NSTextField(labelWithString: "00:00")
        timerLabel.frame = NSRect(x: labelX, y: labelY, width: labelWidth, height: 22.0)
        timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 15.0, weight: .bold)
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
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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

    // MARK: - State Management

    func showRecording() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isProcessing = false
            self.updatePosition()
            self.setIndicatorState(color: .systemRed, text: "00:00")
            self.startTimer()
            self.alphaValue = 1.0
            self.orderFrontRegardless()
            Logger.log("[OverlayPanel] HUD recording started in top-right corner (level=%ld)", self.level.rawValue)
        }
    }

    func showProcessing() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isProcessing = true
            self.stopTimer()

            // Keep HUD visible and transition to processing mode
            self.setIndicatorState(color: .systemTeal, text: "Processing…")
            self.startProcessingPulse()
            self.alphaValue = 1.0
            self.orderFrontRegardless()
            Logger.log("[OverlayPanel] HUD transitioned to processing mode.")
        }
    }

    func showSuccess(completion: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completion()
                return
            }
            self.stopTimer()
            self.setIndicatorState(color: .systemGreen, text: "Done ✓")

            // Keep "Done ✓" visible for 350ms, then fade out and execute paste
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    self.animator().alphaValue = 0.0
                }, completionHandler: {
                    self.orderOut(nil)
                    self.alphaValue = 1.0
                    completion()
                })
            }
        }
    }

    func hideImmediate() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stopTimer()
            self.isProcessing = false
            self.orderOut(nil)
            self.alphaValue = 1.0
        }
    }

    // Backward compatibility helper
    func show() {
        showRecording()
    }

    func hide() {
        hideImmediate()
    }

    // MARK: - Positioning

    private func updatePosition() {
        // Priority:
        // 1. Screen containing the focused window where user is typing (NSScreen.main)
        // 2. Screen containing cursor
        // 3. Primary screen
        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.main
            ?? NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) })
            ?? NSScreen.screens.first

        guard let screen = targetScreen else { return }
        let visibleFrame = screen.visibleFrame
        let panelWidth: CGFloat = 144.0
        let panelHeight: CGFloat = 38.0
        let margin: CGFloat = 20.0

        let originX = visibleFrame.maxX - panelWidth - margin
        let originY = visibleFrame.maxY - panelHeight - margin

        self.setFrame(NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight), display: true)
    }

    // MARK: - Timer & Animations

    private func setIndicatorState(color: NSColor, text: String) {
        dotView.layer?.backgroundColor = color.cgColor
        dotView.layer?.shadowColor = color.cgColor
        dotView.layer?.opacity = 1.0
        timerLabel.stringValue = text
    }

    private func startTimer() {
        stopTimer()
        startTime = Date()
        timerLabel.stringValue = "00:00"
        pulseOn = true
        dotView.layer?.opacity = 1.0

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in
            self?.tickRecording()
        }
        timer.resume()
        self.timerSource = timer
    }

    private func startProcessingPulse() {
        stopTimer()
        pulseOn = true
        dotView.layer?.opacity = 1.0

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.35, repeating: 0.35)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.pulseOn.toggle()
            self.dotView.layer?.opacity = self.pulseOn ? 1.0 : 0.4
        }
        timer.resume()
        self.timerSource = timer
    }

    private func stopTimer() {
        timerSource?.cancel()
        timerSource = nil
        startTime = nil
    }

    private func tickRecording() {
        guard let start = startTime else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        let mm = elapsed / 60
        let ss = elapsed % 60

        timerLabel.stringValue = String(format: "%02d:%02d", mm, ss)
        pulseOn.toggle()
        dotView.layer?.opacity = pulseOn ? 1.0 : 0.35
    }
}
