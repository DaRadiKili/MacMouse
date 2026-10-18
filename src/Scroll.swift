import Cocoa

/// Mausrad: Richtung getrennt vom Trackpad umkehren und optional weich scrollen.
/// Trackpad und Magic Mouse (fortlaufende Scroll-Events) bleiben immer unverändert.

let scrollMarker: Int64 = 0x53435231

/// Verteilt Rad-Schritte über kurze Zeit als Pixel-Scrollen (ease-out), statt sie ruckartig zu springen.
final class SmoothScroller {
    static let shared = SmoothScroller()

    private let pixelsPerStep = 55.0
    private let maxRemaining = 4000.0
    private var remX = 0.0, remY = 0.0       // noch zu scrollende Pixel
    private var carryX = 0.0, carryY = 0.0   // Bruchteile, die noch keinen ganzen Pixel ergeben
    private var timer: Timer?

    func add(dx: Double, dy: Double) {
        let px = pixelsPerStep * settings.scrollSpeed
        remX = max(-maxRemaining, min(maxRemaining, remX + dx * px))
        remY = max(-maxRemaining, min(maxRemaining, remY + dy * px))
        if timer == nil {
            let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    private func tick() {
        // Anteil des Rests pro Tick: 0.5 (knackig) … 0.06 (sehr weich)
        let f = 0.5 - 0.44 * max(0, min(1, settings.scrollSmoothness))
        let sx = abs(remX) < 1 ? remX : remX * f
        let sy = abs(remY) < 1 ? remY : remY * f
        remX -= sx; remY -= sy
        carryX += sx; carryY += sy
        let ix = Int32(carryX.rounded(.towardZero)), iy = Int32(carryY.rounded(.towardZero))
        carryX -= Double(ix); carryY -= Double(iy)
        if ix != 0 || iy != 0 { post(dx: ix, dy: iy) }
        if remX == 0 && remY == 0 {
            timer?.invalidate(); timer = nil
            carryX = 0; carryY = 0
        }
    }

    private func post(dx: Int32, dy: Int32) {
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                              wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        e.setIntegerValueField(.eventSourceUserData, value: scrollMarker)
        e.post(tap: .cghidEventTap)
    }
}

var scrollTap: CFMachPort?

let scrollCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = scrollTap { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard type == .scrollWheel, settings.scrollInvertMouse || settings.smoothScroll,
          event.getIntegerValueField(.eventSourceUserData) != scrollMarker,                // eigene Events
          event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else {            // Trackpad / Magic Mouse
        return Unmanaged.passUnretained(event)
    }
    let sign = settings.scrollInvertMouse ? -1.0 : 1.0

    // Mit Cmd/Ctrl/Alt (Zoomen, schnelles Scrollen …) nicht glätten
    if settings.smoothScroll, event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
        let dy = event.getDoubleValueField(.scrollWheelEventDeltaAxis1) * sign
        let dx = event.getDoubleValueField(.scrollWheelEventDeltaAxis2) * sign
        if dx != 0 || dy != 0 { SmoothScroller.shared.add(dx: dx, dy: dy) }
        return nil
    }

    if settings.scrollInvertMouse {
        // Erst alle Originalwerte lesen: Das Setzen eines Feldes rechnet verwandte Felder neu, sonst würde ein
        // zweites Umkehren den schon geänderten Wert wieder drehen.
        let ints: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
                                    .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2]
        let fixed: [CGEventField] = [.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2]
        let intValues = ints.map { event.getIntegerValueField($0) }
        let fixedValues = fixed.map { event.getDoubleValueField($0) }
        for (f, v) in zip(ints, intValues) { event.setIntegerValueField(f, value: -v) }
        for (f, v) in zip(fixed, fixedValues) { event.setDoubleValueField(f, value: -v) }
    }
    return Unmanaged.passUnretained(event)
}

func startScrollTap() {
    let mask: CGEventMask = 1 << CGEventType.scrollWheel.rawValue
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                      eventsOfInterest: mask, callback: scrollCallback, userInfo: nil) else {
        log("Scroll-Tap fehlgeschlagen – Bedienungshilfen erlauben")
        return
    }
    scrollTap = tap
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
}
