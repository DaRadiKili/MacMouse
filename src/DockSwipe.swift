import Cocoa

/// Simuliert einen Trackpad-3-Finger-Wisch fürs Dock (Desktop wechseln, Mission Control, App Exposé).
///
/// Ab macOS 27 liest das Dock dafür ein IOHIDEvent (Typ DockSwipe), das in ein CGEvent vom Typ 30 gepackt wird.
/// Alles hier sind undokumentierte System-Schnittstellen und können sich mit macOS-Updates ändern.
/// Ohne die nötigen Symbole ist `available` false, und der Aufrufer fällt auf Tastenkürzel zurück.
final class DockSwipe {
    enum Axis: Int64 { case horizontal = 1, vertical = 2 }
    private enum Phase: UInt32 { case began = 1, changed = 2, ended = 4, cancelled = 8 }

    // IOHIDEvent-Konstanten (IOHIDEventTypes.h / IOHIDEventFieldDefs.h)
    private static let typeDockSwipe: UInt32 = 23
    private static let typeVelocity: UInt32 = 9
    private static let fieldMotion: UInt32 = (23 << 16) | 1
    private static let fieldProgress: UInt32 = (23 << 16) | 2
    private static let fieldFlavor: UInt32 = (23 << 16) | 5
    private static let flavorDockPrimary: Int64 = 3
    private static let phaseShift: UInt32 = 24
    private static let spaceSeparatorWidth = 63.0
    private static let exitSpeedFactor = 100.0

    // MARK: Zugriff auf die privaten Funktionen

    private typealias InitFn = @convention(c) (AnyObject, Selector, UInt32, UInt64, UInt64) -> Unmanaged<AnyObject>?
    private typealias OptionsFn = @convention(c) (AnyObject, Selector, UInt32) -> Void
    private typealias IntFn = @convention(c) (AnyObject, Selector, Int64, UInt32) -> Void
    private typealias DoubleFn = @convention(c) (AnyObject, Selector, Double, UInt32) -> Void
    private typealias AppendFn = @convention(c) (AnyObject, Selector, AnyObject) -> Void
    private typealias SetHIDEventFn = @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> Void
    private typealias SetTypeFn = @convention(c) (UnsafeRawPointer, UInt32) -> Void

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    private static let hidClass: AnyClass? = NSClassFromString("HIDEvent")

    private static let selInit = NSSelectorFromString("initWithType:timestamp:senderID:")
    private static let selOptions = NSSelectorFromString("setOptions:")
    private static let selInt = NSSelectorFromString("setIntegerValue:forField:")
    private static let selDouble = NSSelectorFromString("setDoubleValue:forField:")
    private static let selAppend = NSSelectorFromString("appendEvent:")

    private static func imp<T>(_ sel: Selector, as: T.Type) -> T? {
        guard let cls = hidClass, let m = class_getInstanceMethod(cls, sel) else { return nil }
        return unsafeBitCast(method_getImplementation(m), to: T.self)
    }

    private static let initImp = imp(selInit, as: InitFn.self)
    private static let optionsImp = imp(selOptions, as: OptionsFn.self)
    private static let intImp = imp(selInt, as: IntFn.self)
    private static let doubleImp = imp(selDouble, as: DoubleFn.self)
    private static let appendImp = imp(selAppend, as: AppendFn.self)

    private static let setHIDEvent: SetHIDEventFn? = {
        guard let h = skyLight, let p = dlsym(h, "SLEventSetIOHIDEvent") else { return nil }
        return unsafeBitCast(p, to: SetHIDEventFn.self)
    }()
    private static let setEventType: SetTypeFn? = {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGEventSetType") else { return nil }
        return unsafeBitCast(p, to: SetTypeFn.self)
    }()

    static let available: Bool = {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
            && initImp != nil && optionsImp != nil && intImp != nil && doubleImp != nil && appendImp != nil
            && setHIDEvent != nil && setEventType != nil
    }()

    /// Erzeugt ein HIDEvent-Objekt (alloc + init über die ObjC-Runtime).
    private static func makeHID(type: UInt32) -> AnyObject? {
        guard let cls = hidClass, let initImp = initImp,
              let raw = (cls as AnyObject).perform(NSSelectorFromString("alloc")) else { return nil }
        let obj = raw.takeRetainedValue()                 // +1 aus alloc
        _ = Unmanaged.passUnretained(obj).retain()            // init verbraucht self
        return initImp(obj, selInit, type, 0, 0)?.takeRetainedValue()
    }

    // MARK: Gesten-Zustand

    private static var generation = 0                      // verwirft nachgeschickte End-Events einer alten Geste
    private let axis: Axis
    private let sign: Double
    private let scaleH: Double
    private let scaleV: Double
    private var offset = 0.0
    private var lastDelta = 0.0

