import Foundation

// MARK: - Akku-Verlauf und Laufzeit-Schätzung

/// Ein Messpunkt des Akkus.
struct BatterySample: Codable {
    var t: Double      // Unix-Zeit
    var p: Double      // Prozent (0–100)
    var c: Bool        // lädt
    var hz: Int        // Abfragerate zu diesem Zeitpunkt, 0 = unbekannt
}

enum EstimateSource {
    case rated      // nur Herstellerangabe
    case learning   // Herstellerangabe, schon mit ersten Messungen vermischt
    case measured   // überwiegend eigene Messungen
}

struct BatteryEstimate {
    var percent: Double
    var charging: Bool
    var hz: Int
    var isFull: Bool
    var toFull: TimeInterval?        // nur beim Laden; nil = noch zu wenig Messwerte
    var remaining: TimeInterval?     // nur beim Entladen
    var fullRuntime: TimeInterval    // so lange hält eine volle Ladung bei `hz`
    var source: EstimateSource
    var perRate: [(hz: Int, runtime: TimeInterval, measured: Bool)]
}

/// Sammelt regelmäßig den Akkustand, speichert ihn und schätzt daraus, wie lange das Laden noch dauert und
/// wie lange die Maus danach durchhält. Startwerte sind die Razer-Angaben je Abfragerate, die eigenen
/// Messungen übernehmen nach und nach.
final class BatteryTracker {
    static let shared = BatteryTracker()

    /// Razer-Angaben für die Viper V3 Pro (Stunden pro volle Ladung). 125/500 Hz sind nicht angegeben und
    /// werden wie 1000 Hz behandelt.
    static let ratedHours: [Int: Double] = [1000: 95, 2000: 62, 4000: 40, 8000: 17]

    private let queue = DispatchQueue(label: "macmouse.battery")
    private let path = configDir + "/battery.json"
    private var samples: [BatterySample] = []
    private let interval: TimeInterval = 180        // alle 3 Minuten messen
    private let keepSeconds: TimeInterval = 14 * 24 * 3600

    /// Für Tests: feste Messpunkte, ohne Datei.
    init(samples: [BatterySample]) { self.samples = samples }

    private init() {
        if let data = FileManager.default.contents(atPath: path),
           let s = try? JSONDecoder().decode([BatterySample].self, from: data) { samples = s }
    }

    // MARK: Messen

