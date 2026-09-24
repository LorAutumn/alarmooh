import AlarmoohCore
import AppKit
import OSLog

// NSLog erscheint auf macOS 26 nicht mehr im Unified Log; OSLog schon.
// Subsystem ist die Bundle-ID, mit der gebaut wurde (siehe Scripts/bundle.sh).
let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "alarmooh", category: "app")

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
    /// Eigener Zugang zur Systemlautstaerke, ausdruecklich neben dem des
    /// Players im Koordinator. Er kennt keinen laufenden Alarm, sondern nur den
    /// Snapshot auf der Platte — und genau der ist das, was ueber das Ende
    /// eines Prozesses hinaus zaehlt. Beide Controller teilen sich diese Datei;
    /// mehr Verbindung brauchen sie nicht.
    private let volumeController = SystemVolumeController()

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

        // Gleich danach und ohne jede Bedingung: Endete der letzte Lauf mitten
        // im Alarm, steht die Systemlautstaerke noch oben, und das Einzige, was
        // davon weiss, ist die Snapshot-Datei.
        //
        // Bisher lief diese Wiederherstellung nur in `AlarmCoordinator.start()`
        // — also erst im Erfolgszweig hinter `requestAccess()`. Wird der Zugriff
        // verweigert, spaeter entzogen oder bleibt die Abfrage haengen (genau
        // der Fall, der weiter unten beschrieben ist), wurde die Datei nie
        // gelesen und die Lautstaerke blieb dauerhaft oben. Mit dem Kalender hat
        // das Zuruecksetzen nichts zu tun: es liest eine Datei und schreibt
        // hoechstens eine Lautstaerke.
        //
        // Zweimal laufen kann es deshalb nicht: `restoreAfterCrashIfNeeded`
        // loescht die Datei, sobald sie angewandt ist, und `snapshots.load()`
        // findet danach nichts mehr. Der Aufruf im Koordinator bleibt also
        // stehen und wird wirkungslos — er kommt ohnehin spaeter und immer noch
        // vor dem ersten moeglichen Alarm, trifft also nie einen lebenden
        // Snapshot.
        volumeController.restoreAfterCrashIfNeeded()

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

    /// Das Anheben der Systemlautstaerke ist nur unter der Zusage vertretbar,
    /// dass es immer zurueckgenommen wird. Beenden war die Luecke darin: „alarmooh
    /// beenden" steht im Menue, ist die naheliegendste Reaktion auf einen Alarm,
    /// den man loswerden will — und beendete den Prozess, ohne dass je ein
    /// `restore()` lief. Zurueck blieb ein lautes Geraet.
    ///
    /// Ein eigenes Zuruecksetzen steht hier bewusst nicht: `AlarmPlayer.stop()`
    /// stellt die Lautstaerke bereits selbst wieder her, und beide Wege unten
    /// fuehren dorthin. Eine zweite Fassung derselben Regel liefe frueher oder
    /// spaeter auseinander.
    func applicationWillTerminate(_ notification: Notification) {
        // Erst das Vorhoeren: auch der Testton hebt die Lautstaerke an. Laeuft
        // daneben ein Alarm, gehoert der Snapshot ihm — `stopPreview()` weiss
        // das und setzt dann nichts zurueck, weshalb dieser Aufruf vor dem
        // naechsten stehen muss.
        coordinator.stopPreviewSound()
        // Dann der Alarm selbst, auf demselben Weg wie ein Klick auf „Stumm":
        // Ton aus, Panel zu, Lautstaerke zurueck. Laeuft keiner, passiert nichts.
        coordinator.dismissAlarm()
        // Zuletzt die Datei. Sie deckt ab, was die beiden Aufrufe oben nicht
        // erreichen — etwa einen Snapshot, dessen Besitzer diesen Prozess nicht
        // ueberlebt hat. Nach einer erfolgreichen Wiederherstellung ist sie weg,
        // dieser Aufruf also folgenlos.
        volumeController.restore()
    }

    /// Datenschutz-Bereich "Kalender" der Systemeinstellungen.
    private static func openCalendarPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
