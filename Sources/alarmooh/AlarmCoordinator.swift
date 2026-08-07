import AlarmoohCore
import AppKit
import CoreGraphics
import EventKit

/// Bindet Kalender, Zeitplanung, Ton und Oberflaeche zusammen.
///
/// Grundsatz: kein Polling. Aus jedem Scan entsteht genau ein Timer auf den
/// exakten Ausloesezeitpunkt; zwischen zwei Alarmen tut der Prozess nichts.
@MainActor
final class AlarmCoordinator {
    private let source: EventKitCalendarSource
    private let statusItem: StatusItemController
    private let panel = AlarmPanelController()
    private let player = AlarmPlayer()
    private let settingsStore = SettingsStore.standard()

    private var settings: Settings
    private var events: [CalendarEvent] = []
    private var handled: Set<String> = []
    private var alarmTimer: Timer?
    private var scanTimer: Timer?
    private var activeAlarm: CalendarEvent?

    /// Die Datei ist vorhanden, aber unlesbar. Dann wird weder geschrieben noch
    /// nachgeladen — und der Nutzer muss es erfahren, sonst laeuft alarmooh
    /// scheinbar normal weiter, waehrend jede Aenderung ins Leere geht.
    private(set) var settingsFileBroken = false

    init(source: EventKitCalendarSource, statusItem: StatusItemController) {
        self.source = source
        self.statusItem = statusItem
        self.settings = settingsStore.load()
        self.settingsFileBroken = settingsStore.lastLoadFailed
    }

    /// Stand, den das Einstellungsfenster anzeigt.
    var currentSettings: Settings { settings }

    func start() {
        // Muss vor jedem moeglichen Alarm laufen: laeuft es mitten im Alarm,
        // loescht es den lebenden Snapshot und die Lautstaerke bleibt oben.
        player.restoreVolumeAfterCrashIfNeeded()
        observeSystem()
        scheduleScanTimer()
        scan()
    }

    // MARK: - Scan

    /// Ausgeloest durch: EventKit-Aenderung, Sicherheitstakt, Aufwachen.
    func scan() {
        let loaded = settingsStore.load()
        if settingsStore.lastLoadFailed {
            // Bei defekter Datei liefert `load()` Standardwerte — und die haben
            // keine abonnierten Kalender. Wuerden wir die uebernehmen, faende
            // `EventFilter` nichts mehr und die App hoerte alle 30 Minuten aufs
            // Neue lautlos auf zu alarmieren. Also den Stand im Speicher behalten.
            settingsFileBroken = true
        } else {
            settings = loaded
            settingsFileBroken = false
        }
        refresh()
    }

    /// Wendet die Einstellungen aus dem Speicher an, ohne die Datei zu lesen.
    private func refresh() {
        let now = Date()
        let raw = (try? source.events(from: now, to: now.addingTimeInterval(86_400))) ?? []
        // Erst filtern, dann planen: der Scheduler kennt die Opt-out-Regeln nicht.
        events = EventFilter.alarmable(raw, settings: settings)
        forgetHandledEventsNoLongerRelevant()
        let next = events.first
        statusItem.rebuildMenu(
            nextEvent: next,
            nextEventActions: next.map(menuActions(for:)),
            warning: settingsWarning
        )
        scheduleNextAlarm()
    }

    /// Der Link wird hier bestimmt, nicht im Menue: `LinkExtractor` gehoert zur
    /// Kalenderauswertung, und der Koordinator haelt ohnehin die gefilterte
    /// Liste. So bleibt `StatusItemController` ein reiner Menuebauer.
    private func menuActions(for event: CalendarEvent) -> StatusItemController.NextEventActions {
        StatusItemController.NextEventActions(
            link: LinkExtractor.meetingLink(in: event),
            join: { [weak self] url in
                NSWorkspace.shared.open(url)
                // Wer frueh beitritt, will spaeter keinen Alarm mehr — derselbe
                // Weg wie im Panel, also nur dieses eine Vorkommen.
                self?.muteEvent(event.id)
            },
            mute: { [weak self] in self?.muteEvent(event.id) }
        )
    }

