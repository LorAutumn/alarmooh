import AlarmoohCore
import AppKit
import OSLog

// NSLog erscheint auf macOS 26 nicht mehr im Unified Log; OSLog schon.
let log = Logger(subsystem: "io.github.lorautumn.alarmooh", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let source = EventKitCalendarSource()
    // Lazy, damit das Menueleisten-Icon erst nach dem Start der App entsteht —
    // aber dann sofort: `applicationDidFinishLaunching` loest den Initializer
    // als Erstes aus, noch vor der Berechtigungsabfrage.
    private lazy var statusItem = StatusItemController()
    private lazy var coordinator = AlarmCoordinator(source: source, statusItem: statusItem)
    private lazy var settingsWindow = SettingsWindowController(
        coordinator: coordinator, source: source
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Das Menueleisten-Icon ist die einzige Oberflaeche dieser App und
        // entsteht deshalb ausdruecklich als Erstes — vor jeder Nachfrage nach
        // dem Kalenderzugriff. Diese Zeile loest den lazy-Initializer aus, und
        // `StatusItemController.init` baut sein Menue gleich mit; "alarmooh
        // beenden" ist damit ab hier erreichbar.
        //
        // Der Grund ist beobachtet, nicht theoretisch: bleibt die
        // Berechtigungsabfrage haengen (ein mehrfach abgebrochener
        // Systemdialog reicht), kehrt sie nie zurueck. Wuerde das Icon erst
        // danach entstehen, laeuft alarmooh als unsichtbarer Prozess weiter,
        // den man weder befragen noch beenden kann. Die Reihenfolge hier ist
        // deshalb Teil der Funktion und keine Stilfrage.
        let statusItem = self.statusItem

        // Auch ohne Kalenderzugriff erreichbar: dort steht, was alarmooh braucht.
        statusItem.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        statusItem.onTogglePause = { [weak self] in self?.coordinator.togglePause() }

        // Solange die Abfrage laeuft, waere "Kein überwachter Termin" eine
        // Falschaussage: alarmooh hat noch gar nicht nachgesehen. Der Hinweis
        // sagt stattdessen, worauf gewartet wird — und bleibt genau dann
        // stehen, wenn nie eine Antwort kommt. Bewusst ohne `warningAction`:
        // hier gibt es nichts anzuklicken, es ist nur ein Zustand.
        statusItem.rebuildMenu(
            nextEvent: nil,
            // Wie unten: `currentSettings` liest nur die Datei, ohne zu scannen.
            paused: coordinator.currentSettings.paused,
            warning: "Warte auf Kalenderzugriff…"
        )

        Task {
            guard await source.requestAccess() else {
                log.error("Kalenderzugriff verweigert")
                // Ohne Zugriff kann alarmooh gar nichts. Statt still im
                // "Kein Termin"-Zustand zu verharren, sagt das Menue, was fehlt,
                // und fuehrt direkt in die Systemeinstellungen.
                statusItem.rebuildMenu(
                    nextEvent: nil,
                    // Auch ohne Kalenderzugriff soll das Icon den Pausenstand
                    // zeigen; `currentSettings` liest nur die Datei, ohne zu scannen.
                    paused: coordinator.currentSettings.paused,
                    warning: "Kein Kalenderzugriff — alarmooh kann nichts überwachen",
                    warningAction: StatusItemController.WarningAction(
                        title: "Kalenderzugriff in den Systemeinstellungen erlauben…",
                        perform: Self.openCalendarPrivacySettings
                    )
                )
                return
            }
            coordinator.start()
            log.info("alarmooh bereit")
        }
    }

    /// Datenschutz-Bereich "Kalender" der Systemeinstellungen.
    private static func openCalendarPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
