import Cocoa

struct DisplayInfo: Identifiable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let width: Int      // in Punkten (die Auflösung, die macOS wirklich nutzt)
    let height: Int
}

/// Merkt sich, auf welchem Bildschirm der Mauszeiger gerade ist (für DPI je Bildschirm und den Auflösungs-Ausgleich).
enum Displays {
    static var activeID: CGDirectDisplayID = CGMainDisplayID()
    static var onChange: (() -> Void)?

    static func uuid(_ id: CGDirectDisplayID) -> String {
        guard let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "\(id)" }
        return CFUUIDCreateString(nil, u) as String
    }

    static var activeUUID: String { uuid(activeID) }

    static func widthPoints(_ id: CGDirectDisplayID) -> Double { Double(CGDisplayBounds(id).width) }

    /// Punkte pro Millimeter (Diagonale in Punkten / Diagonale in mm). Unabhängig davon, ob der Bildschirm gedreht ist.
    /// Je höher, desto kleiner erscheint ein Punkt, und desto mehr DPI braucht der Zeiger für dasselbe Tempo.
    static func density(_ id: CGDirectDisplayID) -> Double {
        let b = CGDisplayBounds(id)
        let mm = CGDisplayScreenSize(id)
        let diagPoints = hypot(Double(b.width), Double(b.height))
        let diagMM = hypot(Double(mm.width), Double(mm.height))
        return diagMM > 50 ? diagPoints / diagMM : Double(b.width) / 600   // ohne Größenangabe: 600 mm Breite annehmen
    }

    private static func idUnderCursor() -> CGDirectDisplayID {
        guard let loc = CGEvent(source: nil)?.location else { return CGMainDisplayID() }
        var id: CGDirectDisplayID = 0
        var count: UInt32 = 0
        if CGGetDisplaysWithPoint(loc, 1, &id, &count) == .success, count > 0 { return id }
        return CGMainDisplayID()
    }

    /// Alle angeschlossenen Bildschirme (nur vom Hauptthread aufrufen).
    static func all() -> [DisplayInfo] {
        NSScreen.screens.compactMap { s in
            guard let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            return DisplayInfo(id: num, uuid: uuid(num), name: s.localizedName,
                               width: Int(s.frame.width), height: Int(s.frame.height))
        }
    }

    static func start() {
        activeID = idUnderCursor()
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            let id = idUnderCursor()
            guard id != activeID else { return }
            activeID = id
            if settings.debug { log("Zeiger auf Bildschirm \(uuid(id)) (Breite \(Int(widthPoints(id))))") }
            onChange?()
        }
    }
}
