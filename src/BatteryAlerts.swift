import Cocoa

/// Warnt bei niedrigem Akku (Einblendung mit Restlaufzeit) und färbt das Menüleisten-Symbol ein.
enum BatteryAlerts {
    private static let defaults = UserDefaults.standard   // in der App: Einstellungen der App selbst

    /// Schwellen, für die in dieser Entlade-Phase schon gewarnt wurde (damit jede Warnung nur einmal kommt).
    private static var alerted: Set<Int> {
        get { Set(defaults.array(forKey: "alertedLevels") as? [Int] ?? []) }
        set { defaults.set(Array(newValue), forKey: "alertedLevels") }
    }
    private static var fullAlerted: Bool {
        get { defaults.bool(forKey: "fullAlerted") }
        set { defaults.set(newValue, forKey: "fullAlerted") }
    }

    /// Farbe des Symbols für diesen Akkustand (nil = normal).
    static func iconColor(percent: Double, charging: Bool) -> NSColor? {
        guard settings.batteryIconColors, !charging else { return nil }
        if percent <= Double(settings.batteryCritical) { return .systemRed }
        if percent <= Double(settings.batteryLow) { return .systemOrange }
        return nil
    }

    enum Action: Equatable {
        case low(level: Int)   // Schwelle, die gerade unterschritten wurde
        case full
    }

    /// Entscheidet, ob jetzt eine Meldung fällig ist, und aktualisiert dafür den Merkzustand. (Ohne Oberfläche, testbar.)
    static func decide(percent pct: Double, charging: Bool, alerted: inout Set<Int>, fullAlerted: inout Bool,
                       low: Int, critical: Int, fullEnabled: Bool) -> Action? {
        if charging {
            alerted = []
            guard fullEnabled else { return nil }
            if pct >= 99 && !fullAlerted { fullAlerted = true; return .full }
            if pct < 95 { fullAlerted = false }
            return nil
        }
        fullAlerted = false
        // Wieder deutlich über der Schwelle (z. B. nach dem Laden) → Warnung wieder scharf schalten
        alerted = alerted.filter { pct <= Double($0) + 3 }
        let levels = [critical, low].sorted()   // kleinste zuerst
        guard let level = levels.first(where: { pct <= Double($0) }), !alerted.contains(level) else { return nil }
        alerted.formUnion(levels.filter { $0 >= level })   // höhere Schwellen gelten damit auch als gemeldet
        return .low(level: level)
    }

    /// Nach jeder Messung aufrufen (Hauptthread).
    static func evaluate(_ info: BatteryInfo, _ estimate: BatteryEstimate) {
        menuController?.setIconColor(iconColor(percent: info.exact, charging: info.charging))
        guard settings.batteryAlerts else { return }
        var a = alerted, f = fullAlerted
        let action = decide(percent: info.exact, charging: info.charging, alerted: &a, fullAlerted: &f,
                            low: settings.batteryLow, critical: settings.batteryCritical, fullEnabled: settings.batteryFullAlert)
        alerted = a; fullAlerted = f
        switch action {
        case .full?:
            HUD.shared.show("Akku voll", "Danach ca. \(formatDuration(estimate.fullRuntime)) (\(estimate.hz) Hz)",
                            tint: .systemGreen, duration: 5, force: true)
        case .low(let level)?:
            show(percent: info.exact, estimate: estimate, level: level)
        case nil:
            break
        }
    }

    private static func show(percent: Double, estimate: BatteryEstimate, level: Int) {
        let critical = level <= settings.batteryCritical
        let title = (critical ? "Akku fast leer: " : "Akku niedrig: ") + "\(Int(percent.rounded())) %"
        let detail = estimate.remaining.map { "Hält noch ca. \(formatDuration($0)) (\(estimate.hz) Hz)" } ?? "Bitte bald laden"
        HUD.shared.show(title, detail, tint: critical ? .systemRed : .systemOrange, duration: 6, force: true)
    }

    /// Vorschau aus dem Einstellungsfenster.
    static func preview(critical: Bool) {
        let level = critical ? settings.batteryCritical : settings.batteryLow
        let sample = BatteryInfo(percent: level, charging: false, exact: Double(level))
        let est = BatteryTracker.shared.estimate(for: sample, hz: Razer.knownPollingRate ?? settings.pollingRate ?? 1000)
        show(percent: Double(level), estimate: est, level: level)
    }
}