    private var settingsWarning: String? {
        settingsFileBroken
            ? "settings.json ist defekt — Änderungen werden nicht gespeichert"
            : nil
    }

    /// Schreibt neue Einstellungen und wendet sie sofort an. Scheitert das
    /// Schreiben, bleibt auch der Stand im Speicher unveraendert — sonst zeigte
    /// das Fenster etwas an, das den naechsten Start nicht ueberlebt.
    func apply(_ new: Settings) throws {
        do {
            try settingsStore.save(new)
        } catch {
            settingsFileBroken = true
            refresh()
            throw error
        }
        settings = new
        settingsFileBroken = false
        refresh()
    }

    /// Verhindert, dass die Menge der erledigten Alarme unbegrenzt waechst:
    /// Termine ausserhalb des 24-Stunden-Fensters werden vergessen.
    private func forgetHandledEventsNoLongerRelevant() {
        handled.formIntersection(Set(events.map(\.id)))
    }

    // MARK: - Timer

    private func scheduleNextAlarm() {
        alarmTimer?.invalidate()
        guard activeAlarm == nil,
              let next = AlarmScheduler.nextAlarm(
                  events: events, now: Date(), settings: settings, handled: handled
              )
        else { return }

        let delay = max(next.fireDate.timeIntervalSinceNow, 0)
        alarmTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fire(next.event) }
        }
        // Wichtig fuer minimale Last: ein einziger Timer, keine Schleife.
        alarmTimer?.tolerance = 5
    }

    private func scheduleScanTimer() {
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(
            withTimeInterval: settings.scanInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
        scanTimer?.tolerance = 60
    }

    // MARK: - Alarm

    private func fire(_ event: CalendarEvent) {
        // Nur bei aktivem Rechner: schlaeft das Display oder ist der Deckel zu,
        // wird der Alarm verworfen und beim Aufwachen neu bewertet.
        guard CGDisplayIsAsleep(CGMainDisplayID()) == 0 else { return }

        activeAlarm = event
        statusItem.setAlarming(true)
        player.start(settings: settings)

        let link = LinkExtractor.meetingLink(in: event)
        let view = AlarmView(
            event: event,
            link: link,
            onJoin: { [weak self] url in
                NSWorkspace.shared.open(url)
                self?.dismissAlarm()
            },
            onDismiss: { [weak self] in self?.dismissAlarm() },
            onMuteEvent: { [weak self] in
                self?.muteEvent(event.id)
                self?.dismissAlarm()
            },
            onMuteSeries: event.seriesID.map { seriesID in
                { [weak self] in
                    self?.muteSeries(seriesID)
                    self?.dismissAlarm()
                }
            }
        )
        panel.show(view: view, below: statusItem.iconFrameOnScreen)
    }

    func dismissAlarm() {
        guard let event = activeAlarm else { return }
        handled.insert(event.id)
        activeAlarm = nil
        player.stop()
        panel.close()
        statusItem.setAlarming(false)
        scheduleNextAlarm()   // ein direkt folgender Termin kommt jetzt dran
    }

    private func muteSeries(_ seriesID: String) {
        settings.mutedSeriesIDs.insert(seriesID)
        persistMute()
    }

    /// Nur dieses eine Vorkommen. Die Kennung enthaelt den Startzeitpunkt,
    /// kuenftige Vorkommen derselben Serie bleiben also scharf.
    private func muteEvent(_ eventID: String) {
        settings.mutedEventIDs.insert(eventID)
        persistMute()
    }

    private func persistMute() {
        do {
            try settingsStore.save(settings)
            scan()
        } catch {
            // Nicht verschlucken: die Stummschaltung gilt fuer diese Sitzung,
            // aber der Nutzer muss sehen, dass sie den Neustart nicht ueberlebt.
            settingsFileBroken = true
            log.error("Stummschaltung nicht gespeichert: \(error.localizedDescription)")
            refresh()
        }
    }

    // MARK: - Systemereignisse

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scan() }
            }
        }
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }
}
