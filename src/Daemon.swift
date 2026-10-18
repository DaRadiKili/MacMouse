import Cocoa
import IOKit.hid

// MARK: - Hintergrunddienst

var watcher: IOHIDManager?
var menuController: MenuController?

/// Reagiert auf geänderte Einstellungen (aus der Datei, dem Menü oder dem Einstellungsfenster).
func reactToConfig() {
    applyConfiguredDPI()
    applyDeviceSettings()
    Pointer.apply()
    Pointer.updateFixed()
}

/// Setzt die DPI neu, sobald die Maus (wieder) auftaucht – z. B. nach Standby oder Dongle-Wechsel.
func startDeviceWatcher() {
    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(mgr, Razer.matching)
    IOHIDManagerRegisterDeviceMatchingCallback(mgr, { _, _, _, _ in
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            applyConfiguredDPI(force: true)
            applyDeviceSettings(force: true)
        }
    }, nil)
    IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    watcher = mgr
}

func runDaemon(showSettings: Bool = false) {
    settings.observe { reactToConfig() }
    settings.reloadIfChanged()
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    if !AXIsProcessTrustedWithOptions(opts) {
        log("Bedienungshilfen-Berechtigung fehlt – bitte in den Systemeinstellungen erlauben, dann neu starten")
    }
    log("Fließende Gesten: \(DockSwipe.available ? "verfügbar" : "nicht verfügbar (Sprung-Modus)")")
    startButtonTap()
    startScrollTap()
    startGestures()
    startDeviceWatcher()
    Displays.onChange = {
        // Zeiger wechselt den Bildschirm → DPI passend zu dessen Profil/Auflösung setzen
        // Ohne Einblendung: beim Wechseln zwischen Bildschirmen soll nichts aufblitzen
        if settings.dpiCompensation || !settings.displayDPI.isEmpty { applyConfiguredDPI() }
    }
    Displays.start()
    // Profile: Änderungen ins aktive Profil zurückschreiben und je nach vorderster App wechseln
    settings.observe { DispatchQueue.main.async { Profiles.syncActive() } }
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                      object: nil, queue: .main) { n in
        let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        Profiles.frontAppChanged(app?.bundleIdentifier)
    }
    Profiles.frontAppChanged(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    if settings.debug { HIDSniffer.start() }
    BatteryTracker.shared.start()
    migrateCompensationReference()
    if settings.debug {
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
            let b = Razer.battery()
            log("Akku: " + (b.map { "\($0.percent) %" + ($0.charging ? " (lädt)" : "") } ?? "nicht lesbar: \(Razer.lastError)"))
            log("Abfragerate: " + (Razer.getPollingRate().map { "\($0) Hz" } ?? "nicht lesbar: \(Razer.lastError)"))
            log("Abschaltzeit: " + (Razer.getIdleTime().map { "\($0) s" } ?? "nicht lesbar: \(Razer.lastError)"))
        }
    }
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
        if let g = gesture, Date().timeIntervalSince(g.since) > 30 { resetGesture() }   // Sicherheitsnetz
        settings.reloadIfChanged()
        Pointer.reassert()
    }
    // Auflösung in macOS geändert → DPI mit dem Auflösungs-Ausgleich neu berechnen
    NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                           object: nil, queue: .main) { _ in
        guard settings.dpiCompensation else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { applyConfiguredDPI() }
    }
    NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                           object: nil, queue: .main) { _ in Pointer.restore() }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)     // nur Menüleiste, kein Dock-Symbol
    installMainMenu()
    // `macmouse probe`: liest die Abhebe-Distanz aus (nur lesend) und schreibt sie ins Log
    DistributedNotificationCenter.default().addObserver(forName: Notification.Name("de.macmouse.probe"),
                                                        object: nil, queue: .main) { _ in
        DispatchQueue.global().async {
            log("Abhebe-Distanz: " + (Razer.getLiftOff().map { "\($0)" } ?? "nicht lesbar (\(Razer.lastError))"))
        }
    }
    // `macmouse test-alert`: zeigt beide Akku-Warnungen samt Symbolfarbe zur Probe
    DistributedNotificationCenter.default().addObserver(forName: Notification.Name("de.macmouse.alertTest"),
                                                        object: nil, queue: .main) { _ in
        BatteryAlerts.preview(critical: false); menuController?.setIconColor(.systemOrange)
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
            BatteryAlerts.preview(critical: true); menuController?.setIconColor(.systemRed)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 14) { BatteryTracker.shared.sampleNow() }   // zurück zum echten Stand
    }
    // `macmouse settings` im Terminal öffnet das Einstellungsfenster im laufenden Dienst
    DistributedNotificationCenter.default().addObserver(forName: Notification.Name("de.macmouse.openSettings"),
                                                        object: nil, queue: .main) { _ in SettingsWindow.shared.show() }
    menuController = MenuController()
    log("\(appName) läuft – Strg+C zum Beenden")
    if showSettings { DispatchQueue.main.async { SettingsWindow.shared.show() } }
    app.run()
}

