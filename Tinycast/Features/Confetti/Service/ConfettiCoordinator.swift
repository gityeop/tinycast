import AppKit
import QuartzCore

@MainActor
final class ConfettiCoordinator {
    private struct Overlay {
        let panel: NSPanel
        let emitter: CAEmitterLayer
    }

    private var overlays: [Overlay] = []
    private var lifetime: Task<Void, Never>?

    isolated deinit {
        lifetime?.cancel()
        for overlay in overlays { overlay.panel.close() }
    }

    func show() {
        stop()
        let particles = Self.particleCells()
        overlays = NSScreen.screens.map { screen in
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.animationBehavior = .none

            let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            let emitter = CAEmitterLayer()
            emitter.frame = content.bounds
            emitter.contentsScale = screen.backingScaleFactor
            emitter.emitterShape = .line
            emitter.emitterSize = CGSize(width: screen.frame.width, height: 1)
            emitter.emitterPosition = CGPoint(x: screen.frame.width / 2, y: screen.frame.height + 16)
            emitter.beginTime = CACurrentMediaTime()
            emitter.emitterCells = particles
            content.wantsLayer = true
            content.layer = emitter
            panel.contentView = content
            panel.orderFrontRegardless()
            return Overlay(panel: panel, emitter: emitter)
        }

        lifetime = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(700))
                self?.endEmission()
                try await Task.sleep(for: .seconds(5))
                self?.stop()
            } catch { return }
        }
    }

    func stop() {
        lifetime?.cancel()
        lifetime = nil
        for overlay in overlays {
            overlay.emitter.emitterCells = nil
            overlay.panel.close()
        }
        overlays.removeAll()
    }

    private func endEmission() {
        for overlay in overlays { overlay.emitter.birthRate = 0 }
    }

    private static func particleCells() -> [CAEmitterCell] {
        let image = NSImage(size: NSSize(width: 9, height: 14), flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(rect: rect).fill()
            return true
        }
        let contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple]
        return colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = contents
            cell.color = color.cgColor
            cell.birthRate = 35
            cell.lifetime = 5
            cell.velocity = 220
            cell.velocityRange = 80
            cell.emissionLongitude = -.pi / 2
            cell.emissionRange = .pi / 3
            cell.yAcceleration = -180
            cell.spin = 3
            cell.spinRange = 5
            cell.scaleRange = 0.3
            return cell
        }
    }
}
