import Foundation
import IOKit.hid

/// Abhebe-Distanz des Sensors (Befehle nach dem Fang-Projekt, Razer-Generation der DeathAdder/Viper V3 Pro).
enum LiftOff: Equatable {
    case preset(Int)                       // 1 = niedrig, 2 = mittel, 3 = hoch
    case asymmetric(lift: Int, land: Int)  // Razer-Skala: lift 2…26, land 1…25, land < lift

    var isValid: Bool {
        switch self {
        case .preset(let l): return (1...3).contains(l)
        case .asymmetric(let lift, let land): return (2...26).contains(lift) && (1...25).contains(land) && land < lift
        }
    }
}

struct BatteryInfo {
    var percent: Int
    var charging: Bool
    var exact: Double      // Prozent mit Nachkommastellen (aus dem 0–255-Rohwert)
}

/// Razer-Protokoll über USB-HID Feature Reports (90 Byte). Befehle nach OpenRazer (Viper V3 Pro, Kabel).
enum Razer {
    static let vendorID = 0x1532
    static var manager: IOHIDManager?
    static var txCandidates: [UInt8] = [0x1F, 0x3F, 0xFF, 0x08, 0x00]
    static var lastError = ""
    private static let lock = NSLock()   // Befehle von Menü, Fenster und Hintergrund nie gleichzeitig senden

    static let matching: CFDictionary = [
        "VendorID": vendorID,
        "PrimaryUsagePage": 1,   // Generic Desktop
        "PrimaryUsage": 2,       // Mouse
    ] as CFDictionary

