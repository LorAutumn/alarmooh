import AlarmoohCore
import AppKit

@MainActor
final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    var onOpenSettings: () -> Void = {}
    var onQuit: () -> Void = { NSApp.terminate(nil) }
    /// Klick aufs Icon waehrend eines Alarms stellt ihn ab.
    var onIconClickedDuringAlarm: (() -> Void)?

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

    func rebuildMenu(nextEvent: CalendarEvent?, warning: String? = nil) {
        let menu = NSMenu()
        if let warning {
            // Ganz oben und ohne Aktion: reiner Hinweis, den man nicht uebersieht.
            menu.addItem(withTitle: warning, action: nil, keyEquivalent: "")
            menu.addItem(.separator())
        }
        if let event = nextEvent {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            menu.addItem(
                withTitle: "Naechster: \(event.title) um \(formatter.string(from: event.start))",
                action: nil, keyEquivalent: ""
            )
        } else {
            menu.addItem(withTitle: "Kein ueberwachter Termin", action: nil, keyEquivalent: "")
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
    }
}
