import Foundation

/// Art einer Aktion, wie sie im Einstellungsfenster gewählt wird. Gespeichert wird sie als Text in der Config
/// (z. B. "key:cmd+shift+4", "mission", "dpi:next", "app:Safari", "shell:say hallo").
enum ActionKind: String, CaseIterable, Identifiable {
    case passthrough, none, keys, mission, appexpose, desktopLeft, desktopRight, dpiNext, dpiPrev, profileNext, profilePrev, profile, app, shell, custom, gesture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passthrough: return "Normal"
        case .none: return "Nichts"
        case .keys: return "Tastenkombination"
        case .mission: return "Mission Control"
        case .appexpose: return "App Exposé"
        case .desktopLeft: return "Desktop links"
        case .desktopRight: return "Desktop rechts"
        case .dpiNext: return "DPI: nächste Stufe"
        case .dpiPrev: return "DPI: vorherige Stufe"
        case .profileNext: return "Profil: nächstes"
        case .profilePrev: return "Profil: vorheriges"
        case .profile: return "Profil wechseln zu …"
        case .app: return "App starten"
        case .shell: return "Shell-Befehl"
        case .custom: return "Eigener Text (Config)"
        case .gesture: return "Gesten-Taste"
        }
    }

    static let common: [ActionKind] = [.none, .keys, .mission, .appexpose, .desktopLeft, .desktopRight,
                                       .dpiNext, .dpiPrev, .profileNext, .profilePrev, .profile, .app, .shell]
}

struct ActionSpec {
    var kind: ActionKind
    var arg: String

    /// Marker für "diese Taste ist die Gesten-Taste" (wird nicht in `buttons` gespeichert).
    static let gestureMarker = "@gesture"

    init(_ spec: String?) {
        let s = (spec ?? "passthrough").trimmingCharacters(in: .whitespaces)
        let lower = s.lowercased()
        kind = .custom
        arg = s
        switch lower {
        case "", "passthrough": kind = .passthrough; arg = ""
        case "none": kind = .none; arg = ""
        case "mission": kind = .mission; arg = ""
        case "appexpose": kind = .appexpose; arg = ""
        case "desktopleft": kind = .desktopLeft; arg = ""
        case "desktopright": kind = .desktopRight; arg = ""
        case "dpi:next": kind = .dpiNext; arg = ""
        case "dpi:prev": kind = .dpiPrev; arg = ""
        case "profile:next": kind = .profileNext; arg = ""
        case "profile:prev": kind = .profilePrev; arg = ""
        case ActionSpec.gestureMarker: kind = .gesture; arg = ""
        default:
            if lower.hasPrefix("key:") { kind = .keys; arg = String(s.dropFirst(4)) }
            else if lower.hasPrefix("profile:") { kind = .profile; arg = String(s.dropFirst(8)) }
            else if lower.hasPrefix("app:") { kind = .app; arg = String(s.dropFirst(4)) }
            else if lower.hasPrefix("shell:") { kind = .shell; arg = String(s.dropFirst(6)) }
        }
    }

    init(kind: ActionKind, arg: String = "") { self.kind = kind; self.arg = arg }

    /// Text für die Config. Ohne Angabe (leere Kombination, kein App-Name …) passiert nichts.
    var spec: String {
        switch kind {
        case .passthrough: return "passthrough"
        case .none: return "none"
        case .keys: return arg.isEmpty ? "none" : "key:\(arg)"
        case .mission: return "mission"
        case .appexpose: return "appexpose"
        case .desktopLeft: return "desktopleft"
        case .desktopRight: return "desktopright"
        case .dpiNext: return "dpi:next"
        case .dpiPrev: return "dpi:prev"
        case .profileNext: return "profile:next"
        case .profilePrev: return "profile:prev"
        case .profile: return arg.isEmpty ? "none" : "profile:\(arg)"
        case .app: return arg.isEmpty ? "none" : "app:\(arg)"
        case .shell: return arg.isEmpty ? "none" : "shell:\(arg)"
        case .custom: return arg.isEmpty ? "none" : arg
        case .gesture: return ActionSpec.gestureMarker
        }
    }
}
