// MacMouse – Razer-DPI, Maustasten-Belegung und Trackpad-Gesten für macOS
//
// Bauen: scripts/build.sh      Hilfe: macmouse help

import Cocoa
import IOKit.hid

setvbuf(stdout, nil, _IOLBF, 0)
migrateLegacyConfig()

func printHelp() {
    print("""
    MacMouse – Razer-DPI, Maustasten und Trackpad-Gesten

    Befehle:
      macmouse run            Hintergrunddienst mit Menüleisten-Symbol starten
      macmouse dpi            aktuelle DPI der Maus anzeigen
      macmouse dpi 1600       DPI setzen (100–35000)
      macmouse settings       Einstellungsfenster des laufenden Dienstes öffnen
      macmouse probe          Abhebe-Distanz der Maus auslesen (ins Log)
      macmouse test-alert     beide Akku-Warnungen und die Symbolfarben zur Probe zeigen
      macmouse status         Berechtigungen, Config und Maus prüfen
      macmouse init           Standard-Config anlegen
      macmouse install        als App nach ~/Applications kopieren und beim Login starten
      macmouse uninstall      Autostart wieder entfernen

    Config: \(configPath)  (wird bei Änderung automatisch neu geladen)

    Tasten: 2 = Mitte, 3 = oben an der Seite, 4 = unten an der Seite (Viper V3 Pro), 5+ = weitere
    Trackpad-Gesten: swipeLeft/Right/Up/Down, pinchIn/pinchOut, rotateLeft/rotateRight

    Gesten-Taste ("gestureButtons"): Taste halten und die Maus bewegen.
      gestureMode "smooth": der Wisch folgt der Maus wie am Trackpad (links/rechts = Desktop, hoch = Mission
                            Control, runter = App Exposé). "gestureInvert" dreht die Richtung um.
      gestureMode "jump":   bei "gestureThreshold" Bewegung wird die Aktion von up/down/left/right ausgelöst.
      "gestureVertical": "jump" löst hoch/runter nur einmal aus (up/down-Aktion), "smooth" folgt der Maus.
      "click" gilt, wenn nicht bewegt wurde. "debug": true schreibt gedrückte Tasten ins Log.

    Auflösungs-Ausgleich ("dpiCompensation": true): die Maus-DPI wächst mit der Bildschirmbreite in Punkten
      (Referenz: "dpiReferenceWidth"), damit sich der Zeiger bei jeder macOS-Auflösung gleich anfühlt.

    Scrollen/Zeiger: "scrollInvertMouse", "smoothScroll" (+ "scrollSpeed", "scrollSmoothness"), "pointerAcceleration": "off".
    DPI je Bildschirm: "displayDPI": {"<Display-UUID>": 1200}. Geräte: "pollingRate" (Hz), "idleTimeout" (Sekunden).
    Alles davon lässt sich bequemer im Einstellungsfenster einstellen (Menüleiste → Einstellungen …).

    Obere Seitentaste: im Einstellungsfenster belegbar ("buttons": {"3": "key:cmd+shift+4"}); ohne Belegung passiert nichts.

    Aktionen:
      key:cmd+shift+4     Tastenkürzel (Modifier: cmd, shift, alt, ctrl, hyper = alle vier)
      key:cmd+left        Pfeile: left right up down; außerdem space, tab, esc, return, f1–f12 …
      mission | appexpose | desktopleft | desktopright    Kurzformen für Ctrl+Pfeil
      dpi:next | dpi:prev | dpi:3200                      DPI umschalten
      app:Safari          App starten
      shell:say hallo     Shell-Befehl
      none                Klick/Geste schlucken, nichts tun
      passthrough         unverändert durchlassen (Standard)
    """)
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : (Bundle.main.bundleIdentifier != nil ? "app" : "help") {
case "run":
    runDaemon()
case "app":
    launchFromFinder()
case "dpi":
    if args.count > 2, let v = Int(args[2]) {
        if Razer.setDPI(v) {
            if let d = Razer.getDPI() { log("DPI jetzt: \(d.x)") } else { log("DPI gesendet: \(v)") }
        } else { log("Fehler: \(Razer.lastError)"); exit(1) }
    } else if let d = Razer.getDPI() {
        log("DPI: \(d.x) × \(d.y)")
    } else { log("Fehler: \(Razer.lastError)"); exit(1) }
case "status":
    log("Bedienungshilfen: \(AXIsProcessTrusted() ? "erlaubt" : "NICHT erlaubt")")
    log("Eingabeüberwachung: \(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted ? "erlaubt" : "NICHT erlaubt")")
    settings.reloadIfChanged()
    log("Config: \(configPath)")
    log("Fließende Gesten: \(DockSwipe.available ? "verfügbar" : "nicht verfügbar")")
    if let d = Razer.getDPI() { log("Razer-Maus: DPI \(d.x) × \(d.y)") } else { log("Razer-Maus: \(Razer.lastError)") }
case "settings":
    DistributedNotificationCenter.default().postNotificationName(Notification.Name("de.macmouse.openSettings"), object: nil, userInfo: nil, deliverImmediately: true)
case "render":
    renderSettingsTabs(to: args.count > 2 ? args[2] : "render")
case "test-alert":
    DistributedNotificationCenter.default().postNotificationName(Notification.Name("de.macmouse.alertTest"), object: nil, userInfo: nil, deliverImmediately: true)
case "probe":
    DistributedNotificationCenter.default().postNotificationName(Notification.Name("de.macmouse.probe"), object: nil, userInfo: nil, deliverImmediately: true)
case "init":
    settings.ensureFile()
case "install":
    settings.ensureFile(); install()
case "uninstall":
    uninstall()
default:
    printHelp()
}