    private var lastSample = Date.distantPast
    private var lastKnown: (percent: Double, charging: Bool)?

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.sampleNow() }
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.tick() }
    }

    /// Normal alle 3 Minuten, bei fast leerem Akku jede Minute (damit Warnungen rechtzeitig kommen).
    private func tick() {
        let low = lastKnown.map { !$0.charging && $0.percent <= Double(settings.batteryLow + 5) } ?? false
        if Date().timeIntervalSince(lastSample) >= (low ? 55 : interval - 5) { sampleNow() }
    }

    /// Liest den Akku von der Maus und wertet ihn aus.
    func sampleNow() {
        lastSample = Date()
        DispatchQueue.global(qos: .utility).async {
            guard let info = Razer.battery() else { return }
            self.process(info, hz: Razer.getPollingRate() ?? Razer.knownPollingRate ?? 0)
        }
    }

    /// Speichert den Messpunkt, schätzt die Laufzeit und stößt Warnungen und Symbolfarbe an.
    @discardableResult
    func process(_ info: BatteryInfo, hz: Int) -> BatteryEstimate {
        record(info, hz: hz)
        lastKnown = (info.exact, info.charging)
        let e = estimate(for: info, hz: hz)
        DispatchQueue.main.async { BatteryAlerts.evaluate(info, e) }
        return e
    }

    /// Speichert einen Messpunkt (höchstens einen pro Minute).
    func record(_ info: BatteryInfo, hz: Int) {
        queue.sync {
            let now = Date().timeIntervalSince1970
            if let last = samples.last, now - last.t < 60 { return }
            samples.append(BatterySample(t: now, p: info.exact, c: info.charging, hz: hz))
            samples.removeAll { now - $0.t > keepSeconds }
            if samples.count > 6000 { samples.removeFirst(samples.count - 6000) }
            if let data = try? JSONEncoder().encode(samples) { try? data.write(to: URL(fileURLWithPath: path), options: .atomic) }
        }
    }

    // MARK: Schätzen

    /// Entladung je Abfragerate aus allen Messpaaren ohne Laden und ohne Lücken: (verlorene Prozent, Stunden).
    private func dischargeStats(_ s: [BatterySample]) -> [Int: (dp: Double, hours: Double)] {
        var stats: [Int: (dp: Double, hours: Double)] = [:]
        guard s.count > 1 else { return stats }
        for i in 1..<s.count {
            let a = s[i - 1], b = s[i]
            guard !a.c, !b.c, a.hz > 0, a.hz == b.hz else { continue }
            let hours = (b.t - a.t) / 3600
            guard hours > 0, hours <= 20.0 / 60 else { continue }     // keine Lücken (Maus aus/Ruhemodus)
            let dp = a.p - b.p
            guard dp >= 0 else { continue }
            let cur = stats[a.hz] ?? (0, 0)
            stats[a.hz] = (cur.dp + dp, cur.hours + hours)
        }
        return stats
    }

    private static func rated(_ hz: Int) -> Double {
        ratedHours[hz] ?? (hz > 0 && hz < 1000 ? ratedHours[1000]! : (ratedHours[hz > 8000 ? 8000 : 1000]!))
    }

    /// Laufzeit einer vollen Ladung in Stunden; Herstellerwert und Messung werden nach Messdauer gemischt.
    private static func runtimeHours(_ hz: Int, _ stats: [Int: (dp: Double, hours: Double)]) -> (hours: Double, measured: Bool) {
        let priorRate = 100 / rated(hz)                // % pro Stunde laut Hersteller
        let priorWeight = 8.0                          // so viele Stunden zählt der Herstellerwert
        let st = stats[hz] ?? (0, 0)
        let rate = (st.dp + priorRate * priorWeight) / (st.hours + priorWeight)
        return (100 / rate, st.hours >= 6)
    }

    /// Ladegeschwindigkeit in % pro Stunde aus den letzten Messpunkten dieser Ladung.
    private func chargeRate(_ s: [BatterySample], now: Double, livePercent: Double) -> Double? {
        var pts: [(t: Double, p: Double)] = [(now, livePercent)]
        var prev = now
        for sample in s.reversed() {
            guard sample.c, prev - sample.t <= 20 * 60, now - sample.t <= 45 * 60 else { break }
            pts.append((sample.t, sample.p))
            prev = sample.t
        }
        guard pts.count >= 3, let first = pts.last, now - first.t >= 6 * 60 else { return nil }
        // Ausgleichsgerade (kleinste Quadrate) über t
        let n = Double(pts.count)
        let mt = pts.map { $0.t }.reduce(0, +) / n, mp = pts.map { $0.p }.reduce(0, +) / n
        let num = pts.map { ($0.t - mt) * ($0.p - mp) }.reduce(0, +)
        let den = pts.map { ($0.t - mt) * ($0.t - mt) }.reduce(0, +)
        guard den > 0 else { return nil }
        let perHour = num / den * 3600
        return perHour >= 1 ? perHour : nil
    }

    /// Schätzung für den aktuellen Akkustand. `hz` ist die gerade eingestellte Abfragerate (0 = unbekannt → 1000).
    func estimate(for info: BatteryInfo, hz: Int) -> BatteryEstimate {
        queue.sync {
            let rate = hz > 0 ? hz : 1000
            let now = Date().timeIntervalSince1970
            let stats = dischargeStats(samples)
            let current = BatteryTracker.runtimeHours(rate, stats)

            // Unbekannte Abfraterate: Messwert-Faktor (Akku hält besser/schlechter als angegeben) übernehmen
            var scale = 1.0
            if let best = stats.filter({ $0.value.hours >= 3 }).max(by: { $0.value.hours < $1.value.hours })?.key {
                scale = max(0.3, min(1.3, BatteryTracker.runtimeHours(best, stats).hours / BatteryTracker.rated(best)))
            }
            var perRate: [(hz: Int, runtime: TimeInterval, measured: Bool)] = []
            for r in [125, 500, 1000, 2000, 4000, 8000] {
                let own = BatteryTracker.runtimeHours(r, stats)
                let hours = (stats[r]?.hours ?? 0) >= 1 ? own.hours : BatteryTracker.rated(r) * scale
                perRate.append((r, hours * 3600, own.measured))
            }

            let dh = stats[rate]?.hours ?? 0
            let source: EstimateSource = dh >= 6 ? .measured : (dh >= 1 ? .learning : .rated)
            let hoursFull = (stats[rate]?.hours ?? 0) >= 1 ? current.hours : BatteryTracker.rated(rate) * scale

            var est = BatteryEstimate(percent: info.exact, charging: info.charging, hz: rate,
                                      isFull: info.charging && info.exact >= 99, toFull: nil, remaining: nil,
                                      fullRuntime: hoursFull * 3600, source: source, perRate: perRate)
            if info.charging {
                if let perHour = chargeRate(samples, now: now, livePercent: info.exact) {
                    let hours = (100 - info.exact) / perHour
                    if hours <= 24 { est.toFull = hours * 3600 }
                }
            } else {
                est.remaining = info.exact / 100 * hoursFull * 3600
            }
            return est
        }
    }
}

