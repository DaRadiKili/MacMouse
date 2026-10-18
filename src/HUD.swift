import Cocoa

/// Kleine Einblendung am unteren Bildschirmrand (z. B. "1600 DPI" oder eine Akku-Warnung), die von selbst verschwindet.
final class HUD {
    static let shared = HUD()

    private var panel: NSPanel?
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?
    private var generation = 0

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 84),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let blur = NSVisualEffectView(frame: p.contentRect(forFrameRect: p.frame))
        blur.material = .hudWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        // Runde Ecken über eine Maske (statt layer.cornerRadius), sonst zeichnet das Fenster eckige Ränder/Schatten
        let radius: CGFloat = 18
        let mask = NSImage(size: NSSize(width: radius * 2 + 1, height: radius * 2 + 1), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        blur.maskImage = mask

        title.font = .systemFont(ofSize: 28, weight: .semibold)
        title.alignment = .center
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        blur.addSubview(title)
        blur.addSubview(subtitle)
        p.contentView = blur
        return p
    }

    /// `force`: auch zeigen, wenn die DPI-Einblendung ausgeschaltet ist (für Warnungen).
    func show(_ text: String, _ detail: String? = nil, tint: NSColor? = nil, duration: TimeInterval = 1.3, force: Bool = false) {
        guard force || settings.showHUD else { return }
        DispatchQueue.main.async {
            let p = self.panel ?? self.makePanel()
            self.panel = p
            self.title.stringValue = text
            self.title.textColor = tint ?? .labelColor
            self.subtitle.stringValue = detail ?? ""

            // Breite nach Text, Höhe je nachdem, ob es eine zweite Zeile gibt
            let textWidth = max(self.title.attributedStringValue.size().width, self.subtitle.attributedStringValue.size().width)
            let width = max(220, min(520, textWidth + 56))
            let height: CGFloat = (detail ?? "").isEmpty ? 64 : 84
            p.setContentSize(NSSize(width: width, height: height))
            self.title.frame = NSRect(x: 8, y: height - 50, width: width - 16, height: 36)
            self.subtitle.frame = NSRect(x: 8, y: 12, width: width - 16, height: 16)

            // Auf dem Bildschirm mit dem Zeiger, unten mittig
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            if let f = screen?.visibleFrame {
                p.setFrameOrigin(NSPoint(x: f.midX - p.frame.width / 2, y: f.minY + 90))
            }

            // Eine noch laufende Ausblend-Animation abbrechen, sonst blendet sie das neue Fenster gleich wieder aus
            self.generation += 1
            let gen = self.generation
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0
                p.animator().alphaValue = 1
            }
            p.alphaValue = 1
            p.orderFrontRegardless()

            self.hideWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.35
                    self?.panel?.animator().alphaValue = 0
                }, completionHandler: {
                    // Nur schließen, wenn inzwischen keine neue Einblendung gestartet wurde
                    if let self = self, self.generation == gen { self.panel?.orderOut(nil) }
                })
            }
            self.hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        }
    }
}
