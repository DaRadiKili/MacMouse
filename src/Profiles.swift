import Cocoa

/// Profile: gespeicherte Pakete aus Einstellungen (DPI, Tasten, Gesten, Scrollen …), die man per Menü, Taste
/// oder automatisch je nach vorderster App wechselt. Die "echten" Einstellungen oben in config.json bleiben
/// immer die gerade gültigen; ein Profil ist ein Schnappschuss davon. Änderungen werden ins aktive Profil
/// zurückgeschrieben.
enum Profiles {
    /// Diese Schlüssel gehören zu einem Profil. Nicht dabei: DPI-Stufen, Auflösungs-Ausgleich, Akku-Warnungen, Ruhemodus.
    static let keys = [
        "dpi", "displayDPI", "pollingRate",
        "buttons", "buttonsExtra", "gestureButtons",
        "gestureMode", "gestureVertical", "gestureInvert", "gestureThreshold", "gestureLock", "gestures",
        "scrollInvertMouse", "smoothScroll", "scrollSpeed", "scrollSmoothness", "pointerAcceleration",
    ]

    static var enabled: Bool { !names.isEmpty }
    static var names: [String] { settings.profileOrder.filter { rawProfiles()[$0] != nil } }

    private static func rawProfiles() -> [String: [String: Any]] {
        (settings.rawObject()["profiles"] as? [String: [String: Any]]) ?? [:]
    }

    /// Die aktuell geltenden Profil-Einstellungen.
    static func snapshot() -> [String: Any] {
        settings.rawObject().filter { keys.contains($0.key) }
    }

    private static func uniqueName(_ wanted: String) -> String {
        let base = wanted.trimmingCharacters(in: .whitespaces).isEmpty ? "Profil" : wanted.trimmingCharacters(in: .whitespaces)
        var name = base, n = 2
        while rawProfiles()[name] != nil { name = "\(base) \(n)"; n += 1 }
        return name
    }

    // MARK: Anlegen, wechseln, löschen

    /// Schaltet Profile ein: die aktuellen Einstellungen werden zum Profil "Standard".
    static func enable() {
        guard !enabled else { return }
        settings.write(["profiles": ["Standard": snapshot()], "profileOrder": ["Standard"],
                        "activeProfile": "Standard", "defaultProfile": "Standard"])
    }

    /// Neues Profil aus den aktuellen Einstellungen und gleich dorthin wechseln.
    @discardableResult
    static func create(_ wanted: String) -> String {
        if !enabled { enable() }
        syncActive()                                   // erst das bisherige Profil sichern
        let name = uniqueName(wanted)
        var all = rawProfiles(); all[name] = snapshot()
        settings.write(["profiles": all, "profileOrder": settings.profileOrder + [name], "activeProfile": name])
        return name
    }

    /// Wechselt zum Profil. `announce`: kurze Einblendung (nicht bei automatischem App-Wechsel).
    static func activate(_ name: String, announce: Bool = false) {
        guard let snap = rawProfiles()[name] else { return }
        if settings.activeProfile == name { return }
        syncActive()                                   // Änderungen am bisherigen Profil nicht verlieren
        var changes: [String: Any] = [:]
        for k in keys { changes[k] = snap[k] ?? NSNull() }
        changes["activeProfile"] = name
        settings.write(changes)
        log("Profil → \(name)")
        if announce { HUD.shared.show(name, "Profil", duration: 1.3, force: true) }
    }

    static func delete(_ name: String) {
        guard enabled, name != settings.defaultProfile else { return }
        var all = rawProfiles(); all[name] = nil
        let apps = settings.appProfiles.filter { $0.value != name }
        settings.write(["profiles": all, "profileOrder": settings.profileOrder.filter { $0 != name }, "appProfiles": apps])
        if settings.activeProfile == name, let d = settings.defaultProfile { activate(d) }
    }

    static func rename(_ old: String, to wanted: String) {
        let new = wanted.trimmingCharacters(in: .whitespaces)
        var all = rawProfiles()
        guard let snap = all[old], !new.isEmpty, new != old, all[new] == nil else { return }
        all[old] = nil; all[new] = snap
        let apps = settings.appProfiles.mapValues { $0 == old ? new : $0 }
        var changes: [String: Any] = ["profiles": all, "appProfiles": apps,
                                      "profileOrder": settings.profileOrder.map { $0 == old ? new : $0 }]
        if settings.activeProfile == old { changes["activeProfile"] = new }
        if settings.defaultProfile == old { changes["defaultProfile"] = new }
        settings.write(changes)
    }

    /// "next", "prev" oder ein Profilname.
    static func perform(_ arg: String) {
        let list = names
        guard !list.isEmpty else { return }
        let a = arg.trimmingCharacters(in: .whitespaces)
        if a == "next" || a == "prev" {
            let cur = settings.activeProfile.flatMap { list.firstIndex(of: $0) } ?? 0
            let target = list[(cur + (a == "next" ? 1 : list.count - 1)) % list.count]
            activate(target, announce: true)
        } else if list.contains(a) {
            activate(a, announce: true)
        }
    }

    // MARK: Abgleich und App-Wechsel

    /// Schreibt Änderungen an den laufenden Einstellungen ins aktive Profil zurück.
    static func syncActive() {
        guard let active = settings.activeProfile else { return }
        var all = rawProfiles()
        guard let stored = all[active] else { return }
        let snap = snapshot()
        if !(snap as NSDictionary).isEqual(to: stored) {
            all[active] = snap
            settings.write(["profiles": all])
        }
    }

    /// Vorderste App hat gewechselt → passendes Profil laden.
    static func frontAppChanged(_ bundleID: String?) {
        guard enabled, let id = bundleID, id != Bundle.main.bundleIdentifier else { return }
        guard let target = settings.appProfiles[id] ?? settings.defaultProfile, target != settings.activeProfile else { return }
        activate(target)
    }
}
