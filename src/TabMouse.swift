import SwiftUI

// MARK: - Tab "Maus": DPI und Gerät

final class MouseTabState: ObservableObject {
    @Published var draft: Int?          // Wert während des Ziehens am Regler
    @Published var exact = ""
    @Published var newPreset = ""
}

struct MouseTab: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var st = MouseTabState()

    private var shown: Int { st.draft ?? model.currentBase }

    var body: some View {
        Form {
            Section("DPI") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(shown)").font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("DPI").foregroundStyle(.secondary)
                        Spacer()
                        let hw = hardwareDPI(forBase: shown)
                        if hw != shown { Text("an der Maus: \(hw)").font(.footnote).foregroundStyle(.secondary) }
                    }
                    Slider(value: Binding(get: { positionFromDPI(shown) }, set: { st.draft = dpiFromPosition($0) }),
                           in: 0...1) { editing in
                        if !editing, let d = st.draft { model.setDPI(d); st.draft = nil }
                    }
                }
                LabeledContent("Genauer Wert") {
                    HStack(spacing: 8) {
                        TextField("", text: $st.exact, prompt: Text("z. B. 1200")).labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                            .onSubmit(applyExact)
                        Text("DPI").foregroundStyle(.secondary)
                        Button("Setzen", action: applyExact).disabled(Int(st.exact) == nil)
                    }
                }
                LabeledContent("Stufen") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .trailing, spacing: 8) {
                        ForEach(settings.presets, id: \.self) { p in
                            HStack(spacing: 2) {
                                Button("\(p)") { model.setDPI(p) }
                                    .buttonStyle(.bordered)
                                    .tint(p == model.currentBase ? .accentColor : nil)
                                Button { removePreset(p) } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.secondary)
                                    .help("Stufe \(p) entfernen")
                            }
                        }
                    }
                }
                LabeledContent("Neue Stufe") {
                    HStack(spacing: 8) {
                        TextField("", text: $st.newPreset, prompt: Text("z. B. 2400")).labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                            .onSubmit(addPreset)
                        Text("DPI").foregroundStyle(.secondary)
                        Button("Hinzufügen", action: addPreset).disabled(Int(st.newPreset) == nil)
                    }
                }
                Text("Die Tasten-Aktionen „DPI: nächste/vorherige Stufe“ schalten durch diese Liste.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Zeigertempo") {
                Toggle("Auflösungs-Ausgleich", isOn: Binding(get: { settings.dpiCompensation }, set: setCompensation))
                Text("Hält das Tempo des Zeigers auf dem Bildschirm gleich, wenn du die Auflösung in macOS änderst oder der Zeiger auf einen anderen Monitor wechselt. Der DPI-Wert oben gilt für den Bildschirm und die Auflösung, bei denen du das einschaltest.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Einblenden, wenn die DPI wechselt", isOn: Binding(get: { settings.showHUD }, set: { settings.write(["showHUD": $0]) }))
            }

            Section("Maus") {
                Picker("Abfragerate", selection: Binding(get: { model.polling ?? 0 }, set: { model.setPolling($0) })) {
                    if model.polling == nil { Text("–").tag(0) }
                    ForEach(Razer.pollingRates, id: \.self) { Text("\($0) Hz").tag($0) }
                }
                .disabled(model.polling == nil)
                Picker("Ruhemodus nach", selection: Binding(get: { model.idle ?? 0 }, set: { model.setIdle($0) })) {
                    if model.idle == nil { Text("–").tag(0) }
                    ForEach(idleOptions, id: \.self) { Text(idleLabel($0)).tag($0) }
                }
                .disabled(model.idle == nil)
                Picker("Abhebe-Distanz", selection: Binding(get: { liftChoice }, set: setLiftChoice)) {
                    if model.liftOff == nil { Text("–").tag(0) }
                    Text("Niedrig").tag(1)
                    Text("Mittel").tag(2)
                    Text("Hoch").tag(3)
                    Text("Eigene Werte").tag(4)
                }
                .disabled(model.liftOff == nil)
                if case .asymmetric(let lift, let land)? = model.liftOff {
                    LabeledContent("Abheben (Razer-Skala 2–26)") {
                        Stepper(value: Binding(get: { lift }, set: { model.setLiftOff(.asymmetric(lift: $0, land: min(land, $0 - 1))) }), in: 2...26) {
                            Text("\(lift)").monospacedDigit()
                        }
                    }
                    LabeledContent("Aufsetzen (Razer-Skala 1–25)") {
                        Stepper(value: Binding(get: { land }, set: { model.setLiftOff(.asymmetric(lift: lift, land: $0)) }), in: 1...max(1, lift - 1)) {
                            Text("\(land)").monospacedDigit()
                        }
                    }
                }
                Text("Je niedriger die Abhebe-Distanz, desto früher hört die Maus beim Hochheben auf zu tracken. Eigene Werte: Aufsetzen muss unter Abheben liegen.")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                    Button("Aktualisieren") { model.refreshDevice() }.disabled(model.busy)
                }
                if Razer.pollingRates.contains(where: { $0 > 1000 }) {
                    Text("Abfrageraten über 1000 Hz funktionieren nur mit dem HyperPolling-Funkempfänger.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

        }
        .formStyle(.grouped)
    }

    // MARK: Aktionen

    private var idleOptions: [Int] {
        var o = [60, 120, 300, 600, 900]
        if let i = model.idle, !o.contains(i) { o.append(i); o.sort() }
        return o
    }

    private var liftChoice: Int {
        switch model.liftOff {
        case .preset(let l)?: return l
        case .asymmetric?: return 4
        case nil: return 0
        }
    }

    private func setLiftChoice(_ v: Int) {
        switch v {
        case 1...3: model.setLiftOff(.preset(v))
        case 4: model.setLiftOff(.asymmetric(lift: 13, land: 12))   // Startwerte, danach per Schritte anpassen
        default: break
        }
    }

    private func idleLabel(_ s: Int) -> String { s % 60 == 0 ? "\(s / 60) Min." : "\(s) s" }

    private func applyExact() {
        guard let v = Int(st.exact) else { return }
        model.setDPI(max(100, min(35_000, v)))
        st.exact = ""
    }

    private func addPreset() {
        guard let v = Int(st.newPreset), (100...35_000).contains(v) else { return }
        settings.write(["dpiPresets": Array(Set(settings.presets + [v])).sorted()])
        st.newPreset = ""
    }

    private func removePreset(_ p: Int) { settings.write(["dpiPresets": settings.presets.filter { $0 != p }]) }

    /// Beim Einschalten wird die aktuelle Punktdichte zur Referenz: der Zeiger fühlt sich zunächst genau wie jetzt an.
    private func setCompensation(_ on: Bool) {
        var change: [String: Any] = ["dpiCompensation": on]
        if on {
            change["dpiReferenceDensity"] = Displays.density(Displays.activeID)
            if settings.dpi == nil { change["dpi"] = model.currentBase }
        }
        settings.write(change)
    }
}

