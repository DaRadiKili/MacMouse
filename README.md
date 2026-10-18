# MacMouse

Kleine Menüleisten-App für macOS, mit der sich eine **Razer-Maus ohne Razer Synapse** einstellen lässt. Dazu kommen
frei belegbare Maustasten, Wischgesten mit der Maus und getrenntes Scrollen für Maus und Trackpad.

> **Status: Version 0.1.** Entwickelt und getestet mit einer **Razer Viper V3 Pro** (per Kabel) unter **macOS 27**.
> Andere Razer-Mäuse verwenden ähnliche Befehle, sind aber nicht getestet.

## Was MacMouse kann

- **DPI** einstellen (Regler, genauer Wert, eigene Stufen), optional mit **Auflösungs-Ausgleich**: Das Zeigertempo
  bleibt gleich, egal welche Auflösung oder welcher Monitor aktiv ist. Eigene DPI pro Bildschirm ist möglich.
- **Zeigergeschwindigkeit** fest halten, unabhängig vom Regler in den Systemeinstellungen.
- **Maustasten belegen**: Tastenkombinationen (auch mit „Hyper“ = ⌃⌥⇧⌘), Mission Control, App Exposé, Desktop wechseln,
  DPI-Stufe, Profil wechseln, App starten, Shell-Befehl. Zusätzlich **Doppelklick und Halten** pro Taste.
- **Gesten-Taste**: Taste halten und die Maus bewegen. Links/Rechts wechselt **fließend** den Desktop wie am Trackpad,
  Hoch/Runter öffnet Mission Control bzw. App Exposé.
- **Akku**: Stand, Restlaufzeit und Zeit bis voll (lernt aus deinem Akku-Verlauf), Warnungen bei einstellbaren
  Schwellen, Symbol in der Menüleiste wird orange bzw. rot.
- **Gerät**: Abfragerate, Ruhemodus, Abhebe-Distanz (Lift-off).
- **Scrollen**: Mausrad-Richtung getrennt vom Trackpad umkehren, glattes Scrollen.
- **Profile** (auch automatisch je nach vorderster App), **Sichern und Laden** aller Einstellungen.

## Bauen und installieren

Voraussetzung: macOS mit Xcode Command Line Tools (`swiftc`).

```bash
scripts/build.sh              # baut build/MacMouse.app (signiert mit einem lokalen Zertifikat)
build/MacMouse install        # kopiert die App nach ~/Applications und startet sie beim Login
```

Beim ersten Start fragt macOS nach zwei Berechtigungen für **MacMouse**, beide unter
*Systemeinstellungen → Datenschutz & Sicherheit*:

- **Bedienungshilfen** (Maustasten, Gesten, Scrollen)
- **Eingabeüberwachung** (Zugriff auf die Maus für DPI, Akku usw.)

Das lokale Signier-Zertifikat liegt in einem eigenen Schlüsselbund unter `~/.config/macmouse/`. Dank fester Signatur
bleiben die Berechtigungen nach einem Neubau erhalten.

## Bedienung

Menüleisten-Symbol → *Einstellungen …*, oder im Terminal `macmouse settings`. Die Einstellungen stehen in
`~/.config/macmouse/config.json`; `macmouse help` zeigt alle Befehle und Aktionen.

## Hinweise

- Fließende Wischgesten nutzen **undokumentierte macOS-Schnittstellen** (Dock-Swipe-Ereignisse) und gehen aktuell nur
  unter macOS 27. Sonst gilt der Sprung-Modus (Ctrl+Pfeil).
- Die Razer-Befehle (USB-HID Feature Reports) sind **inoffiziell** und stammen aus öffentlichen Reverse-Engineering-Quellen.
  Schreibende Befehle werden zurückgelesen und bei einer Abweichung zurückgesetzt. Nutzung auf eigene Gefahr.
- MacMouse steht in keiner Verbindung zu Razer oder Apple.

## Danksagung

Die Arbeit baut auf öffentlichen Recherchen auf: [OpenRazer](https://github.com/openrazer/openrazer) (Razer-Protokoll),
[fang](https://github.com/BrandonDoster/fang) (Lift-off-Befehle) und [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix)
(Erkenntnisse zu Dock-Swipe-Ereignissen). Der Code in diesem Repository ist eigenständig geschrieben.

## Lizenz

MIT, siehe [LICENSE](LICENSE).
