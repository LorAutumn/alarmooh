import AlarmoohCore
import AppKit

@MainActor
final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    var onOpenSettings: () -> Void = {}
    var onQuit: () -> Void = { NSApp.terminate(nil) }

    /// Anklickbarer Eintrag direkt unter einem Hinweis — fuer Faelle, in denen
    /// der Nutzer das Problem selbst beheben kann (fehlender Kalenderzugriff).
    struct WarningAction {
        let title: String
        let perform: () -> Void
    }

    /// Haelt die Aktion des zuletzt aufgebauten Menues am Leben; NSMenuItem
    /// ruft ueber Target/Action, nicht ueber die Closure.
    private var warningAction: WarningAction?

    init() {
        item.button?.image = NSImage(
            systemSymbolName: "bell.badge", accessibilityDescription: "alarmooh"
        )
        item.button?.image?.isTemplate = true
        rebuildMenu(nextEvent: nil)
    }

    /// Position des Icons in Bildschirmkoordinaten — das Panel haengt sich darunter.
    var iconFrameOnScreen: NSRect? {
        guard let button = item.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    func setAlarming(_ alarming: Bool) {
        item.button?.contentTintColor = alarming ? .systemRed : nil
    }

    func rebuildMenu(
        nextEvent: CalendarEvent?,
        warning: String? = nil,
        warningAction: WarningAction? = nil
    ) {
        self.warningAction = warningAction
        let menu = NSMenu()
        if let warning {
            // Ganz oben und ohne Aktion: reiner Hinweis, den man nicht uebersieht.
            menu.addItem(withTitle: warning, action: nil, keyEquivalent: "")
            if let warningAction {
                // Anders als der Hinweis selbst anklickbar: er bekommt ein
                // Target und ist damit nicht ausgegraut.
                menu.addItem(
                    withTitle: warningAction.title,
                    action: #selector(MenuActions.runWarningAction), keyEquivalent: ""
                ).target = actions
            }
            menu.addItem(.separator())
        }
        if let event = nextEvent {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            menu.addItem(
                withTitle: "Nächster: \(event.title) um \(formatter.string(from: event.start))",
                action: nil, keyEquivalent: ""
            )
        } else {
            menu.addItem(withTitle: "Kein überwachter Termin", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Einstellungen…",
            action: #selector(MenuActions.openSettings), keyEquivalent: ","
        ).target = actions
        menu.addItem(
            withTitle: "alarmooh beenden",
            action: #selector(MenuActions.quit), keyEquivalent: "q"
        ).target = actions
        item.menu = menu
    }

    private lazy var actions = MenuActions(owner: self)

    @MainActor
    final class MenuActions: NSObject {
        weak var owner: StatusItemController?
        init(owner: StatusItemController) { self.owner = owner }
        @objc func openSettings() { owner?.onOpenSettings() }
        @objc func quit() { owner?.onQuit() }
        @objc func runWarningAction() { owner?.warningAction?.perform() }
    }
}
