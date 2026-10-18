import SwiftUI
import IOKit.hid

// MARK: - Tab "Gesten"

struct GesturesTab: View {
    @ObservedObject var model: SettingsModel

    private static let directions: [(key: String, label: String)] = [
        ("up", "Hoch"), ("down", "Runter"), ("left", "Links"), ("right", "Rechts"), ("click", "Kurzer Klick (ohne Bewegung)"),
    ]
    private static let trackpad: [(key: String, label: String)] = [
        ("swipeLeft", "Wischen nach links"), ("swipeRight", "Wischen nach rechts"),
        ("swipeUp", "Wischen nach oben"), ("swipeDown", "Wischen nach unten"),
        ("pinchIn", "Zusammenziehen"), ("pinchOut", "Auseinanderziehen"),
        ("rotateLeft", "Drehen links"), ("rotateRight", "Drehen rechts"),
    ]

    private var button: Int? { settings.gestureButtons.keys.sorted().first }
    private var smooth: Bool { settings.gestureMode == "smooth" && DockSwipe.available }

    var body: some View {
        Form {
            if let b = button {
                gestureSections(b)
            } else {
                Section("Gesten-Taste") {
                    Text("Es ist keine Taste als Gesten-Taste festgelegt. Wähle im Tab „Tasten“ bei einer Taste „Gesten-Taste“.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Trackpad-Gesten") {
                ForEach(Self.trackpad, id: \.key) { g in
                    LabeledContent(g.label) { ActionPicker(kinds: ActionKind.common, spec: trackpadSpec(g.key)) }
                }
                Text("Greifen nur, wenn macOS die Geste nicht selbst verwendet (dann in den Trackpad-Einstellungen ausschalten).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func gestureSections(_ b: Int) -> some View {
        Section("Gesten-Taste: \(buttonName(b))") {
            Picker("Modus", selection: Binding(get: { settings.gestureMode }, set: { settings.write(["gestureMode": $0]) })) {
                Text("Fließend (wie Trackpad)").tag("smooth")
                Text("Sprung (eine Aktion pro Wisch)").tag("jump")
            }
            if !DockSwipe.available {
                Text("Fließende Gesten sind auf diesem macOS nicht verfügbar, es gilt der Sprung-Modus.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if smooth {
                Picker("Hoch/Runter", selection: Binding(get: { settings.gestureVertical }, set: { settings.write(["gestureVertical": $0]) })) {
                    Text("Einmal auslösen, egal wie weit").tag("jump")
                    Text("Folgt der Maus").tag("smooth")
                }
                Toggle("Richtung umkehren", isOn: Binding(get: { settings.gestureInvert }, set: { settings.write(["gestureInvert": $0]) }))
            }
            slider("Start-Empfindlichkeit", value: Binding(get: { settings.gestureLock }, set: { settings.write(["gestureLock": $0]) }),
                   range: 4...40, unit: "px")
            slider("Auslöse-Distanz", value: Binding(get: { settings.gestureThreshold }, set: { settings.write(["gestureThreshold": $0]) }),
                   range: 30...200, unit: "px")
            Text("Start-Empfindlichkeit: wie weit die Maus bewegt werden muss, bis die Richtung feststeht. Auslöse-Distanz: ab wann eine Sprung-Aktion ausgelöst wird.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        Section("Aktionen der Gesten-Taste") {
            ForEach(Self.directions, id: \.key) { d in
                let note = inactiveNote(d.key)
                LabeledContent {
                    ActionPicker(kinds: d.key == "click" ? [.passthrough] + ActionKind.common : ActionKind.common,
                                 spec: directionSpec(b, d.key))
                        .disabled(note != nil)
                        .opacity(note == nil ? 1 : 0.45)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.label)
                        if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }

    /// Im fließenden Modus sind Links/Rechts (und je nach Einstellung Hoch/Runter) fest belegt.
    private func inactiveNote(_ key: String) -> String? {
        guard smooth else { return nil }
        if key == "left" || key == "right" { return "fest: fließender Desktop-Wechsel" }
        if (key == "up" || key == "down") && settings.gestureVertical == "smooth" { return "fest: folgt der Maus (Mission Control / App Exposé)" }
        return nil
    }

    private func buttonName(_ n: Int) -> String {
        switch n {
        case 2: return "Mausrad-Klick"
        case 3: return "Obere Seitentaste"
        case 4: return "Untere Seitentaste"
        default: return "Taste \(n)"
        }
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        LabeledContent(label) {
            HStack {
                Slider(value: value, in: range).frame(width: 190)
                Text("\(Int(value.wrappedValue)) \(unit)").monospacedDigit().frame(width: 52, alignment: .trailing)
            }
        }
    }

    private func directionSpec(_ b: Int, _ key: String) -> Binding<String> {
        Binding(
            get: { settings.gestureButtons[b]?[key] ?? (key == "click" ? "passthrough" : "none") },
            set: { v in
                var all = Dictionary(uniqueKeysWithValues: settings.gestureButtons.map { (String($0.key), $0.value) })
                var map = all[String(b)] ?? [:]
                map[key] = v
                all[String(b)] = map
                settings.write(["gestureButtons": all])
            })
    }

    private func trackpadSpec(_ key: String) -> Binding<String> {
        Binding(
            get: { settings.gestures[key] ?? "none" },
            set: { v in
                var g = settings.gestures
                g[key] = v
                settings.write(["gestures": g])
            })
    }
}

// MARK: - Tab "Scrollen"

struct ScrollTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Mausrad") {
                Toggle("Richtung umkehren (nur Maus, Trackpad bleibt)",
                       isOn: Binding(get: { settings.scrollInvertMouse }, set: { settings.write(["scrollInvertMouse": $0]) }))
                Toggle("Glattes Scrollen", isOn: Binding(get: { settings.smoothScroll }, set: { settings.write(["smoothScroll": $0]) }))
                if settings.smoothScroll {
                    LabeledContent("Tempo") {
                        HStack {
                            Slider(value: Binding(get: { settings.scrollSpeed }, set: { settings.write(["scrollSpeed": $0]) }), in: 0.5...3)
                                .frame(width: 190)
                            Text(String(format: "%.1f×", settings.scrollSpeed)).monospacedDigit().frame(width: 52, alignment: .trailing)
                        }
                    }
                    LabeledContent("Weichheit") {
                        HStack {
                            Slider(value: Binding(get: { settings.scrollSmoothness }, set: { settings.write(["scrollSmoothness": $0]) }), in: 0...1)
                                .frame(width: 190)
                            Text("\(Int(settings.scrollSmoothness * 100)) %").monospacedDigit().frame(width: 52, alignment: .trailing)
                        }
                    }
                }
                Text("Trackpad und Magic Mouse bleiben unverändert. Mit ⌘, ⌃ oder ⌥ gedrückt wird nicht geglättet.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Zeiger") {
                Toggle("Mausgeschwindigkeit aus den Systemeinstellungen ignorieren",
                       isOn: Binding(get: { settings.pointerAcceleration == "fixed" },
                                     set: { settings.write(["pointerAcceleration": $0 ? "fixed" : "system"]) }))
                if settings.pointerAcceleration == "fixed" {
                    LabeledContent("Zeigergeschwindigkeit") {
                        HStack {
                            Slider(value: Binding(get: { settings.pointerSpeed ?? 1.0 },
                                                  set: { settings.write(["pointerSpeed": (($0 * 20).rounded() / 20)]) }), in: 0.1...3.0)
                                .frame(width: 190)
                            Text(String(format: "%.2f", settings.pointerSpeed ?? 1.0)).monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                Text("Mit dieser Option hat der Regler „Zeigergeschwindigkeit“ in den Systemeinstellungen keine Wirkung mehr. Es gilt der feste Wert hier, anfangs genau deine bisherige Einstellung. Gilt für Mäuse, nicht fürs Trackpad. Beim Beenden von \(appName) gilt wieder die Systemeinstellung.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tab "Bildschirme"

struct DisplaysTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Bildschirme") {
                ForEach(model.displays) { d in DisplayRow(model: model, display: d) }
                Text("Eine eigene DPI gilt, sobald der Zeiger auf diesem Bildschirm ist. Ohne eigene DPI gilt die allgemeine DPI (bei eingeschaltetem Auflösungs-Ausgleich zusätzlich nach Punktdichte angepasst).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.displays = Displays.all() }
    }
}

struct DisplayRow: View {
    @ObservedObject var model: SettingsModel
    let display: DisplayInfo

    private var own: Int? { settings.displayDPI[display.uuid] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(display.name).fontWeight(.semibold)
                    Text("\(display.width)×\(display.height) Punkte · \(String(format: "%.2f", Displays.density(display.id))) Punkte/mm")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if display.id == Displays.activeID {
                    Text("Zeiger ist hier").font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                }
            }
            Toggle("Eigene DPI für diesen Bildschirm", isOn: Binding(
                get: { own != nil },
                set: { on in
                    var m = settings.displayDPI
                    m[display.uuid] = on ? (settings.dpi ?? model.currentBase) : nil
                    settings.write(["displayDPI": m])
                }))
            if let v = own {
                HStack {
                    Stepper(value: Binding(get: { v }, set: { set($0) }), in: 100...35_000, step: 50) {
                        TextField("", value: Binding(get: { v }, set: { set($0) }), format: .number, prompt: Text("DPI")).labelsHidden()
                            .textFieldStyle(.roundedBorder).frame(width: 100).multilineTextAlignment(.trailing)
                    }
                    Text("DPI").foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func set(_ v: Int) {
        var m = settings.displayDPI
        m[display.uuid] = max(100, min(35_000, v))
        settings.write(["displayDPI": m])
    }
}

// MARK: - Tab "Info"

struct InfoTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Berechtigungen") {
                status("Bedienungshilfen", AXIsProcessTrusted())
                status("Eingabeüberwachung", IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted)
                HStack {
                    Button("Bedienungshilfen öffnen") { openPrivacy("Privacy_Accessibility") }
                    Button("Eingabeüberwachung öffnen") { openPrivacy("Privacy_ListenEvent") }
                    Spacer()
                    Button("Neu prüfen") { model.rev += 1 }
                }
            }
            Section("System") {
                LabeledContent("Version", value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "Entwicklung")
                LabeledContent("Fließende Gesten", value: DockSwipe.available ? "verfügbar" : "nicht verfügbar")
                LabeledContent("Config-Datei", value: (configPath as NSString).abbreviatingWithTildeInPath)
                HStack {
                    Button("Einstellungen sichern …") { ConfigTransfer.export() }
                    Button("Einstellungen laden …") { ConfigTransfer.importFile() }
                }
                HStack {
                    Button("Config öffnen") { NSWorkspace.shared.open(URL(fileURLWithPath: configPath)) }
                    Button("Log öffnen") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: NSString(string: "~/Library/Logs/MacMouse.log").expandingTildeInPath))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func status(_ name: String, _ ok: Bool) -> some View {
        LabeledContent(name) {
            Label(ok ? "erlaubt" : "nicht erlaubt", systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
        }
    }

    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
}
