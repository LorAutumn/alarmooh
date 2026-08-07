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
        //
        // Bewusst die veraltete Variante mit ignoringOtherApps: seit macOS 14
        // ist NSApp.activate() kooperativ — es bittet nur um die Aktivierung
        // und kehrt zurueck, bevor die App tatsaechlich aktiv ist. Das direkt
        // danach folgende makeKeyAndOrderFront verliert dann das Rennen gegen
        // das gerade aktive Programm; AppKit protokolliert "ordered front from
        // a non-active application and may order beneath the active
        // application's windows", und das Fenster erscheint dahinter.
        // Gemessen (Harness mit zwei Durchgaengen, Finder davor aktiv):
        // mit activate() blieb das Fenster jedes Mal hinter dem Finder und
        // wurde nie Key; mit ignoringOtherApps: true war es jedes Mal ganz
        // vorn und Key. Nur-Fenster-Tricks (orderFrontRegardless, Level
        // .floating) schieben das Fenster zwar nach vorn, machen es aber nicht
        // zum Key-Fenster — es klebt dann ueber dem aktiven Programm, ohne
        // Tastatureingaben zu bekommen. Apple fuehrt ignoringOtherApps in der
        // Dokumentation als veraltet; annotiert ist es nicht, der Compiler
        // warnt also nicht.
        NSApp.activate(ignoringOtherApps: true)
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
