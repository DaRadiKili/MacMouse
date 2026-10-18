import Foundation

func log(_ s: String) {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    print("[\(f.string(from: Date()))] \(s)")
}

/// Name der App (Anzeige, Fenstertitel, Dateien).
let appName = "MacMouse"

let configDir = NSString(string: "~/.config/macmouse").expandingTildeInPath
let configPath = configDir + "/config.json"

/// Obere Seitentaste (Viper V3 Pro). Ohne Belegung passiert beim Drücken nichts.
let upperButton = 3

final class Settings {
    var dpi: Int?
    var presets = [800, 1600, 3200]
    var buttons: [Int: String] = [:]
    var gestures: [String: String] = [:]
    var gestureButtons: [Int: [String: String]] = [:]
    var buttonExtras: [Int: [String: String]] = [:]   // zusätzlich zum normalen Klick: "double" und "hold"
    var gestureThreshold = 80.0
    var gestureLock = 12.0
    var gestureMode = "smooth"      // "smooth" = folgt der Maus wie ein Trackpad, "jump" = Ctrl+Pfeil
    var gestureInvert = false
    var gestureVertical = "jump"    // hoch/runter: "jump" = einmal auslösen, "smooth" = folgt der Maus
    var dpiCompensation = false     // DPI mit der macOS-Auflösung mitskalieren, damit sich der Zeiger gleich anfühlt
    var dpiReferenceWidth = 0.0     // (alt) Bildschirmbreite in Punkten; wird nur noch zum Umrechnen gelesen
    var dpiReferenceDensity = 0.0   // Punkte pro mm, bei denen "dpi" genau so gilt
    var displayDPI: [String: Int] = [:]   // eigene DPI je Bildschirm (Schlüssel: Display-UUID)
    var showHUD = true              // kurze Einblendung, wenn die DPI per Taste wechselt
    var pollingRate: Int?           // Hz, wird beim Verbinden gesetzt
    var idleTimeout: Int?           // Sekunden bis zum Ruhemodus der Maus
    var liftOff: LiftOff?           // Abhebe-Distanz, wird beim Verbinden gesetzt
    var scrollInvertMouse = false   // Mausrad-Richtung umkehren (Trackpad bleibt, wie es ist)
    var smoothScroll = false        // Mausrad scrollt weich
    var scrollSpeed = 1.0           // Tempo des glatten Scrollens
    var scrollSmoothness = 0.5      // 0 = knackig … 1 = sehr weich
    var pointerAcceleration = "fixed"    // "fixed" = feste Zeigergeschwindigkeit (Systemregler wird ignoriert), "system" = wie im System
    var pointerSpeed: Double?            // der feste Wert (0 … 3, wie "Zeigergeschwindigkeit" im System)
    var batteryAlerts = true        // Einblendung bei niedrigem Akku
    var batteryLow = 20             // erste Warnung (Symbol orange), in Prozent
    var batteryCritical = 10        // zweite Warnung (Symbol rot), in Prozent
    var batteryFullAlert = true     // Meldung, wenn der Akku voll ist
    var batteryIconColors = true    // Menüleisten-Symbol bei niedrigem Akku einfärben
    var activeProfile: String?           // gerade geltendes Profil (nil = Profile nicht eingeschaltet)
    var defaultProfile: String?          // gilt, wenn für die vordere App kein eigenes Profil festgelegt ist
    var profileOrder: [String] = []      // Reihenfolge der Profile
    var appProfiles: [String: String] = [:]   // Bundle-ID einer App → Profilname
    var debug = false
    private var stamp: Date?
    private var observers: [() -> Void] = []
    /// Wird nach jedem (Neu-)Laden der Config aufgerufen (Dienst, Menü, Einstellungsfenster).
    func observe(_ f: @escaping () -> Void) { observers.append(f) }

    static let defaultText = """
    {
      "dpi": null,
      "dpiPresets": [800, 1600, 3200],
      "dpiCompensation": false,
      "gestureMode": "smooth",
      "gestureVertical": "jump",
      "gestureInvert": false,
      "gestureThreshold": 80,
      "gestureButtons": {
        "4": {
          "up": "mission",
          "down": "appexpose",
          "left": "desktopright",
          "right": "desktopleft",
          "click": "passthrough"
        }
      },
      "buttons": {
        "3": "none"
      },
      "gestures": {
        "swipeLeft": "none",
        "swipeRight": "none",
        "swipeUp": "none",
        "swipeDown": "none",
        "pinchIn": "none",
        "pinchOut": "none",
        "rotateLeft": "none",
        "rotateRight": "none"
      }
    }

    """

    func ensureFile() {
        guard !FileManager.default.fileExists(atPath: configPath) else { return }
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        try? Settings.defaultText.write(toFile: configPath, atomically: true, encoding: .utf8)
        log("Config angelegt: \(configPath)")
    }

