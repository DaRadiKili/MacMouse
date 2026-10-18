import Cocoa
import SwiftUI

// MARK: - Tastenkombinationen als Text

/// Name einer Taste, wie ihn `pressKeys` versteht ("left", "z", …). Tasten ohne Namen werden zu "#Code".
func keyName(for code: UInt16) -> String {
    let c = CGKeyCode(code)
    if let n = namedKeys.filter({ $0.value == c }).keys.sorted(by: { ($0.count, $0) < ($1.count, $1) }).first { return n }
    if let n = layoutKeys.first(where: { $0.value == c })?.key { return n }
    return "#\(code)"
}

/// "cmd+shift+4" → "⇧⌘4". Alle vier Modifier zusammen (Ctrl+Alt+Shift+Cmd) heißen "Hyper".
func prettyCombo(_ combo: String) -> String {
    let symbols = ["ctrl": "⌃", "alt": "⌥", "shift": "⇧", "cmd": "⌘"]
    let arrows = ["left": "←", "right": "→", "up": "↑", "down": "↓"]
    let order = ["ctrl", "alt", "shift", "cmd"]
    let parts = combo.lowercased().split(separator: "+").map(String.init)
    let hyper = parts.contains("hyper") || order.allSatisfy(parts.contains)
    let mods = hyper ? "Hyper + " : order.filter { parts.contains($0) }.compactMap { symbols[$0] }.joined()
    let key = parts.first { !order.contains($0) && $0 != "hyper" } ?? ""
    let shown = arrows[key] ?? (key.count == 1 ? key.uppercased() : key.hasPrefix("#") ? "Taste \(key.dropFirst())" : key.capitalized)
    return mods + shown
}

// MARK: - Aufnahmefeld

/// Feld, das die nächste gedrückte Tastenkombination aufnimmt.
final class KeyRecorderView: NSView {
    var combo: String? { didSet { needsDisplay = true } }
    var onChange: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 190, height: 28) }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        let active = window?.firstResponder === self
        (active ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = active ? 2 : 1
        path.stroke()

        let text = active && combo == nil ? "Taste drücken …" : (combo.map(prettyCombo) ?? "Klicken, dann Taste drücken")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: combo == nil ? 12 : 14, weight: combo == nil ? .regular : .medium),
            .foregroundColor: combo == nil ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }

    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

    override func keyDown(with event: NSEvent) { capture(event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        capture(event)
        return true   // auch ⌘-Kombinationen aufnehmen, statt sie auszuführen
    }

    private func capture(_ e: NSEvent) {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var parts: [String] = []
        if mods.isSuperset(of: [.control, .option, .shift, .command]) {
            parts.append("hyper")   // z. B. Caps Lock als Hyperkey: alle vier Modifier gleichzeitig
        } else {
            if mods.contains(.control) { parts.append("ctrl") }
            if mods.contains(.option) { parts.append("alt") }
            if mods.contains(.shift) { parts.append("shift") }
            if mods.contains(.command) { parts.append("cmd") }
        }
        parts.append(keyName(for: e.keyCode))
        let c = parts.joined(separator: "+")
        combo = c
        onChange?(c)
        window?.makeFirstResponder(nil)   // Aufnahme ist fertig, das Feld zeigt nur noch die Kombination
    }
}

/// Aufnahmefeld für SwiftUI.
struct KeyRecorderField: NSViewRepresentable {
    @Binding var combo: String

    func makeNSView(context: Context) -> KeyRecorderView {
        let v = KeyRecorderView(frame: .zero)
        v.onChange = { combo = $0 }
        v.combo = combo.isEmpty ? nil : combo
        return v
    }

    func updateNSView(_ v: KeyRecorderView, context: Context) {
        v.onChange = { combo = $0 }
        let shown = combo.isEmpty ? nil : combo
        if v.combo != shown { v.combo = shown }
    }
}
