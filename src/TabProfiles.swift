import SwiftUI

// MARK: - Tab "Profile"

final class ProfilesTabState: ObservableObject {
    @Published var newName = ""
}

/// Anzeigename einer App zu ihrer Bundle-ID (Fallback: die ID selbst).
func appDisplayName(_ bundleID: String) -> String {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
    return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
}

struct ProfilesTab: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var st = ProfilesTabState()

    var body: some View {
        Form {
            if !Profiles.enabled {
                Section("Profile") {
                    Text("Mit Profilen speicherst du Einstellungen (DPI, Tastenbelegung, Gesten, Scrollen) als Paket und wechselst per Menü, Taste oder automatisch je nach vorderster App, z. B. ein Profil für die Arbeit und eines für Spiele.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("Profile einschalten (aktuelle Einstellungen werden „Standard“)") { Profiles.enable() }
                    }
                }
            } else {
                profilesSection
                appsSection
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Profile

    private var profilesSection: some View {
        Section("Profile") {
            ForEach(Profiles.names, id: \.self) { name in
                HStack(spacing: 10) {
                    Button { Profiles.activate(name, announce: true) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: name == settings.activeProfile ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(name == settings.activeProfile ? Color.accentColor : Color.secondary)
                            Text(name)
                            if name == settings.defaultProfile {
                                Text("Standard").font(.caption).foregroundStyle(.secondary)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button("Umbenennen") { promptRename(name) }
                    Button("Löschen") { Profiles.delete(name) }.disabled(name == settings.defaultProfile)
                }
            }
            LabeledContent("Neues Profil") {
                HStack(spacing: 8) {
                    TextField("", text: $st.newName, prompt: Text("Name, z. B. Spiele")).labelsHidden()
                        .textFieldStyle(.roundedBorder).frame(width: 170).onSubmit(addProfile)
                    Button("Anlegen", action: addProfile)
                }
            }
            Picker("Standardprofil", selection: Binding(get: { settings.defaultProfile ?? "" },
                                                        set: { settings.write(["defaultProfile": $0]) })) {
                ForEach(Profiles.names, id: \.self) { Text($0).tag($0) }
            }
            Text("Ein neues Profil startet mit deinen aktuellen Einstellungen. Alles, was du danach änderst, gehört zum aktiven Profil. Das Standardprofil gilt für alle Apps ohne eigenes Profil. Nicht im Profil: DPI-Stufen, Auflösungs-Ausgleich, Akku-Warnungen und Ruhemodus.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Pro App

    private var appsSection: some View {
        Section("Profil pro App") {
            ForEach(settings.appProfiles.keys.sorted(), id: \.self) { id in
                LabeledContent {
                    HStack(spacing: 8) {
                        Picker("", selection: Binding(get: { settings.appProfiles[id] ?? "" }, set: { setApp(id, $0) })) {
                            ForEach(Profiles.names, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().frame(width: 160)
                        Button { removeApp(id) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("Zuordnung entfernen")
                    }
                } label: {
                    Text(appDisplayName(id))
                }
            }
            Menu("App hinzufügen …") {
                ForEach(runningApps(), id: \.bundleIdentifier) { app in
                    Button(app.localizedName ?? app.bundleIdentifier ?? "?") { setApp(app.bundleIdentifier ?? "", settings.defaultProfile ?? "") }
                }
                Divider()
                Button("Andere App wählen …", action: chooseApp)
            }
            Text("Kommt eine dieser Apps nach vorn, wechselt MacMouse automatisch zum Profil. Für alle anderen Apps gilt das Standardprofil.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier && settings.appProfiles[$0.bundleIdentifier!] == nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    // MARK: Aktionen

    private func addProfile() {
        Profiles.create(st.newName.isEmpty ? "Profil" : st.newName)
        st.newName = ""
    }

    private func setApp(_ id: String, _ profile: String) {
        guard !id.isEmpty else { return }
        var m = settings.appProfiles
        m[id] = profile
        settings.write(["appProfiles": m])
        Profiles.frontAppChanged(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    private func removeApp(_ id: String) {
        var m = settings.appProfiles
        m[id] = nil
        settings.write(["appProfiles": m])
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier {
            setApp(id, settings.defaultProfile ?? "")
        }
    }

    private func promptRename(_ old: String) {
        let alert = NSAlert()
        alert.messageText = "Profil umbenennen"
        alert.addButton(withTitle: "Umbenennen")
        alert.addButton(withTitle: "Abbrechen")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = old
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn { Profiles.rename(old, to: field.stringValue) }
    }
}
