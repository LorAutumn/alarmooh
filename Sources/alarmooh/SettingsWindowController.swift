import AppKit
import SwiftUI

/// Ein gewoehnliches Fenster fuer die Einstellungen — anders als das Alarm-Panel
/// darf und soll es den Fokus bekommen.
@MainActor
final class SettingsWindowController {
    private let coordinator: AlarmCoordinator
    private let source: EventKitCalendarSource
    private var window: NSWindow?

    init(coordinator: AlarmCoordinator, source: EventKitCalendarSource) {
        self.coordinator = coordinator
        self.source = source
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window

        // Frisches Modell bei jedem Oeffnen: der Stand kann sich seit dem
        // letzten Mal geaendert haben (Stummschaltung aus dem Alarm-Panel,
        // von Hand editierte Datei).
        let model = SettingsModel(coordinator: coordinator, source: source)
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.setContentSize(window.contentView?.fittingSize ?? NSSize(width: 480, height: 620))
        if !window.isVisible { window.center() }

        // alarmooh ist eine Menueleisten-App ohne Dock-Icon; ohne dieses
        // Aktivieren erschiene das Fenster hinter dem, was gerade vorn ist.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "alarmooh — Einstellungen"
        // Sonst gibt AppKit das Fenster beim Schliessen frei und die naechste
        // Verwendung liefe ins Leere; wir wollen es wiederverwenden.
        window.isReleasedWhenClosed = false
        return window
    }
}
