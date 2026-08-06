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
                statusItem.rebuildMenu(nextEvent: nil)
                return
            }
            coordinator.start()
            log.info("alarmooh bereit")
        }
    }
}