    init(axis: Axis, invert: Bool) {
        self.axis = axis
        self.sign = invert ? -1 : 1
        let screen = DockSwipe.screenUnderCursor()
        let spaces = DockSwipe.spaceCount(on: screen)
        let offsetForOneSpace = spaces <= 1 ? 2.0 : 1.0 + 1.0 / Double(spaces - 1)
        scaleH = offsetForOneSpace / (Double(screen.frame.width) + DockSwipe.spaceSeparatorWidth)
        scaleV = 1.0 / Double(screen.frame.height)
    }

    /// Maus nach rechts → positiv, Maus nach oben → positiv (bei "gestureInvert" umgekehrt).
    private func delta(dx: Double, dy: Double) -> Double {
        sign * (axis == .horizontal ? dx * scaleH : -dy * scaleV)
    }

    func begin(dx: Double, dy: Double) {
        DockSwipe.generation += 1
        offset = delta(dx: dx, dy: dy)
        lastDelta = offset
        post(.began, progress: offset)
    }

    func change(dx: Double, dy: Double) {
        let d = delta(dx: dx, dy: dy)
        if d == 0 { return }
        offset += d
        lastDelta = d
        post(.changed, progress: offset)
    }

    /// Loslassen. Kehrt die letzte Bewegung die Richtung um, wird abgebrochen (wie am Trackpad).
    func end(cancel: Bool = false) {
        let reversed = (lastDelta < 0) != (offset < 0)
        let phase: Phase = (cancel || reversed) ? .cancelled : .ended
        guard let event = post(phase, progress: offset, exitSpeed: lastDelta * DockSwipe.exitSpeedFactor) else { return }
        // Das Dock ignoriert das erste End-Event, wenn es gerade ausgelastet ist → nach 0,2 s und 0,5 s nochmal senden
        let gen = DockSwipe.generation
        for delay in [0.2, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if DockSwipe.generation == gen { event.post(tap: .cgSessionEventTap) }
            }
        }
    }

    @discardableResult
    private func post(_ phase: Phase, progress: Double, exitSpeed: Double = 0) -> CGEvent? {
        guard let hid = DockSwipe.makeHID(type: DockSwipe.typeDockSwipe),
              let setOptions = DockSwipe.optionsImp, let setInt = DockSwipe.intImp, let setDouble = DockSwipe.doubleImp,
              let append = DockSwipe.appendImp, let setHID = DockSwipe.setHIDEvent, let setType = DockSwipe.setEventType,
              let event = CGEvent(source: nil) else { return nil }

        setOptions(hid, DockSwipe.selOptions, phase.rawValue << DockSwipe.phaseShift)
        setInt(hid, DockSwipe.selInt, axis.rawValue, DockSwipe.fieldMotion)
        setInt(hid, DockSwipe.selInt, DockSwipe.flavorDockPrimary, DockSwipe.fieldFlavor)
        setDouble(hid, DockSwipe.selDouble, progress, DockSwipe.fieldProgress)

        if phase == .ended || phase == .cancelled, let vel = DockSwipe.makeHID(type: DockSwipe.typeVelocity) {
            let base = DockSwipe.typeVelocity << 16
            setDouble(vel, DockSwipe.selDouble, exitSpeed, base | 0)   // X
            setDouble(vel, DockSwipe.selDouble, exitSpeed, base | 1)   // Y
            setDouble(vel, DockSwipe.selDouble, 0, base | 2)           // Z
            append(hid, DockSwipe.selAppend, vel)
        }

        let eventPtr = Unmanaged.passUnretained(event).toOpaque()
        setType(UnsafeRawPointer(eventPtr), 30)
        setHID(UnsafeRawPointer(eventPtr), UnsafeRawPointer(Unmanaged.passUnretained(hid).toOpaque()))
        event.post(tap: .cgSessionEventTap)
        return event
    }

    // MARK: Bildschirm und Desktops

    private static func screenUnderCursor() -> NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Anzahl der Desktops auf dem Bildschirm; bestimmt, wie weit "ein Desktop weiter" im Fortschritt ist.
    private static func spaceCount(on screen: NSScreen) -> Int {
        typealias ConnFn = @convention(c) () -> Int32
        typealias SpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
        guard let h = skyLight, let c = dlsym(h, "CGSMainConnectionID"), let f = dlsym(h, "CGSCopyManagedDisplaySpaces"),
              let spaces = unsafeBitCast(f, to: SpacesFn.self)(unsafeBitCast(c, to: ConnFn.self)())?.takeRetainedValue(),
              let entries = spaces as? [[String: Any]] else { return 2 }
        var uuid = ""
        if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
           let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
            uuid = CFUUIDCreateString(nil, u) as String
        }
        let entry = entries.first { ($0["Display Identifier"] as? String)?.caseInsensitiveCompare(uuid) == .orderedSame }
            ?? entries.first { ($0["Display Identifier"] as? String) == "Main" }
            ?? entries.first
        return (entry?["Spaces"] as? [Any])?.count ?? 2
    }
}
