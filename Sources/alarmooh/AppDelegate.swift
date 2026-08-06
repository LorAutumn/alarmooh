import AlarmoohCore
import AppKit
import OSLog

// NSLog erscheint auf macOS 26 nicht mehr im Unified Log; OSLog schon.
let log = Logger(subsystem: "io.github.lorautumn.alarmooh", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let source = EventKitCalendarSource()
    // Lazy, damit das Menueleisten-Icon erst nach dem Start der App entsteht.
    private lazy var statusItem = StatusItemController()
    private lazy var coordinator = AlarmCoordinator(source: source, statusItem: statusItem)
    private lazy var settingsWindow = SettingsWindowController(
        coordinator: coordinator, source: source
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Auch ohne Kalenderzugriff erreichbar: dort steht, was alarmooh braucht.
        statusItem.onOpenSettings = { [weak self] in self?.settingsWindow.show() }

        Task {
            guard await source.requestAccess() else {
                log.error("Kalenderzugriff verweigert")
                // Ohne Zugriff kann alarmooh gar nichts. Statt still im
                // "Kein Termin"-Zustand zu verharren, sagt das Menue, was fehlt,
                // und fuehrt direkt in die Systemeinstellungen.
                statusItem.rebuildMenu(
                    nextEvent: nil,
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