// MARK: - Text

/// "1 Std. 20 Min.", "35 Min.", "95 Std.", "ca. 5 Tage".
func formatDuration(_ seconds: TimeInterval) -> String {
    let minutes = Int((seconds / 60).rounded())
    if minutes < 1 { return "weniger als 1 Min." }
    if minutes < 60 { return "\(minutes) Min." }
    let hours = minutes / 60
    if hours < 10 { return "\(hours) Std. \(minutes % 60) Min." }
    if hours < 120 { return "\(Int((Double(minutes) / 60).rounded())) Std." }
    return String(format: "%.1f Tage", Double(hours) / 24).replacingOccurrences(of: ".", with: ",")
}

extension BatteryEstimate {
    var sourceNote: String {
        switch source {
        case .rated: return "Herstellerangabe"
        case .learning: return "Schätzung, lernt mit"
        case .measured: return "nach deinen Messungen"
        }
    }

    /// Nur der Wert für die Einstellungen: "ca. 1 Std. 20 Min.", "voll" oder "wird berechnet …".
    var statusValue: String {
        if charging {
            if isFull { return "voll" }
            return toFull.map { "ca. \(formatDuration($0))" } ?? "wird berechnet …"
        }
        return remaining.map { "ca. \(formatDuration($0))" } ?? "–"
    }

    /// Zeile für "wie lange noch": Laden → Zeit bis voll, sonst Restlaufzeit.
    var statusLine: String {
        if charging {
            if isFull { return "Akku voll" }
            if let t = toFull { return "Voll in ca. \(formatDuration(t))" }
            return "Zeit bis voll: wird berechnet …"
        }
        return remaining.map { "Hält noch ca. \(formatDuration($0))" } ?? ""
    }

    /// Nur der Wert, z. B. "ca. 17 Std. bei 8000 Hz".
    var runtimeValue: String { "ca. \(formatDuration(fullRuntime)) bei \(hz) Hz" }

    /// Zeile für "wie lange hält eine volle Ladung" bei den aktuellen Einstellungen.
    var runtimeLine: String {
        let prefix = charging ? "Danach" : "Volle Ladung"
        return "\(prefix) ca. \(formatDuration(fullRuntime)) (\(hz) Hz)"
    }
}

/// "48 % (ca. 8 Std.)" beim Entladen, "48 % · lädt (ca. 13 Min.)" beim Laden, "100 % · voll" wenn voll.
func batterySummary(_ b: BatteryInfo, _ e: BatteryEstimate?) -> String {
    var text = "\(b.percent) %"
    guard let e = e else { return b.charging ? text + " · lädt" : text }
    if b.charging {
        text += e.isFull ? " · voll" : " · lädt" + (e.toFull.map { " (ca. \(formatDuration($0)))" } ?? "")
    } else if let r = e.remaining {
        text += " (ca. \(formatDuration(r)))"
    }
    return text
}
