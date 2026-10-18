import Cocoa
import IOKit
import IOKit.hidsystem

/// Hält die Zeigergeschwindigkeit der Maus auf einem festen Wert, unabhängig vom Regler in den Systemeinstellungen.
/// Der feste Wert ist zunächst die Einstellung, die gerade im System steht, die Beschleunigungskurve bleibt erhalten.
/// Beim Beenden stellt MacMouse den Systemwert wieder her. Das Trackpad ist nicht betroffen.
enum Pointer {
    private static var connection: io_connect_t = 0
    private static var applied: String?
    private static let key = "HIDMouseAcceleration" as CFString   // kIOHIDMouseAccelerationType

    private static func handle() -> io_connect_t {
        if connection == 0 { connection = NXOpenEventStatus() }
        return connection
    }

    /// Der Wert aus den Systemeinstellungen ("com.apple.mouse.scaling", 0 … 3).
    private static func systemValue() -> Double {
        let v = CFPreferencesCopyValue("com.apple.mouse.scaling" as CFString, kCFPreferencesAnyApplication,
                                       kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let d = (v as? Double) ?? 0.6875
        return d > 0 ? d : 0.6875    // -1 (Beschleunigung aus) oder 0 würden die Maus bremsen
    }

    /// Der feste Wert: gespeichert, sonst der aktuelle Systemwert (wird dann gleich gespeichert).
    private static func fixedValue() -> Double {
        if let v = settings.pointerSpeed, v > 0 { return v }
        let v = systemValue()
        DispatchQueue.main.async { settings.write(["pointerSpeed": v]) }
        return v
    }

    private static func set(_ value: Double) -> IOReturn { IOHIDSetAccelerationWithKey(handle(), key, value) }

    static func apply() {
        let mode = settings.pointerAcceleration
        if mode == applied { return }
        // Beim Start im Modus "system" nichts anfassen
        if applied == nil && mode != "fixed" { applied = mode; return }
        let value = mode == "fixed" ? fixedValue() : systemValue()
        let rc = set(value)
        applied = mode
        log(rc == KERN_SUCCESS ? "Mausgeschwindigkeit: \(mode == "fixed" ? "fest" : "wie im System") (\(String(format: "%.2f", value)))"
                               : "Mausgeschwindigkeit setzen fehlgeschlagen (0x\(String(UInt32(bitPattern: rc), radix: 16)))")
    }

    /// Ändert sich der feste Wert im Einstellungsfenster, wird er sofort übernommen.
    static func updateFixed() {
        guard applied == "fixed", let v = settings.pointerSpeed, v > 0 else { return }
        _ = set(v)
    }

    /// Ändert jemand die Mausgeschwindigkeit in den Systemeinstellungen, schreibt macOS den Wert neu. Dann wird er
    /// hier wieder auf den festen Wert gesetzt (wird jede Sekunde geprüft, kostet praktisch nichts).
    static func reassert() {
        guard applied == "fixed", let target = settings.pointerSpeed, target > 0 else { return }
        var current = 0.0
        IOHIDGetAccelerationWithKey(handle(), key, &current)
        if abs(current - target) > 0.001 {
            _ = set(target)
            log("Mausgeschwindigkeit in den Systemeinstellungen geändert – fester Wert gilt weiter")
        }
    }

    /// Beim Beenden: Systemwert zurück.
    static func restore() {
        guard applied == "fixed" else { return }
        _ = set(systemValue())
    }
}
