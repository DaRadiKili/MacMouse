import Cocoa

/// Sorgt dafür, dass MacMouse nur einmal läuft, auch wenn macOS es beim Anmelden auf zwei Wegen startet
/// (Autostart-Job und "Fenster wieder öffnen"/Anmeldeobjekt). Die Sperrdatei wird beim Beenden automatisch frei.
enum SingleInstance {
    private static var fd: Int32 = -1

    /// true = wir sind die einzige Instanz.
    static func acquire() -> Bool {
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        fd = open(configDir + "/instance.lock", O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return true }   // Sperrdatei nicht anlegbar: lieber trotzdem starten
        return flock(fd, LOCK_EX | LOCK_NB) == 0
    }
}

/// Ein erneutes Öffnen der App (Doppelklick im Programme-Ordner, `open -a MacMouse`) zeigt die Einstellungen.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.shared.show()
        return true
    }
}

var appDelegate: AppDelegate?