// MARK: - Tab "Tasten"

struct ButtonsTab: View {
    @ObservedObject var model: SettingsModel

    private static let rows: [(button: Int, label: String)] = [
        (2, "Mausrad-Klick"), (3, "Obere Seitentaste"), (4, "Untere Seitentaste"),
    ]
    private static let kinds: [ActionKind] = [.passthrough] + ActionKind.common + [.gesture]

    var body: some View {
        Form {
            Section("Belegung") {
                ForEach(Self.rows, id: \.button) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent(row.label) {
                            ActionPicker(kinds: Self.kinds, spec: spec(for: row.button))
                        }
                        if settings.gestureButtons[row.button] == nil {
                            Collapsible(title: "Doppelklick und Halten") {
                                LabeledContent("Doppelklick") {
                                    ActionPicker(kinds: ActionKind.common, spec: extraSpec(row.button, "double"))
                                }
                                LabeledContent("Halten") {
                                    ActionPicker(kinds: ActionKind.common, spec: extraSpec(row.button, "hold"))
                                }
                            }
                        }
                    }
                }
            }
            Section {
                Text("„Normal“ lässt die Taste so, wie macOS sie kennt (die untere/obere Seitentaste ist dann Zurück/Vor). „Nichts“ schluckt den Klick. „Gesten-Taste“: Taste halten und die Maus bewegen, Einstellungen dazu im Tab Gesten. Mit Doppelklick oder Halten löst der normale Klick erst beim Loslassen aus.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Linke und rechte Maustaste lassen sich nicht umbelegen. Die DPI-Taste auf der Oberseite wird von der Maus selbst gesteuert.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func extraSpec(_ n: Int, _ key: String) -> Binding<String> {
        Binding(
            get: { settings.buttonExtras[n]?[key] ?? "none" },
            set: { v in
                var all = Dictionary(uniqueKeysWithValues: settings.buttonExtras.map { (String($0.key), $0.value) })
                var map = all[String(n)] ?? [:]
                map[key] = v
                all[String(n)] = map
                settings.write(["buttonsExtra": all])
            })
    }

    private func spec(for n: Int) -> Binding<String> {
        Binding(
            get: {
                if settings.gestureButtons[n] != nil { return ActionSpec.gestureMarker }
                return settings.buttons[n] ?? "passthrough"
            },
            set: { v in
                var buttons = Dictionary(uniqueKeysWithValues: settings.buttons.map { (String($0.key), $0.value) })
                var gestureButtons = Dictionary(uniqueKeysWithValues: settings.gestureButtons.map { (String($0.key), $0.value) })
                if v == ActionSpec.gestureMarker {
                    if gestureButtons[String(n)] == nil {
                        gestureButtons[String(n)] = ["up": "mission", "down": "appexpose", "left": "desktopright",
                                                     "right": "desktopleft", "click": "passthrough"]
                    }
                    buttons[String(n)] = "none"
                } else {
                    gestureButtons[String(n)] = nil
                    buttons[String(n)] = v
                }
                settings.write(["buttons": buttons, "gestureButtons": gestureButtons])
            })
    }
}
