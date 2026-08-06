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

    init(source: EventKitCalendarSource, statusItem: StatusItemController) {
        self.source = source
        self.statusItem = statusItem
        self.settings = settingsStore.load()
    }

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
        settings = settingsStore.load()
        let now = Date()
        let raw = (try? source.events(from: now, to: now.addingTimeInterval(86_400))) ?? []
        // Erst filtern, dann planen: der Scheduler kennt die Opt-out-Regeln nicht.
        events = EventFilter.alarmable(raw, settings: settings)
        forgetHandledEventsNoLongerRelevant()
        statusItem.rebuildMenu(nextEvent: events.first)
        scheduleNextAlarm()
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
        try? settingsStore.save(settings)
        scan()
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