    /// Lädt die Datei neu, wenn sie sich geändert hat. Gibt true zurück, wenn neu geladen wurde.
    @discardableResult
    func reloadIfChanged() -> Bool {
        ensureFile()
        let attrs = try? FileManager.default.attributesOfItem(atPath: configPath)
        let modified = attrs?[.modificationDate] as? Date
        if modified == stamp { return false }
        stamp = modified
        guard let data = FileManager.default.contents(atPath: configPath),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            log("config.json ist kein gültiges JSON – alte Werte bleiben aktiv")
            return false
        }
        dpi = obj["dpi"] as? Int
        presets = ((obj["dpiPresets"] as? [Int]) ?? [800, 1600, 3200]).sorted()
        buttons = [:]
        for (k, v) in (obj["buttons"] as? [String: String]) ?? [:] {
            guard let n = Int(k), n >= 2 else {
                log("Taste \"\(k)\" ignoriert (nur Tasten ab 2 sind umbelegbar: 2=Mitte, 3=Zurück, 4=Vor, …)")
                continue
            }
            buttons[n] = v
        }
        gestures = (obj["gestures"] as? [String: String]) ?? [:]
        gestureButtons = [:]
        for (k, v) in (obj["gestureButtons"] as? [String: [String: String]]) ?? [:] {
            if let n = Int(k), n >= 2 { gestureButtons[n] = v }
        }
        buttonExtras = [:]
        for (k, v) in (obj["buttonsExtra"] as? [String: [String: String]]) ?? [:] {
            if let n = Int(k), n >= 2 { buttonExtras[n] = v }
        }
        gestureThreshold = (obj["gestureThreshold"] as? Double) ?? 80
        gestureLock = (obj["gestureLock"] as? Double) ?? 12
        gestureMode = (obj["gestureMode"] as? String) ?? "smooth"
        gestureInvert = (obj["gestureInvert"] as? Bool) ?? false
        gestureVertical = (obj["gestureVertical"] as? String) ?? "jump"
        dpiCompensation = (obj["dpiCompensation"] as? Bool) ?? false
        dpiReferenceWidth = (obj["dpiReferenceWidth"] as? Double) ?? 0
        dpiReferenceDensity = (obj["dpiReferenceDensity"] as? Double) ?? 0
        if buttons[upperButton] == nil { buttons[upperButton] = "none" }   // unbelegt → nichts passiert
        displayDPI = (obj["displayDPI"] as? [String: Int]) ?? [:]
        showHUD = (obj["showHUD"] as? Bool) ?? true
        pollingRate = obj["pollingRate"] as? Int
        idleTimeout = obj["idleTimeout"] as? Int
        if let lo = obj["liftOff"] as? [String: Any], let mode = lo["mode"] as? String {
            let parsed: LiftOff? = mode == "preset" ? (lo["level"] as? Int).map { .preset($0) }
                : (mode == "asymmetric" ? ((lo["lift"] as? Int).flatMap { l in (lo["land"] as? Int).map { .asymmetric(lift: l, land: $0) } }) : nil)
            liftOff = parsed?.isValid == true ? parsed : nil
        } else { liftOff = nil }
        scrollInvertMouse = (obj["scrollInvertMouse"] as? Bool) ?? false
        smoothScroll = (obj["smoothScroll"] as? Bool) ?? false
        scrollSpeed = (obj["scrollSpeed"] as? Double) ?? 1.0
        scrollSmoothness = (obj["scrollSmoothness"] as? Double) ?? 0.5
        pointerAcceleration = (obj["pointerAcceleration"] as? String) == "system" ? "system" : "fixed"   // alte Werte ("off") → "fixed"
        pointerSpeed = obj["pointerSpeed"] as? Double
        batteryAlerts = (obj["batteryAlerts"] as? Bool) ?? true
        batteryLow = (obj["batteryLow"] as? Int) ?? 20
        batteryCritical = min((obj["batteryCritical"] as? Int) ?? 10, batteryLow - 1)
        batteryFullAlert = (obj["batteryFullAlert"] as? Bool) ?? true
        batteryIconColors = (obj["batteryIconColors"] as? Bool) ?? true
        activeProfile = obj["activeProfile"] as? String
        defaultProfile = obj["defaultProfile"] as? String
        profileOrder = (obj["profileOrder"] as? [String]) ?? []
        appProfiles = (obj["appProfiles"] as? [String: String]) ?? [:]
        debug = (obj["debug"] as? Bool) ?? false
        log("Config geladen")
        observers.forEach { $0() }
        return true
    }

    /// Der rohe Inhalt von config.json (für Profile, die beliebige Schlüssel kopieren).
    func rawObject() -> [String: Any] {
        (FileManager.default.contents(atPath: configPath).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
    }

    /// Ändert einzelne Werte in config.json (z. B. aus dem Menü) und lädt sie sofort neu.
    func write(_ changes: [String: Any]) {
        ensureFile()
        var obj = (FileManager.default.contents(atPath: configPath)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        for (k, v) in changes { if v is NSNull { obj.removeValue(forKey: k) } else { obj[k] = v } }
        guard let data = try? JSONSerialization.data(withJSONObject: obj,
                                                     options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return }
        try? data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
        reloadIfChanged()
    }
}

let settings = Settings()

/// Frühere Versionen hießen "maus" und lagen in ~/.config/maus. Beim ersten Start wird der Ordner umbenannt.
func migrateLegacyConfig() {
    let fm = FileManager.default
    let old = NSString(string: "~/.config/maus").expandingTildeInPath
    guard fm.fileExists(atPath: old), !fm.fileExists(atPath: configDir) else { return }
    do {
        try fm.moveItem(atPath: old, toPath: configDir)
        log("Einstellungen von ~/.config/maus nach ~/.config/macmouse verschoben")
    } catch {
        log("Umzug der alten Einstellungen fehlgeschlagen: \(error.localizedDescription)")
    }
}
