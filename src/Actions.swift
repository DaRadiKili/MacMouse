import Cocoa
import Carbon.HIToolbox

// MARK: - Tastenkürzel senden

let namedKeys: [String: CGKeyCode] = [
    "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51, "esc": 53, "escape": 53,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "home": 115, "end": 119, "pageup": 116, "pagedown": 121, "forwarddelete": 117,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
    "f9": 101, "f10": 109, "f11": 103, "f12": 111,
]

/// Zeichen → Tastencode laut aktuellem Tastaturlayout (damit "z" auch auf QWERTZ stimmt).
let layoutKeys: [String: CGKeyCode] = {
    var map: [String: CGKeyCode] = [:]
    guard let src = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
          let raw = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return map }
    let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
    let layout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
    for code in 0..<128 {
        var dead: UInt32 = 0
        var len = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let r = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                               OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
        if r == noErr, len > 0 {
            let s = String(utf16CodeUnits: chars, count: len)
            if map[s] == nil { map[s] = CGKeyCode(code) }
        }
    }
    return map
}()

let aliases: [String: String] = [
    "mission": "ctrl+up", "appexpose": "ctrl+down",
    "desktopleft": "ctrl+left", "desktopright": "ctrl+right",
]

func pressKeys(_ combo: String) {
    var flags: CGEventFlags = []
    var keyName = ""
    for part in combo.lowercased().split(separator: "+").map({ String($0).trimmingCharacters(in: .whitespaces) }) {
        switch part {
        case "cmd", "command": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "alt", "opt", "option": flags.insert(.maskAlternate)
        case "ctrl", "control": flags.insert(.maskControl)
        case "hyper": flags.formUnion([.maskControl, .maskAlternate, .maskShift, .maskCommand])
        default: keyName = part
        }
    }
    // "#NN" = roher Tastencode (für Tasten ohne Namen, vom Aufnahme-Fenster erzeugt)
    let raw = keyName.hasPrefix("#") ? UInt16(keyName.dropFirst()).map { CGKeyCode($0) } : nil
    guard let code = raw ?? namedKeys[keyName] ?? layoutKeys[keyName] else {
        log("Unbekannte Taste: \"\(keyName)\" in \"\(combo)\""); return
    }
    // Pfeil-/Navigationstasten tragen auf echten Tastaturen das fn-Flag; Systemkürzel wie Ctrl+← erwarten es
    if [123, 124, 125, 126, 115, 119, 116, 121, 117].contains(Int(code)) { flags.insert(.maskSecondaryFn) }
    for down in [true, false] {
        guard let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { continue }
        e.flags = flags
        e.post(tap: .cghidEventTap)
    }
}

// MARK: - Aktionen

func perform(_ spec: String) {
    let s = spec.trimmingCharacters(in: .whitespaces)
    let lower = s.lowercased()
    if s.isEmpty || lower == "none" || lower == "passthrough" { return }
    if let combo = aliases[lower] { pressKeys(combo); return }
    guard let colon = s.firstIndex(of: ":") else { log("Unbekannte Aktion: \(spec)"); return }
    let kind = s[..<colon].lowercased()
    let arg = String(s[s.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    switch kind {
    case "key": pressKeys(arg)
    case "dpi": DispatchQueue.global(qos: .userInitiated).async { changeDPI(arg) }
    case "profile": DispatchQueue.main.async { Profiles.perform(arg) }
    case "app": run("/usr/bin/open", ["-a", arg])
    case "shell": run("/bin/sh", ["-c", arg])
    default: log("Unbekannte Aktion: \(spec)")
    }
}

func run(_ path: String, _ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    try? p.run()
}
