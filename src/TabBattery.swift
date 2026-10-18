import SwiftUI

// MARK: - Tab "Akku": Stand, Laufzeit-Schätzung und Warnungen

struct BatteryTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Akku") {
                LabeledContent("Akku") {
                    if let b = model.battery {
                        HStack(spacing: 10) {
                            ProgressView(value: Double(b.percent), total: 100).tint(.green).frame(width: 160)
                            Text(batterySummary(b, model.estimate)).monospacedDigit()
                        }
                    } else {
                        Text(model.deviceError ?? "nicht lesbar").foregroundStyle(.secondary)
                    }
                }
                if let e = model.estimate {
                    LabeledContent(e.charging ? "Danach hält sie" : "Volle Ladung hält", value: e.runtimeValue)
                    Collapsible(title: "Laufzeit je Abfragerate") {
                        ForEach(e.perRate, id: \.hz) { r in
                            LabeledContent("\(r.hz) Hz", value: "ca. \(formatDuration(r.runtime))" + (r.measured ? " · gemessen" : " · geschätzt"))
                        }
                    }
                    Text("Quelle: \(e.sourceNote). Die Schätzung startet mit den Razer-Angaben je Abfragerate und lernt aus dem Akku-Verlauf, den \(appName) alle 3 Minuten mitschreibt. Beim Laden braucht sie etwa 10 Minuten, bis die Ladezeit berechnet werden kann.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                    Button("Aktualisieren") { model.refreshDevice() }.disabled(model.busy)
                }
            }

            Section("Akku-Warnungen") {
                Toggle("Warnung einblenden", isOn: Binding(get: { settings.batteryAlerts }, set: { settings.write(["batteryAlerts": $0]) }))
                LabeledContent("Erste Warnung bei (orange)") {
                    Stepper(value: Binding(get: { settings.batteryLow }, set: { setLow($0) }), in: 5...60) {
                        Text("\(settings.batteryLow) %").monospacedDigit()
                    }
                }
                LabeledContent("Zweite Warnung bei (rot)") {
                    Stepper(value: Binding(get: { settings.batteryCritical }, set: { settings.write(["batteryCritical": $0]) }),
                            in: 1...max(1, settings.batteryLow - 1)) {
                        Text("\(settings.batteryCritical) %").monospacedDigit()
                    }
                }
                Toggle("Symbol in der Menüleiste einfärben", isOn: Binding(get: { settings.batteryIconColors }, set: { settings.write(["batteryIconColors": $0]) }))
                Toggle("Melden, wenn der Akku voll ist", isOn: Binding(get: { settings.batteryFullAlert }, set: { settings.write(["batteryFullAlert": $0]) }))
                HStack {
                    Spacer()
                    Button("Vorschau erste Warnung") { BatteryAlerts.preview(critical: false) }
                    Button("Vorschau zweite Warnung") { BatteryAlerts.preview(critical: true) }
                }
                Text("Die Warnung zeigt, wie lange der Akku noch hält. Das Symbol wird nur beim Entladen orange bzw. rot, nicht beim Laden.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func setLow(_ v: Int) {
        // Die zweite Schwelle muss immer unter der ersten liegen
        settings.write(["batteryLow": v, "batteryCritical": min(settings.batteryCritical, v - 1)])
    }

}
