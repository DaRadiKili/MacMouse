import Cocoa
import UniformTypeIdentifiers

/// Einstellungen als Datei sichern und wieder einlesen (z. B. für einen anderen Mac).
enum ConfigTransfer {
    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    static func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MacMouse-Einstellungen.json"
        panel.allowedContentTypes = [.json]
        panel.message = "Alle Einstellungen inklusive Profilen als Datei sichern."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: configPath), to: url)
        } catch {
            alert("Sichern fehlgeschlagen", error.localizedDescription)
        }
    }

    static func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Eine mit MacMouse gesicherte Einstellungsdatei wählen."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            alert("Datei nicht lesbar", "Das ist keine gültige Einstellungsdatei (JSON).")
            return
        }
        // Die bisherigen Einstellungen als Sicherung neben die Config legen
        let backup = configPath + ".vor-import"
        try? FileManager.default.removeItem(atPath: backup)
        try? FileManager.default.copyItem(atPath: configPath, toPath: backup)
        guard let clean = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return }
        do {
            try clean.write(to: URL(fileURLWithPath: configPath), options: .atomic)
            settings.reloadIfChanged()
            alert("Einstellungen übernommen", "Die bisherigen Einstellungen liegen als „config.json.vor-import“ neben der Config.")
        } catch {
            alert("Übernehmen fehlgeschlagen", error.localizedDescription)
        }
    }
}
