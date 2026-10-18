import Cocoa

// MARK: - Maustasten und Gesten-Taste (Event Tap)

var eventTap: CFMachPort?

/// Markiert von uns erzeugte Klicks, damit der Tap sie nicht erneut abfängt.
let clickMarker: Int64 = 0x4D415553

/// Laufende Gesten-Taste. Der Zeiger bewegt sich normal mit, nur bei einem fließenden Wisch (Desktop-Wechsel)
/// wird er eingefroren, weil dann der Desktop der Maus folgt und der Zeiger nicht mitlaufen soll.
final class GestureState {
    let button: Int
    let since = Date()
    var dx = 0.0, dy = 0.0
    var fired = false          // Sprung: Aktion schon ausgelöst
    var locked = false         // Richtung steht fest → beim Loslassen kein normaler Klick mehr
    var jumpVertical = false   // Fließender Modus, aber hoch/runter als einmalige Aktion
    var swipe: DockSwipe?      // Fließender Modus: laufender Dock-Swipe
    let start: CGPoint         // Zeigerposition beim Drücken
    init(button: Int) {
        self.button = button
        start = CGEvent(source: nil)?.location ?? .zero
    }
}

var gesture: GestureState?

/// Zeiger an der Startposition festhalten (nur während eines fließenden Wischs).
private func freezeCursor(at p: CGPoint) {
    CGWarpMouseCursorPosition(p)
    CGAssociateMouseAndMouseCursorPosition(0)
}

func resetGesture() {
    if let s = gesture?.swipe { s.end(cancel: true) }   // nie einen halben Swipe im Dock hängen lassen
    gesture = nil
    CGAssociateMouseAndMouseCursorPosition(1)           // Cursor wieder freigeben
}

/// Normaler Klick der Taste, wenn nicht gewischt wurde.
func replayClick(_ n: Int) {
    let loc = CGEvent(source: nil)?.location ?? .zero
    for type in [CGEventType.otherMouseDown, .otherMouseUp] {
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: loc,
                              mouseButton: CGMouseButton(rawValue: UInt32(n)) ?? .center) else { continue }
        e.setIntegerValueField(.mouseEventButtonNumber, value: Int64(n))
        e.setIntegerValueField(.eventSourceUserData, value: clickMarker)
        e.post(tap: .cghidEventTap)
    }
}

private func handleGestureButton(_ n: Int, _ map: [String: String], _ type: CGEventType, _ event: CGEvent) {
    switch type {
    case .otherMouseDown:
        gesture = GestureState(button: n)               // Zeiger bleibt frei beweglich

    case .otherMouseDragged:
        guard let g = gesture, g.button == n else { return }
        let mx = event.getDoubleValueField(.mouseEventDeltaX)
        let my = event.getDoubleValueField(.mouseEventDeltaY)
        if settings.gestureMode == "smooth" && DockSwipe.available {
            if let s = g.swipe {
                s.change(dx: mx, dy: my)
            } else if g.jumpVertical {
                // hoch/runter als Sprung: erst bei genug Bewegung einmal auslösen, egal wie weit danach
                g.dy += my
                if !g.fired && abs(g.dy) >= settings.gestureThreshold {
                    g.fired = true
                    let dir = g.dy > 0 ? "down" : "up"
                    if settings.debug { log("Geste: \(dir)") }
                    if let spec = map[dir] { DispatchQueue.main.async { perform(spec) } }
                }
            } else {
                g.dx += mx; g.dy += my
                if max(abs(g.dx), abs(g.dy)) >= settings.gestureLock {
                    g.locked = true
                    let axis: DockSwipe.Axis = abs(g.dx) >= abs(g.dy) ? .horizontal : .vertical
                    if settings.debug { log("Swipe startet: \(axis == .horizontal ? "horizontal" : "vertikal")") }
                    if axis == .vertical && settings.gestureVertical == "jump" {
                        g.jumpVertical = true
                    } else {
                        let s = DockSwipe(axis: axis, invert: settings.gestureInvert)
                        g.swipe = s
                        freezeCursor(at: g.start)
                        s.begin(dx: g.dx, dy: g.dy)
                    }
                }
            }
        } else if !g.fired {
            g.dx += mx; g.dy += my
            if max(abs(g.dx), abs(g.dy)) >= settings.gestureThreshold {
                g.fired = true
                let dir = abs(g.dx) > abs(g.dy) ? (g.dx > 0 ? "right" : "left") : (g.dy > 0 ? "down" : "up")
                if settings.debug { log("Geste: \(dir)") }
                if let spec = map[dir] { DispatchQueue.main.async { perform(spec) } }
            }
        }

    case .otherMouseUp:
        guard let g = gesture, g.button == n else { return }
        gesture = nil
        CGAssociateMouseAndMouseCursorPosition(1)
        if let s = g.swipe {
            s.end()
        } else if !g.fired && !g.locked {
            let spec = map["click"] ?? "passthrough"
            DispatchQueue.main.async { spec.lowercased() == "passthrough" ? replayClick(n) : perform(spec) }
        }

    default: break
    }
}

let tapCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = eventTap { CGEvent.tapEnable(tap: t, enable: true) }
        if gesture != nil { resetGesture() }
        return Unmanaged.passUnretained(event)
    }
    if event.getIntegerValueField(.eventSourceUserData) == clickMarker {
        return Unmanaged.passUnretained(event)
    }
    let n = Int(event.getIntegerValueField(.mouseEventButtonNumber))
    if settings.debug && type == .otherMouseDown { log("Taste \(n) gedrückt") }

    if let map = settings.gestureButtons[n] {
        handleGestureButton(n, map, type, event)
        return nil
    }
    // Doppelklick/Halten festgelegt → eigene Zeitlogik
    let extras = settings.buttonExtras[n]
    let double = usableAction(extras?["double"]), hold = usableAction(extras?["hold"])
    if double != nil || hold != nil {
        MultiButton.handle(n, type, single: settings.buttons[n] ?? "passthrough", double: double, hold: hold)
        return nil
    }
    guard let spec = settings.buttons[n], spec.lowercased() != "passthrough" else {
        return Unmanaged.passUnretained(event)
    }
    if type == .otherMouseDown { DispatchQueue.main.async { perform(spec) } }
    return nil   // Klick schlucken (Down und Up)
}

func startButtonTap() {
    let mask: CGEventMask = (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
        | (1 << CGEventType.otherMouseDragged.rawValue)
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                      eventsOfInterest: mask, callback: tapCallback, userInfo: nil) else {
        log("Event-Tap fehlgeschlagen – bitte Bedienungshilfen + Eingabeüberwachung erlauben und neu starten")
        return
    }
    eventTap = tap
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
}

// MARK: - Trackpad-Gesten

var magnifyAccum = 0.0
var rotateAccum = 0.0

func fireGesture(_ name: String) {
    guard let spec = settings.gestures[name] else { return }
    perform(spec)
}

func startGestures() {
    NSEvent.addGlobalMonitorForEvents(matching: [.swipe, .magnify, .rotate]) { e in
        switch e.type {
        case .swipe:
            if e.deltaX > 0 { fireGesture("swipeLeft") }
            else if e.deltaX < 0 { fireGesture("swipeRight") }
            else if e.deltaY > 0 { fireGesture("swipeUp") }
            else if e.deltaY < 0 { fireGesture("swipeDown") }
        case .magnify:
            if e.phase == .began { magnifyAccum = 0 }
            magnifyAccum += Double(e.magnification)
            if e.phase == .ended {
                if magnifyAccum > 0.3 { fireGesture("pinchOut") }
                else if magnifyAccum < -0.3 { fireGesture("pinchIn") }
            }
        case .rotate:
            if e.phase == .began { rotateAccum = 0 }
            rotateAccum += Double(e.rotation)
            if e.phase == .ended {
                if rotateAccum > 20 { fireGesture("rotateLeft") }
                else if rotateAccum < -20 { fireGesture("rotateRight") }
            }
        default: break
        }
    }
}

// MARK: - Doppelklick und Halten

/// nil, wenn die Aktion leer oder "none" ist.
private func usableAction(_ spec: String?) -> String? {
    guard let s = spec?.trimmingCharacters(in: .whitespaces), !s.isEmpty, s.lowercased() != "none" else { return nil }
    return s
}

private final class MultiButtonState {
    var holdWork: DispatchWorkItem?
    var singleWork: DispatchWorkItem?   // wartet, ob ein zweiter Klick kommt
    var holdFired = false
    var consumed = false                // Doppelklick wurde schon ausgelöst
}

/// Unterscheidet Tippen, Doppelklick und Halten für eine Taste. Hat eine Taste Doppelklick oder Halten, löst der
/// normale Klick erst beim Loslassen (bzw. nach dem Doppelklick-Fenster) aus.
enum MultiButton {
    private static var states: [Int: MultiButtonState] = [:]
    static let holdTime = 0.35
    static let doubleWindow = 0.28

    static func handle(_ n: Int, _ type: CGEventType, single: String, double: String?, hold: String?) {
        let st = states[n] ?? MultiButtonState()
        states[n] = st
        switch type {
        case .otherMouseDown:
            st.holdFired = false
            st.consumed = false
            if let w = st.singleWork {                 // zweiter Druck innerhalb des Fensters
                w.cancel(); st.singleWork = nil
                if let d = double { st.consumed = true; fire(d, n); return }
            }
            if let h = hold {
                let w = DispatchWorkItem { st.holdFired = true; fire(h, n) }
                st.holdWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + holdTime, execute: w)
            }
        case .otherMouseUp:
            st.holdWork?.cancel(); st.holdWork = nil
            if st.holdFired || st.consumed { return }
            if double != nil {
                let w = DispatchWorkItem { st.singleWork = nil; fire(single, n) }
                st.singleWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + doubleWindow, execute: w)
            } else {
                fire(single, n)
            }
        default:
            break
        }
    }

    private static func fire(_ spec: String, _ n: Int) {
        if spec.lowercased() == "passthrough" { replayClick(n) } else { perform(spec) }
    }
}
