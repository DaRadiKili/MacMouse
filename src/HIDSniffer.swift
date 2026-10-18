import Foundation
import IOKit.hid

private func hex(_ n: Int) -> String { "0x" + String(n, radix: 16) }

/// Diagnose: schreibt alle Signale der Razer-Maus (Tasten, Tastatur-Schnittstelle, Herstellerdaten) ins Log.
/// Bewegung und Mausrad werden ausgelassen. Wird nur mit `"debug": true` gestartet.
enum HIDSniffer {
    private static var manager: IOHIDManager?

    static func start() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, ["VendorID": Razer.vendorID] as CFDictionary)

        // Einzelne Elemente: Tasten (Seite 9), Tastatur (Seite 7), Hersteller (Seite 0xFF00 …)
        IOHIDManagerRegisterInputValueCallback(mgr, { _, _, sender, value in
            let element = IOHIDValueGetElement(value)
            let page = Int(IOHIDElementGetUsagePage(element))
            let usage = Int(IOHIDElementGetUsage(element))
            if page == 1 && [0x30, 0x31, 0x38].contains(usage) { return }   // X, Y, Rad
            let v = IOHIDValueGetIntegerValue(value)
            var interface = "?"
            if let s = sender {
                let dev = Unmanaged<IOHIDDevice>.fromOpaque(s).takeUnretainedValue()
                let up = IOHIDDeviceGetProperty(dev, "PrimaryUsagePage" as CFString) as? Int ?? 0
                let u = IOHIDDeviceGetProperty(dev, "PrimaryUsage" as CFString) as? Int ?? 0
                interface = "\(hex(up))/\(hex(u))"
            }
            log("HID [Schnittstelle \(interface)] Seite \(hex(page)), Usage \(hex(usage)), Wert \(v)")
        }, nil)

        // Rohe Berichte (für Herstellerdaten, die keine normale Taste sind)
        IOHIDManagerRegisterInputReportCallback(mgr, { _, _, sender, _, reportID, report, length in
            var interface = "?"
            if let s = sender {
                let dev = Unmanaged<IOHIDDevice>.fromOpaque(s).takeUnretainedValue()
                let up = IOHIDDeviceGetProperty(dev, "PrimaryUsagePage" as CFString) as? Int ?? 0
                let u = IOHIDDeviceGetProperty(dev, "PrimaryUsage" as CFString) as? Int ?? 0
                interface = "\(hex(up))/\(hex(u))"
                if up == 1 && u == 2 && length <= 12 { return }    // normale Mausberichte (Bewegung) auslassen
            }
            let bytes = (0..<min(Int(length), 24)).map { String(format: "%02x", report[$0]) }.joined(separator: " ")
            log("HID-Bericht [Schnittstelle \(interface)] ID \(reportID), \(length) Byte: \(bytes)")
        }, nil)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr
        log("HID-Mithören aktiv (debug)")
    }
}
