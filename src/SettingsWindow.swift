import SwiftUI
import UniformTypeIdentifiers

// MARK: - Zustand für das Einstellungsfenster

final class SettingsModel: ObservableObject {
    static let shared = SettingsModel()

    @Published var rev = 0                       // zählt hoch, wenn sich die Config ändert → Ansicht neu zeichnen
    @Published var battery: BatteryInfo?
    @Published var estimate: BatteryEstimate?
    @Published var polling: Int?
    @Published var idle: Int?
    @Published var liftOff: LiftOff?
    @Published var deviceDPI: Int?             // was gerade an der Maus steht
    @Published var deviceError: String?
    @Published var busy = false
    @Published var displays: [DisplayInfo] = []

    private init() {
        settings.observe { [weak self] in DispatchQueue.main.async { self?.rev += 1 } }
    }

    /// Eingestellte DPI (ohne Auflösungs-Ausgleich), soweit bekannt.
    var currentBase: Int {
        deviceDPI.map(baseDPI(fromHardware:)) ?? desiredBaseDPI() ?? 1600
    }

    /// Liest Akku, Abfragerate, Abschaltzeit und DPI von der Maus.
    func refreshDevice() {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let dpi = Razer.getDPI()?.x
            let battery = Razer.battery()
            let polling = Razer.getPollingRate()
            let idle = Razer.getIdleTime()
            let liftOff = Razer.getLiftOff()
            let error = (dpi == nil && battery == nil) ? Razer.lastError : nil
            var estimate: BatteryEstimate?
            if let b = battery { estimate = BatteryTracker.shared.process(b, hz: polling ?? Razer.knownPollingRate ?? 1000) }
            DispatchQueue.main.async {
                self.estimate = estimate
                self.deviceDPI = dpi; self.battery = battery; self.polling = polling; self.idle = idle; self.liftOff = liftOff
                self.deviceError = error; self.busy = false
            }
        }
    }

    func setDPI(_ base: Int) {
        deviceDPI = hardwareDPI(forBase: base)
        DispatchQueue.global(qos: .userInitiated).async { applyDPI(base, persist: true) }
    }

    func setPolling(_ hz: Int) {
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = Razer.setPollingRate(hz)
            DispatchQueue.main.async {
                if ok { self.polling = hz; settings.write(["pollingRate": hz]) }
                else { self.deviceError = "Abfragerate nicht gesetzt: \(Razer.lastError)" }
            }
        }
    }

    func setLiftOff(_ lo: LiftOff) {
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = Razer.setLiftOff(lo)
            DispatchQueue.main.async {
                if ok {
                    self.liftOff = lo
                    switch lo {
                    case .preset(let l): settings.write(["liftOff": ["mode": "preset", "level": l]])
                    case .asymmetric(let lift, let land): settings.write(["liftOff": ["mode": "asymmetric", "lift": lift, "land": land]])
                    }
                } else {
                    self.deviceError = "Abhebe-Distanz nicht gesetzt: \(Razer.lastError)"
                }
            }
        }
    }

    func setIdle(_ seconds: Int) {
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = Razer.setIdleTime(seconds)
            DispatchQueue.main.async {
                if ok { self.idle = seconds; settings.write(["idleTimeout": seconds]) }
                else { self.deviceError = "Abschaltzeit nicht gesetzt: \(Razer.lastError)" }
            }
        }
    }
}

// MARK: - Fenster

final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        let model = SettingsModel.shared
        if window == nil {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 660),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            win.title = "\(appName) – Einstellungen"
            win.isReleasedWhenClosed = false
            win.minSize = NSSize(width: 820, height: 560)
            win.contentView = NSHostingView(rootView: SettingsRoot(model: model))
            win.center()
            window = win
        }
        model.displays = Displays.all()
        model.refreshDevice()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case mouse, battery, buttons, gestures, profiles, scroll, displays, info

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mouse: return "Maus"
        case .battery: return "Akku"
        case .buttons: return "Tasten"
        case .gestures: return "Gesten"
        case .profiles: return "Profile"
        case .scroll: return "Scrollen"
        case .displays: return "Bildschirme"
        case .info: return "Info"
        }
    }

    var icon: String {
        switch self {
        case .mouse: return "computermouse"
        case .battery: return "battery.75percent"
        case .buttons: return "circle.grid.2x2"
        case .gestures: return "hand.draw"
        case .profiles: return "person.2"
        case .scroll: return "scroll"
        case .displays: return "display"
        case .info: return "info.circle"
        }
    }
}

final class NavState: ObservableObject {
    @Published var page: SettingsPage? = .mouse
}

/// Links die Seitenleiste mit Symbolen, rechts die gewählte Seite.
struct SettingsRoot: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var nav = NavState()

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsPage.allCases, selection: $nav.page) { page in
                Label(page.title, systemImage: page.icon).tag(page as SettingsPage?)
            }
            .listStyle(.sidebar)
            .frame(width: 190)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch nav.page ?? .mouse {
        case .mouse: MouseTab(model: model)
        case .battery: BatteryTab(model: model)
        case .buttons: ButtonsTab(model: model)
        case .gestures: GesturesTab(model: model)
        case .profiles: ProfilesTab(model: model)
        case .scroll: ScrollTab(model: model)
        case .displays: DisplaysTab(model: model)
        case .info: InfoTab(model: model)
        }
    }
}

