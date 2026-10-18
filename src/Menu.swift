import Cocoa

/// Menüleisten-Symbol mit den wichtigsten Dingen: Akku, DPI-Stufen, Profil, Gesten-Modus.
/// Alles andere steckt im Einstellungsfenster.
final class MenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let header = NSMenuItem(title: "Razer-Maus", action: nil, keyEquivalent: "")
    private var currentBase: Int?       // eingestellte DPI (ohne Auflösungs-Ausgleich)

    override init() {
        super.init()
        if let button = statusItem.button {
            let img = NSImage(systemSymbolName: "computermouse", accessibilityDescription: appName)
            img?.isTemplate = true
            button.image = img
            if img == nil { button.title = "🖱" }
        }
        menu.delegate = self
        statusItem.menu = menu
        header.isEnabled = false
        rebuild()
    }

    /// Symbol einfärben (nil = normal, passt sich dem Hell-/Dunkelmodus an).
    func setIconColor(_ color: NSColor?) {
        guard let button = statusItem.button,
              let base = NSImage(systemSymbolName: "computermouse", accessibilityDescription: appName) else { return }
        if let color = color,
           let tinted = base.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color])) {
            tinted.isTemplate = false
            button.image = tinted
        } else {
            base.isTemplate = true
            button.image = base
        }
    }

    // MARK: Menüaufbau

    private func item(_ title: String, _ action: Selector, state: Bool = false, object: Any? = nil, tag: Int = 0) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        it.state = state ? .on : .off
        it.representedObject = object
        it.tag = tag
        return it
    }

    private func rebuild() {
        menu.removeAllItems()
        menu.addItem(header)
        menu.addItem(.separator())
        for p in settings.presets {
            menu.addItem(item("\(p) DPI", #selector(pickPreset(_:)), state: p == currentBase, tag: p))
        }
        if Profiles.enabled {
            menu.addItem(.separator())
            let sub = NSMenu()
            for name in Profiles.names {
                sub.addItem(item(name, #selector(pickProfile(_:)), state: name == settings.activeProfile, object: name))
            }
            let parent = NSMenuItem(title: "Profil: \(settings.activeProfile ?? "–")", action: nil, keyEquivalent: "")
            parent.submenu = sub
            menu.addItem(parent)
        }
        menu.addItem(.separator())

        let modeHeader = NSMenuItem(title: "Gesten-Taste", action: nil, keyEquivalent: "")
        modeHeader.isEnabled = false
        menu.addItem(modeHeader)
        for (mode, title) in [("smooth", "Fließend (wie Trackpad)"), ("jump", "Sprung (Ctrl+Pfeil)")] {
            let usable = mode != "smooth" || DockSwipe.available
            let it = item(usable ? title : title + " – nicht verfügbar", #selector(pickMode(_:)),
                          state: settings.gestureMode == mode, object: mode)
            it.isEnabled = usable
            menu.addItem(it)
        }
        menu.addItem(.separator())

        let prefs = item("Einstellungen …", #selector(openSettings))
        prefs.keyEquivalent = ","
        menu.addItem(prefs)
        let quit = item("Beenden", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    /// Eine Zeile: "Razer-Maus · Akku 48 % (ca. 8 Std.)".
    private func headerText(_ battery: BatteryInfo?, _ estimate: BatteryEstimate?) -> String {
        battery.map { "Razer-Maus · Akku " + batterySummary($0, estimate) } ?? "Razer-Maus"
    }

    // MARK: Delegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
        showCurrentDPI()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let hw = Razer.getDPI()?.x
            let battery = Razer.battery()
            let hz = Razer.getPollingRate() ?? Razer.knownPollingRate ?? settings.pollingRate ?? 1000
            var estimate: BatteryEstimate?
            if let b = battery { estimate = BatteryTracker.shared.process(b, hz: hz) }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.currentBase = hw.map { baseDPI(fromHardware: $0) }
                self.header.title = self.headerText(battery, estimate)
                self.showCurrentDPI()
            }
        }
    }

    private func showCurrentDPI() {
        guard let base = currentBase else { return }
        for it in menu.items where it.action == #selector(pickPreset(_:)) { it.state = it.tag == base ? .on : .off }
    }

    // MARK: Aktionen

    @objc private func pickPreset(_ it: NSMenuItem) { apply(it.tag) }

    private func apply(_ base: Int) {
        currentBase = base
        showCurrentDPI()
        DispatchQueue.global(qos: .userInitiated).async { applyDPI(base, persist: true) }
    }

    @objc private func pickProfile(_ it: NSMenuItem) {
        guard let name = it.representedObject as? String else { return }
        Profiles.activate(name, announce: true)
    }

    @objc private func pickMode(_ it: NSMenuItem) {
        guard let mode = it.representedObject as? String else { return }
        settings.write(["gestureMode": mode])
    }

    @objc func openSettings() { SettingsWindow.shared.show() }

    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - Hauptmenü (nicht sichtbar, aber nötig für ⌘C/⌘V in Textfeldern und ⌘W)

func installMainMenu() {
    let main = NSMenu()

    let appItem = NSMenuItem()
    main.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "\(appName) beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu

    let editItem = NSMenuItem()
    main.addItem(editItem)
    let edit = NSMenu(title: "Bearbeiten")
    edit.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = edit

    let windowItem = NSMenuItem()
    main.addItem(windowItem)
    let window = NSMenu(title: "Fenster")
    window.addItem(withTitle: "Schließen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    windowItem.submenu = window

    NSApp.mainMenu = main
}