    /// Findet die Razer-Maus-Schnittstelle, über die Befehle laufen (Feature Report 90 Byte).
    private static func findDevice() -> IOHIDDevice? {
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)   // zeigt den macOS-Dialog
        }
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, matching)
        let rc = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        if rc != kIOReturnSuccess {
            let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
            let accessText = access == kIOHIDAccessTypeGranted ? "erlaubt" : (access == kIOHIDAccessTypeDenied ? "verweigert" : "unbestimmt")
            lastError = rc == kIOReturnNotPermitted
                ? "Zugriff auf die Maus verweigert (Eingabeüberwachung: \(accessText)) – Eingabeüberwachung erlauben oder Programm beenden, das die Maus exklusiv belegt"
                : "HID-Manager konnte nicht geöffnet werden (0x\(String(UInt32(bitPattern: rc), radix: 16)))"
            return nil
        }
        manager = mgr
        let devices = (IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>) ?? []
        for dev in devices {
            let size = IOHIDDeviceGetProperty(dev, "MaxFeatureReportSize" as CFString) as? Int ?? 0
            if size >= 90 && IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess {
                return dev
            }
        }
        lastError = "Keine Razer-Maus gefunden (angesteckt? Dongle/Kabel verbunden?)"
        return nil
    }

    private static func withDevice<T>(_ body: (IOHIDDevice) -> T?) -> T? {
        lock.lock(); defer { lock.unlock() }
        guard let dev = findDevice() else { return nil }
        return body(dev)
    }

    private static func transaction(_ dev: IOHIDDevice, cls: UInt8, id: UInt8, size: UInt8, args: [UInt8]) -> [UInt8]? {
        for tid in txCandidates {
            var req = [UInt8](repeating: 0, count: 90)
            req[1] = tid; req[5] = size; req[6] = cls; req[7] = id
            for (i, a) in args.enumerated() { req[8 + i] = a }
            var crc: UInt8 = 0
            for i in 2..<88 { crc ^= req[i] }
            req[88] = crc

            for attempt in 0..<4 {
                let rc = IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, 0, req, 90)
                guard rc == kIOReturnSuccess else {
                    lastError = "SetReport fehlgeschlagen (0x\(String(UInt32(bitPattern: rc), radix: 16)))"
                    break
                }
                usleep(40_000)
                var resp = [UInt8](repeating: 0, count: 90)
                var len = 90
                let rc2 = IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, 0, &resp, &len)
                guard rc2 == kIOReturnSuccess else {
                    lastError = "GetReport fehlgeschlagen (0x\(String(UInt32(bitPattern: rc2), radix: 16)))"
                    break
                }
                if resp[0] == 0x02 {
                    txCandidates = [tid]   // diese Transaktions-ID passt zur Maus
                    return resp
                }
                lastError = "Maus antwortet mit Status 0x\(String(resp[0], radix: 16)) (Transaktions-ID 0x\(String(tid, radix: 16)))"
                if resp[0] == 0x01 && attempt < 3 { usleep(150_000); continue }   // beschäftigt → nochmal
                if resp[0] == 0x01 { return nil }                                  // weiter beschäftigt (z. B. Ruhemodus): aufgeben
                if resp[0] == 0x05 { return nil }                                  // Befehl wird nicht unterstützt
                break
            }
        }
        return nil
    }

    /// Rohbefehl (für Diagnose und neue Funktionen). Gibt die 90 Antwort-Bytes zurück.
    static func raw(cls: UInt8, id: UInt8, size: UInt8, args: [UInt8]) -> [UInt8]? {
        withDevice { dev in transaction(dev, cls: cls, id: id, size: size, args: args) }
    }

    // MARK: DPI

    static func getDPI() -> (x: Int, y: Int)? {
        withDevice { dev in
            transaction(dev, cls: 0x04, id: 0x85, size: 7, args: [0x01]).map {
                (Int($0[9]) << 8 | Int($0[10]), Int($0[11]) << 8 | Int($0[12]))
            }
        }
    }

    @discardableResult
    static func setDPI(_ value: Int) -> Bool {
        let v = max(100, min(35_000, value))
        let args: [UInt8] = [0x01, UInt8(v >> 8), UInt8(v & 0xFF), UInt8(v >> 8), UInt8(v & 0xFF)]
        return withDevice { dev in transaction(dev, cls: 0x04, id: 0x05, size: 7, args: args) != nil ? true : nil } ?? false
    }

    // MARK: Akku

    static func battery() -> BatteryInfo? {
        withDevice { dev in
            guard let level = transaction(dev, cls: 0x07, id: 0x80, size: 2, args: []) else { return nil }
            let charging = transaction(dev, cls: 0x07, id: 0x84, size: 2, args: [])?[9] == 1
            let exact = Double(level[9]) / 255 * 100
            return BatteryInfo(percent: Int(exact.rounded()), charging: charging, exact: exact)
        }
    }

    // MARK: Abfragerate (Hz)
    // Ältere Firmware nutzt Befehl 0x05/0x85 (125/500/1000), neuere 0x40/0xC0 (bis 8000). Welcher passt, merkt sich MacMouse.

    private static let codesV1: [UInt8: Int] = [0x01: 1000, 0x02: 500, 0x08: 125]
    private static let codesV2: [UInt8: Int] = [0x01: 8000, 0x02: 4000, 0x04: 2000, 0x08: 1000, 0x10: 500, 0x20: 250, 0x40: 125]
    private static var pollingV2: Bool?
    /// Zuletzt gelesene/gesetzte Abfragerate (für den Akku-Verlauf, ohne die Maus erneut zu fragen).
    static var knownPollingRate: Int?

    /// Mögliche Abfraten für das Auswahlmenü (je nach Befehlssatz).
    static var pollingRates: [Int] { pollingV2 == true ? [125, 500, 1000, 2000, 4000, 8000] : [125, 500, 1000] }

    static func getPollingRate() -> Int? {
        withDevice { dev in
            if pollingV2 != true, let r = transaction(dev, cls: 0x00, id: 0x85, size: 1, args: []), let hz = codesV1[r[8]] {
                pollingV2 = false
                knownPollingRate = hz
                return hz
            }
            if let r = transaction(dev, cls: 0x00, id: 0xC0, size: 1, args: []), let hz = codesV2[r[9]] {
                pollingV2 = true
                knownPollingRate = hz
                return hz
            }
            return nil
        }
    }

    @discardableResult
    static func setPollingRate(_ hz: Int) -> Bool {
        if pollingV2 == nil { _ = getPollingRate() }
        return withDevice { dev in
            if pollingV2 == true {
                guard let code = codesV2.first(where: { $0.value == hz })?.key else { return nil }
                return transaction(dev, cls: 0x00, id: 0x40, size: 2, args: [0x00, code]) != nil ? { knownPollingRate = hz; return true }() : nil
            }
            guard let code = codesV1.first(where: { $0.value == hz })?.key else { return nil }
            return transaction(dev, cls: 0x00, id: 0x05, size: 1, args: [code]) != nil ? { knownPollingRate = hz; return true }() : nil
        } ?? false
    }

    // MARK: Abschaltzeit (Sekunden, 60–900)

    static func getIdleTime() -> Int? {
        withDevice { dev in
            transaction(dev, cls: 0x07, id: 0x83, size: 2, args: []).map { Int($0[8]) << 8 | Int($0[9]) }
        }
    }

    @discardableResult
    static func setIdleTime(_ seconds: Int) -> Bool {
        let s = max(60, min(900, seconds))
        return withDevice { dev in
            transaction(dev, cls: 0x07, id: 0x03, size: 2, args: [UInt8(s >> 8), UInt8(s & 0xFF)]) != nil ? true : nil
        } ?? false
    }

    // MARK: Abhebe-Distanz (Lift-off)

    private static func pad(_ head: [UInt8], _ size: Int) -> [UInt8] { head + [UInt8](repeating: 0, count: max(0, size - head.count)) }

    /// Zuletzt gesetzte eigene Werte. Die Viper V3 Pro meldet Abheben/Aufsetzen beim Lesen nicht zurück,
    /// nur den Modus; die Werte merkt sich MacMouse selbst (und die Config).
    private static var lastAsymmetric: LiftOff?

    private static func readLiftOff(_ dev: IOHIDDevice) -> LiftOff? {
        guard let setting = transaction(dev, cls: 0x0B, id: 0x8B, size: 4, args: [0x00, 0x04, 0x01, 0x00]) else { return nil }
        switch setting[10] {
        case 0x01: return .preset(Int(setting[11]) + 1)
        case 0x04:
            if let r = transaction(dev, cls: 0x0B, id: 0x85, size: 10, args: pad([0x00, 0x04], 10)), r[12] != 0 || r[13] != 0 {
                return .asymmetric(lift: Int(r[12]) + 1, land: Int(r[13]) + 1)
            }
            return lastAsymmetric ?? settings.liftOff.flatMap { if case .asymmetric = $0 { return $0 } else { return nil } }
                ?? .asymmetric(lift: 13, land: 12)
        default: return nil
        }
    }

    /// Schreibt die Werte. Gibt bei eigenen Werten die Antwort auf den letzten Befehl mit zurück.
    private static func writeLiftOff(_ dev: IOHIDDevice, _ lo: LiftOff) -> (ok: Bool, echo: [UInt8]?) {
        switch lo {
        case .preset(let level):
            let ok = transaction(dev, cls: 0x0B, id: 0x03, size: 3, args: [0x00, 0x04, 0x00]) != nil
                && transaction(dev, cls: 0x0B, id: 0x0B, size: 4, args: [0x00, 0x04, 0x01, UInt8(level - 1)]) != nil
            return (ok, nil)
        case .asymmetric(let lift, let land):
            guard transaction(dev, cls: 0x0B, id: 0x03, size: 3, args: [0x00, 0x04, 0x01]) != nil,
                  transaction(dev, cls: 0x0B, id: 0x0B, size: 4, args: [0x00, 0x04, 0x04, 0x00]) != nil,
                  let echo = transaction(dev, cls: 0x0B, id: 0x05, size: 10, args: pad([0x00, 0x04, UInt8(lift - 1), UInt8(land - 1)], 10))
            else { return (false, nil) }
            return (true, echo)
        }
    }

    /// Stimmt das, was die Maus nach dem Schreiben meldet, mit dem Wunsch überein?
    private static func confirmed(_ dev: IOHIDDevice, _ lo: LiftOff, _ result: (ok: Bool, echo: [UInt8]?)) -> Bool {
        guard result.ok else { return false }
        switch lo {
        case .preset: return readLiftOff(dev) == lo
        case .asymmetric(let lift, let land):
            // Werte aus der Antwort auf den Schreibbefehl, Modus per Lesen (die Werte selbst lassen sich nicht lesen)
            guard let echo = result.echo, Int(echo[10]) == lift - 1, Int(echo[11]) == land - 1 else { return false }
            guard let m = transaction(dev, cls: 0x0B, id: 0x8B, size: 4, args: [0x00, 0x04, 0x01, 0x00]), m[10] == 0x04 else { return false }
            lastAsymmetric = lo
            return true
        }
    }

    static func getLiftOff() -> LiftOff? { withDevice { readLiftOff($0) } }

    /// Schreibt die Abhebe-Distanz, prüft die Antwort der Maus und setzt bei einer Abweichung den alten Wert zurück.
    @discardableResult
    static func setLiftOff(_ lo: LiftOff) -> Bool {
        guard lo.isValid else { lastError = "Ungültiger Wert für die Abhebe-Distanz"; return false }
        return withDevice { dev in
            let before = readLiftOff(dev)
            if confirmed(dev, lo, writeLiftOff(dev, lo)) { return true }
            lastError = "Die Maus hat die Abhebe-Distanz nicht übernommen" + (before == nil ? "" : " (alter Wert wurde wiederhergestellt)")
            if let b = before { _ = writeLiftOff(dev, b) }
            return nil
        } ?? false
    }
}