// MARK: - Aufklappbare Zeile (die ganze Zeile ist klickbar, nicht nur der Pfeil)

final class ExpandState: ObservableObject {
    @Published var open = false
}

struct Collapsible<Content: View>: View {
    let title: String
    @StateObject private var state = ExpandState()
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { state.open.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: state.open ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold)).frame(width: 12)
                    Text(title)
                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if state.open { content() }
        }
    }
}

// MARK: - Aktionsauswahl (für Tasten, Gesten-Richtungen und Trackpad-Gesten)

/// Lokaler Zustand eines ActionPicker (statt @State, das ein Makro-Plugin braucht, das ohne Xcode fehlt).
final class ActionPickerState: ObservableObject {
    @Published var kind: ActionKind = .none
    @Published var arg = ""
}

struct ActionPicker: View {
    let kinds: [ActionKind]
    @Binding var spec: String
    @StateObject private var st = ActionPickerState()
    private var kind: ActionKind { st.kind }
    private var arg: String { st.arg }

    private var shownKinds: [ActionKind] {
        kinds.contains(kind) ? kinds : kinds + [kind]   // z. B. "Eigener Text" aus der Config anzeigen
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(get: { kind }, set: pick)) {
                ForEach(shownKinds) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 190)

            switch kind {
            case .keys:
                KeyRecorderField(combo: argBinding).frame(width: 190, height: 28)
            case .app:
                TextField("", text: argBinding, prompt: Text("App-Name oder Pfad")).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 150)
                Button("Wählen …", action: chooseApp)
            case .profile:
                Picker("", selection: argBinding) { ForEach(Profiles.names, id: \.self) { Text($0).tag($0) } }
                    .labelsHidden().frame(width: 190)
            case .shell:
                TextField("", text: argBinding, prompt: Text("Befehl")).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 190)
            case .custom:
                TextField("", text: argBinding, prompt: Text("z. B. key:cmd+c")).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 190)
            default:
                EmptyView()
            }
        }
        .padding(.vertical, 3)
        .onAppear(perform: syncFromSpec)
        .onChange(of: spec) { _, _ in syncFromSpec() }
    }

    private var argBinding: Binding<String> {
        Binding(get: { st.arg }, set: { st.arg = $0; commit() })
    }

    private func pick(_ new: ActionKind) {
        st.kind = new
        if ![.keys, .app, .shell, .custom].contains(new) { st.arg = "" }
        commit()
    }

    private func commit() { spec = ActionSpec(kind: st.kind, arg: st.arg).spec }

    /// Übernimmt Änderungen von außen (z. B. aus der Config-Datei), ohne eine gerade begonnene Auswahl zu verwerfen.
    private func syncFromSpec() {
        if ActionSpec(kind: st.kind, arg: st.arg).spec != spec {
            let s = ActionSpec(spec)
            st.kind = s.kind
            st.arg = s.arg
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url { st.arg = url.path; commit() }
    }
}

// MARK: - Entwicklerhilfe: Tabs als Bilder ausgeben (macmouse render <Ordner>)

func renderSettingsTabs(to dir: String) {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    settings.reloadIfChanged()
    let model = SettingsModel.shared
    model.displays = Displays.all()
    if ProcessInfo.processInfo.environment["MAUS_RENDER_DEMO"] != nil {   // Beispielwerte, damit die Akku-Zeilen sichtbar sind
        let b = BatteryInfo(percent: 48, charging: true, exact: 48)
        model.battery = b; model.polling = 8000; model.idle = 300; model.deviceDPI = 1870; model.liftOff = .asymmetric(lift: 13, land: 12)
        model.estimate = BatteryTracker(samples: []).estimate(for: b, hz: 8000)
    }
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let tabs: [(String, AnyView)] = [
        ("0-fenster", AnyView(SettingsRoot(model: model))),
        ("1-maus", AnyView(MouseTab(model: model))),
        ("1b-akku", AnyView(BatteryTab(model: model))),
        ("2-tasten", AnyView(ButtonsTab(model: model))),
        ("3-gesten", AnyView(GesturesTab(model: model))),
        ("4-scrollen", AnyView(ScrollTab(model: model))),
        ("4b-profile", AnyView(ProfilesTab(model: model))),
        ("5-bildschirme", AnyView(DisplaysTab(model: model))),
        ("6-info", AnyView(InfoTab(model: model))),
    ]
    for (name, view) in tabs {
        let host = NSHostingView(rootView: view.frame(width: 940, height: 1000))
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 1000), styleMask: [.titled],
                           backing: .buffered, defer: false)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))   // SwiftUI einmal rechnen lassen
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            print("geschrieben: \(dir)/\(name).png")
        }
    }
}