// MARK: - Installation als App mit Autostart

let agentLabel = "de.macmouse.agent"
let legacyAgentLabel = "de.maus.agent"      // frühere Version "maus"
let agentPlist = NSString(string: "~/Library/LaunchAgents/\(agentLabel).plist").expandingTildeInPath
let installedApp = NSString(string: "~/Applications/MacMouse.app").expandingTildeInPath
let installedExecutable = installedApp + "/Contents/MacOS/MacMouse"
let commandLineLink = NSString(string: "~/.local/bin/macmouse").expandingTildeInPath   // damit `macmouse …` im Terminal geht

func launchctl(_ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    p.arguments = args
    p.standardError = FileHandle.nullDevice
    try? p.run(); p.waitUntilExit()
    return p.terminationStatus
}

/// Entfernt die frühere Installation unter dem alten Namen "maus" (App, Autostart, Terminal-Befehl).
func removeLegacyInstall(domain: String) {
    let fm = FileManager.default
    _ = launchctl(["bootout", "\(domain)/\(legacyAgentLabel)"])
    try? fm.removeItem(atPath: NSString(string: "~/Library/LaunchAgents/\(legacyAgentLabel).plist").expandingTildeInPath)
    try? fm.removeItem(atPath: NSString(string: "~/Applications/maus.app").expandingTildeInPath)
    let oldLink = NSString(string: "~/.local/bin/maus").expandingTildeInPath
    if (try? fm.destinationOfSymbolicLink(atPath: oldLink)) != nil { try? fm.removeItem(atPath: oldLink) }
}

/// Kopiert MacMouse.app nach ~/Applications und startet es beim Login.
func install() {
    let fm = FileManager.default
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
    // Quelle: das Paket, in dem dieses Programm steckt, oder MacMouse.app neben dem Programm (build/)
    var source: String?
    if let r = exe.range(of: ".app/Contents/MacOS/") {
        source = String(exe[..<r.lowerBound]) + ".app"
    } else {
        let sibling = (exe as NSString).deletingLastPathComponent + "/MacMouse.app"
        if fm.fileExists(atPath: sibling) { source = sibling }
    }
    guard let src = source else {
        log("Kein MacMouse.app gefunden. Bitte scripts/build.sh ausführen und von build/ aus installieren.")
        return
    }
    let domain = "gui/\(getuid())"
    _ = launchctl(["bootout", "\(domain)/\(agentLabel)"])        // laufende Version stoppen, bevor sie ersetzt wird
    removeLegacyInstall(domain: domain)
    if src != installedApp {
        try? fm.createDirectory(atPath: (installedApp as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? fm.removeItem(atPath: installedApp)
        do { try fm.copyItem(atPath: src, toPath: installedApp) }
        catch { log("Kopieren nach \(installedApp) fehlgeschlagen: \(error)"); return }
    }
    try? fm.createDirectory(atPath: (commandLineLink as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try? fm.removeItem(atPath: commandLineLink)
    try? fm.createSymbolicLink(atPath: commandLineLink, withDestinationPath: installedExecutable)

    let logPath = NSString(string: "~/Library/Logs/MacMouse.log").expandingTildeInPath
    let plist: [String: Any] = [
        "Label": agentLabel,
        "ProgramArguments": [installedExecutable, "run"],
        "RunAtLoad": true,
        "KeepAlive": ["SuccessfulExit": false],   // nach "Beenden" im Menü bleibt es aus, nach einem Absturz startet es neu
        "StandardOutPath": logPath,
        "StandardErrorPath": logPath,
    ]
    (plist as NSDictionary).write(toFile: agentPlist, atomically: true)
    let rc = launchctl(["bootstrap", domain, agentPlist])
    log(rc == 0 ? "Autostart aktiv. App: \(installedApp)" : "launchctl bootstrap fehlgeschlagen (Code \(rc))")
    log("Erlaube MacMouse unter Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen UND Eingabeüberwachung.")
}

func uninstall() {
    _ = launchctl(["bootout", "gui/\(getuid())/\(agentLabel)"])
    try? FileManager.default.removeItem(atPath: agentPlist)
    try? FileManager.default.removeItem(atPath: installedApp)
    try? FileManager.default.removeItem(atPath: commandLineLink)
    log("Autostart und App entfernt (Config bleibt unter \(configPath))")
}

/// Start per Doppelklick/Launchpad: läuft der Dienst schon, öffnet das nur die Einstellungen.
func launchFromFinder() {
    let id = Bundle.main.bundleIdentifier ?? ""
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0.processIdentifier != getpid() }
    if others.isEmpty {
        runDaemon(showSettings: true)
    } else {
        DistributedNotificationCenter.default().postNotificationName(Notification.Name("de.macmouse.openSettings"), object: nil,
                                                                     userInfo: nil, deliverImmediately: true)
        exit(0)
    }
}
