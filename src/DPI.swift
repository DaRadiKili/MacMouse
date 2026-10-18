import Cocoa

// MARK: - DPI mit Auflösungs-Ausgleich und Bildschirm-Profilen

var lastAppliedDPI: Int?
var lastAppliedHardwareDPI: Int?

/// Mit Auflösungs-Ausgleich: die Maus-DPI wächst mit der Punktdichte des Bildschirms (Punkte pro Millimeter).
/// So bewegt sich der Zeiger bei gleicher Handbewegung immer gleich weit über den Bildschirm, egal welche
/// Auflösung in macOS eingestellt ist oder auf welchem Monitor der Zeiger gerade ist.
func compensationFactor() -> Double {
    guard settings.dpiCompensation, settings.dpiReferenceDensity > 0 else { return 1 }
    let d = Displays.density(Displays.activeID)
    return d > 0 ? d / settings.dpiReferenceDensity : 1
}

/// Alte Configs speicherten eine Referenzbreite. Hier wird sie einmalig in eine Referenzdichte umgerechnet.
func migrateCompensationReference() {
    guard settings.dpiCompensation, settings.dpiReferenceDensity <= 0 else { return }
    let main = CGMainDisplayID()
    let w = Displays.widthPoints(main)
    let density = settings.dpiReferenceWidth > 0 && w > 0
        ? Displays.density(main) * settings.dpiReferenceWidth / w
        : Displays.density(Displays.activeID)
    settings.write(["dpiReferenceDensity": density])
}

/// Der Wert, der wirklich an die Maus geht, zum eingestellten Wert ("base").
func hardwareDPI(forBase base: Int) -> Int { max(100, min(35_000, Int((Double(base) * compensationFactor()).rounded()))) }

/// Umgekehrt: aus dem Geräte-Wert den eingestellten Wert zurückrechnen.
func baseDPI(fromHardware hw: Int) -> Int {
    let f = compensationFactor()
    return f == 1 ? hw : Int((Double(hw) / f / 10).rounded()) * 10
}

/// Eingestellte DPI für den Bildschirm, auf dem der Zeiger gerade ist (eigener Wert oder der allgemeine).
func desiredBaseDPI() -> Int? { settings.displayDPI[Displays.activeUUID] ?? settings.dpi }

/// Setzt die DPI an der Maus; optional wird der Wert als Standard in der Config gespeichert.
/// `feedback` spielt einen Ton und blendet die DPI kurz ein (für Wechsel per Taste oder Bildschirmwechsel).
@discardableResult
func applyDPI(_ base: Int, persist: Bool, feedback: Bool = false) -> Bool {
    let hw = hardwareDPI(forBase: base)
    guard Razer.setDPI(hw) else { log("DPI setzen fehlgeschlagen: \(Razer.lastError)"); return false }
    lastAppliedDPI = base
    lastAppliedHardwareDPI = hw
    log(hw == base ? "DPI → \(base)" : "DPI → \(base) (an der Maus \(hw), Faktor \(String(format: "%.2f", compensationFactor())))")
    DispatchQueue.main.async {
        if persist {
            // Hat der aktuelle Bildschirm eine eigene DPI, wird diese geändert, sonst die allgemeine
            let key = Displays.activeUUID
            if settings.displayDPI[key] != nil {
                var d = settings.displayDPI; d[key] = base
                settings.write(["displayDPI": d])
            } else {
                settings.write(["dpi": base])
            }
        }
        if feedback {
            NSSound(named: "Pop")?.play()
            HUD.shared.show("\(base) DPI", hw == base ? nil : "an der Maus: \(hw)")
        }
    }
    return true
}

/// Wiederholt einen Geräte-Befehl alle 20 Sekunden (höchstens 15-mal), solange die Maus "beschäftigt" meldet,
/// z. B. weil sie im Ruhemodus schläft. Andere Fehler werden nicht wiederholt.
func retryWhileBusy(attempt: Int = 0, _ work: @escaping () -> Bool) {
    DispatchQueue.global(qos: .utility).async {
        if work() { return }
        guard attempt < 15, Razer.lastError.contains("0x1 ") || Razer.lastError.hasSuffix("0x1") || Razer.lastError.contains("Status 0x1") else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20) { retryWhileBusy(attempt: attempt + 1, work) }
    }
}

/// Wendet die konfigurierte DPI an, wenn sich der Zielwert geändert hat (oder `force`).
func applyConfiguredDPI(force: Bool = false, feedback: Bool = false) {
    guard let want = desiredBaseDPI(),
          force || want != lastAppliedDPI || hardwareDPI(forBase: want) != lastAppliedHardwareDPI else { return }
    retryWhileBusy {
        guard let target = desiredBaseDPI() else { return true }   // inzwischen geändert? dann den aktuellen Wert nehmen
        return applyDPI(target, persist: false, feedback: feedback)
    }
}

/// "next", "prev" oder eine Zahl.
func changeDPI(_ arg: String) {
    let a = arg.trimmingCharacters(in: .whitespaces).lowercased()
    if let n = Int(a) { applyDPI(n, persist: true, feedback: true); return }
    guard a == "next" || a == "prev" else { log("Unbekannte DPI-Angabe: \(arg)"); return }
    guard let cur = Razer.getDPI() else { log("DPI lesen fehlgeschlagen: \(Razer.lastError)"); return }
    let base = baseDPI(fromHardware: cur.x)
    let p = settings.presets
    guard !p.isEmpty else { return }
    let target = a == "next" ? (p.first { $0 > base } ?? p[0]) : (p.last { $0 < base } ?? p[p.count - 1])
    applyDPI(target, persist: true, feedback: true)
}

// MARK: - Weitere Geräteeinstellungen (Abfragerate, Abschaltzeit)

var lastAppliedPolling: Int?
var lastAppliedIdle: Int?
var lastAppliedLiftOff: LiftOff?

func applyDeviceSettings(force: Bool = false) {
    retryWhileBusy {
        var ok = true
        if let r = settings.pollingRate, force || r != lastAppliedPolling {
            if Razer.setPollingRate(r) { lastAppliedPolling = r; log("Abfragerate → \(r) Hz") }
            else { log("Abfragerate setzen fehlgeschlagen: \(Razer.lastError)"); ok = false }
        }
        if ok, let l = settings.liftOff, force || l != lastAppliedLiftOff {
            if Razer.setLiftOff(l) { lastAppliedLiftOff = l; log("Abhebe-Distanz → \(l)") }
            else { log("Abhebe-Distanz setzen fehlgeschlagen: \(Razer.lastError)"); ok = false }
        }
        if ok, let i = settings.idleTimeout, force || i != lastAppliedIdle {
            if Razer.setIdleTime(i) { lastAppliedIdle = i; log("Abschaltzeit → \(i) s") }
            else { log("Abschaltzeit setzen fehlgeschlagen: \(Razer.lastError)"); ok = false }
        }
        return ok
    }
}

// MARK: - Regler-Umrechnung (logarithmisch: feine Schritte im unteren Bereich)

let dpiMin = 100.0
let dpiMax = 35_000.0

func dpiFromPosition(_ t: Double) -> Int {
    let raw = dpiMin * pow(dpiMax / dpiMin, t)
    let step = raw < 1000 ? 50.0 : 100.0
    return Int((raw / step).rounded() * step)
}

func positionFromDPI(_ dpi: Int) -> Double {
    min(1, max(0, log(Double(max(dpi, 100)) / dpiMin) / log(dpiMax / dpiMin)))
}
