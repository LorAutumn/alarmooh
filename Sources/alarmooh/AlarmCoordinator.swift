import AlarmoohCore
import AppKit
import CoreGraphics
import EventKit

/// Wird ueber Beginn und Ende des Vorhoerens unterrichtet. Klassengebunden,
/// damit der Koordinator den Beobachter schwach halten kann.
@MainActor
protocol PreviewObserver: AnyObject {
    func previewPlayingChanged(_ isPlaying: Bool)
}

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
    /// Feuert genau dann, wenn der im Menue gezeigte Termin aufhoert, aktuell zu
    /// sein — sonst stuende er dort bis zum naechsten Sicherheitstakt.
    private var menuRefreshTimer: Timer?
    /// Beendet einen laufenden Alarm von selbst; siehe `armAlarmEndTimer`.
    private var alarmEndTimer: Timer?
    private var activeAlarm: CalendarEvent?

    /// Genau ein Beobachter des Vorhoerens, und zwar der zuletzt angemeldete:
    /// das Einstellungsfenster baut bei jedem Oeffnen ein frisches
    /// `SettingsModel`, und das verworfene darf dem neuen nicht dazwischenreden.
    /// Schwach, damit ein verworfenes Modell nicht am Koordinator haengen
    /// bleibt — es haelt ihn seinerseits stark.
    private weak var previewObserver: (any PreviewObserver)?

    /// Die Datei ist vorhanden, aber unlesbar. Dann wird weder geschrieben noch
    /// nachgeladen — und der Nutzer muss es erfahren, sonst laeuft alarmooh
    /// scheinbar normal weiter, waehrend jede Aenderung ins Leere geht.
    private(set) var settingsFileBroken = false

    init(source: EventKitCalendarSource, statusItem: StatusItemController) {
        self.source = source
        self.statusItem = statusItem
        self.settings = settingsStore.load()
        self.settingsFileBroken = settingsStore.lastLoadFailed
        // Nur weitergereicht: der Player weiss als einziger, wann der Testton
        // endet, das Fenster als einziges, wie der Knopf dann heisst.
        player.onPreviewStateChanged = { [weak self] playing in
            self?.previewObserver?.previewPlayingChanged(playing)
        }
    }

    /// Stand, den das Einstellungsfenster anzeigt.
    var currentSettings: Settings { settings }

    // MARK: - Vorschau fuer das Einstellungsfenster

    /// Zeitraum, in dem das Einstellungsfenster nach den naechsten Terminen
    /// sucht. Bewusst viel weiter als das 24-Stunden-Fenster des Alarm-Scans:
    /// gefragt sind zehn Termine, und wer alle zwei Wochen einen Serientermin
    /// hat, findet den zehnten erst nach Monaten. 60 Tage decken auch einen
    /// leeren Kalender mit einem einzigen zweiwoechentlichen Termin ab (vier
    /// Vorkommen) und bleiben eine einzige, kurze EventKit-Abfrage.
    static let upcomingWindow: TimeInterval = 60 * 86_400
    /// So viele Termine zeigt das Einstellungsfenster.
    static let upcomingCount = 10

    /// Die naechsten Termine fuer die Auswahl im Einstellungsfenster.
    ///
    /// Gefiltert mit `selectable`, nicht mit `alarmable`: stummgeschaltete
    /// Termine muessen hier stehen bleiben, sonst kaeme man an den Schalter
    /// zum Wiedereinschalten gar nicht heran.
    ///
    /// Laeuft synchron beim Oeffnen des Fensters und beim Aendern der
    /// Kalenderauswahl — nicht im Alarmpfad.
    func upcomingEvents(limit: Int = upcomingCount) -> [CalendarEvent] {
        let now = Date()
        let raw = (try? source.events(from: now, to: now.addingTimeInterval(Self.upcomingWindow))) ?? []
        let candidates = EventFilter.selectable(raw, settings: settings)

        // Die Regel, wann ein Termin aufhoert aktuell zu sein, steht genau
        // einmal — in `AlarmScheduler`. Sie haengt allein am Startzeitpunkt und
        // die Liste ist nach Start sortiert; ab dem ersten noch aktuellen
        // Termin ist deshalb auch alles Folgende aktuell. Ein zweites
        // Nachbauen des Nachfrist-Vergleichs waere die Stelle, an der Menue und
        // Fenster spaeter auseinanderlaufen.
        guard
            let first = AlarmScheduler.nextRelevantEvent(
                events: candidates, now: now, settings: settings
            ),
            let start = candidates.firstIndex(where: { $0.id == first.id })
        else { return [] }

        return Array(candidates[start...].prefix(limit))
    }

    /// Schaltet ein einzelnes Vorkommen aus dem Einstellungsfenster stumm oder
    /// wieder scharf — ueber denselben Weg wie Menue und Alarmpanel.
    func setEventMuted(_ eventID: String, _ muted: Bool) {
        if muted {
            muteEvent(eventID)
        } else {
            settings.mutedEventIDs.remove(eventID)
            persistLocalChange()
        }
    }

    /// Dasselbe fuer eine ganze Serie: gilt fuer alle kuenftigen Vorkommen.
    func setSeriesMuted(_ seriesID: String, _ muted: Bool) {
        if muted {
            muteSeries(seriesID)
        } else {
            settings.mutedSeriesIDs.remove(seriesID)
            persistLocalChange()
        }
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
        // Nicht `events.first`: EventKit liefert auch Termine, die den
        // Suchzeitraum bloss ueberlappen, also laengst laufen. Dieselbe Regel wie
        // beim Alarm entscheidet, was "naechster Termin" heisst — nur ohne die
        // Pause. Denn auch pausiert bleiben "Naechster: …", Beitreten und
        // Stummschalten im Menue: wer die Alarme abgestellt hat, will trotzdem
        // an sein Meeting.
        let next = AlarmScheduler.nextRelevantEvent(
            events: events, now: now, settings: settings, handled: handled
        )
        statusItem.rebuildMenu(
            nextEvent: next,
            nextEventActions: next.map(menuActions(for:)),
            paused: settings.paused,
            warning: settingsWarning
        )
        scheduleMenuRefresh(for: next)
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
                // Weg wie im Panel, also nur dieses eine Vorkommen. Laeutet es
                // fuer genau diesen Termin schon, hoert es auf; darum das
                // „Alarm entfällt" im Menuetext.
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
    ///
    /// Zusammengefuehrt statt uebernommen: das Einstellungsfenster arbeitet auf
    /// einer Kopie, die es beim Oeffnen gezogen hat, und schreibt bei jedem Klick
    /// den ganzen Wert zurueck. Menue und Alarmpanel aendern dieselben
    /// Einstellungen aber weiter, waehrend das Fenster offen steht. Wuerde der
    /// eingehende Wert unbesehen gelten, machte der naechste Klick im Fenster
    /// jede zwischenzeitliche Aenderung rueckgaengig.
    ///
    /// Die Aufteilung des Besitzes:
    /// - Grundlage ist `settings`, der lebende Stand im Koordinator.
    /// - Aus `incoming` kommen nur die Felder, die das Fenster wirklich
    ///   bedient. Die Stummschaltungen gehoeren dazu: das Fenster entfernt
    ///   Eintraege ("Wieder alarmieren"), das muss ankommen.
    /// - `paused` kommt nie aus `incoming`. Der Schalter sitzt allein im Menue,
    ///   und die gefaehrliche Richtung ist genau diese: ein Speichern aus dem
    ///   Fenster darf eine Pause niemals aufheben, sonst waeren die Alarme
    ///   wieder scharf, ohne dass der Nutzer einen Anlass haette nachzusehen.
    /// - `catchUpGrace` steht in keinem Fenster und bleibt aus demselben Grund
    ///   beim Koordinator.
    ///
    /// Bewusst Feld fuer Feld ausgeschrieben statt `var merged = incoming` mit
    /// nachtraeglicher Korrektur: so ist an jeder Zeile ablesbar, welche Seite
    /// das Feld besitzt, und ein spaeter ergaenztes Feld muss hier ausdruecklich
    /// eingetragen werden, statt stillschweigend aus der veralteten Kopie des
    /// Fensters zu stammen.
    func apply(_ incoming: Settings) throws {
        var merged = settings
        // Vom Fenster verwaltet:
        merged.subscribedCalendarIDs = incoming.subscribedCalendarIDs
        merged.leadTime = incoming.leadTime
        merged.minimumVolume = incoming.minimumVolume
        merged.soundPath = incoming.soundPath
        merged.scanInterval = incoming.scanInterval
        merged.launchAtLogin = incoming.launchAtLogin
        merged.mutedEventIDs = incoming.mutedEventIDs
        merged.mutedSeriesIDs = incoming.mutedSeriesIDs
        // Nicht vom Fenster verwaltet, bleibt aus `settings`:
        // merged.paused         — gehoert dem Schalter im Menue
        // merged.catchUpGrace   — nur ueber die Datei einstellbar

        do {
            try settingsStore.save(merged)
        } catch {
            settingsFileBroken = true
            refresh()
            throw error
        }
        settings = merged
        settingsFileBroken = false
        refresh()
    }

    /// Spielt den Alarmton einmal zum Vorhoeren. Die Einstellungen kommen vom
    /// Aufrufer und nicht aus `settings`: das Fenster zeigt beim Ziehen des
    /// Reglers schon einen Wert, der noch nicht geschrieben ist — und genau den
    /// will der Nutzer hoeren.
    func previewSound(_ preview: Settings) {
        guard activeAlarm == nil else { return }
        player.preview(settings: preview)
    }

    /// Bricht das Vorhoeren ab. Die Lautstaerke stellt der Player dabei
    /// genauso wieder her wie am regulaeren Ende.
    func stopPreviewSound() {
        player.stopPreview()
    }

    /// Meldet den Beobachter des Vorhoerens an und verdraengt damit den
    /// vorherigen: ein Fenster, das neu aufgeht, ist ab hier allein zustaendig.
    /// Den aktuellen Stand bekommt es sofort, sonst zeigte ein waehrend des
    /// Testtons geoeffnetes Fenster "Ton testen" fuer einen laufenden Ton.
    func observePreview(_ observer: any PreviewObserver) {
        previewObserver = observer
        observer.previewPlayingChanged(player.isPreviewing)
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

    /// Ein einziger Timer auf den Moment, in dem der gezeigte Termin aufhoert,
    /// aktuell zu sein. Er ruft nur `refresh`, das dann den naechsten Termin
    /// bestimmt und sich selbst neu stellt — kein Takt, keine Schleife.
    ///
    /// Ohne ihn stuende ein laengst laufender Termin bis zum naechsten
    /// Sicherheitstakt (Standard: 30 Minuten) im Menue. Genau das ist
    /// aufgefallen.
    private func scheduleMenuRefresh(for event: CalendarEvent?) {
        menuRefreshTimer?.invalidate()
        menuRefreshTimer = nil
        guard let event else { return }

        // Eine Sekunde Zuschlag: Die Nachfrist gilt einschliesslich ihrer
        // Grenze. Genau auf der Grenze waehlte `refresh` denselben Termin
        // erneut und stellte einen Timer auf null Sekunden — eine Schleife.
        let expiry = event.start.addingTimeInterval(settings.catchUpGrace + 1)
        menuRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: max(expiry.timeIntervalSinceNow, 0), repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        menuRefreshTimer?.tolerance = 5
    }

    /// Stellt den Alarm nach `AlarmScheduler.alarmEndDate` von selbst ab. Der
    /// Ton laeuft also nicht mehr endlos, sondern hoechstens bis der Termin
    /// aufhoert, aktuell zu sein — mindestens aber eine Minute.
    private func armAlarmEndTimer(for event: CalendarEvent) {
        alarmEndTimer?.invalidate()
        let end = AlarmScheduler.alarmEndDate(for: event, now: Date(), settings: settings)
        alarmEndTimer = Timer.scheduledTimer(
            withTimeInterval: max(end.timeIntervalSinceNow, 0), repeats: false
        ) { [weak self] _ in
            // Derselbe Weg wie ein Klick auf „Stumm": Ton aus, Panel zu, Icon
            // normal, Vorkommen als erledigt vermerkt. Ohne den Vermerk fiele
            // der Termin sofort wieder in die Nachholfrist und laeutete erneut.
            Task { @MainActor in self?.dismissAlarm() }
        }
        alarmEndTimer?.tolerance = 1
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
        armAlarmEndTimer(for: event)

        let link = LinkExtractor.meetingLink(in: event)
        let view = AlarmView(
            event: event,
            link: link,
            onJoin: { [weak self] url in
                NSWorkspace.shared.open(url)
                self?.dismissAlarm()
            },
            onDismiss: { [weak self] in self?.dismissAlarm() },
            // Ohne eigenes `dismissAlarm`: Stummschalten beendet den laufenden
            // Alarm seit jeher — nur steht das jetzt in `muteEvent` und
            // `muteSeries` selbst und gilt damit auch fuer das Menue.
            onMuteEvent: { [weak self] in self?.muteEvent(event.id) },
            onMuteSeries: event.seriesID.map { seriesID in
                { [weak self] in self?.muteSeries(seriesID) }
            }
        )
        panel.show(view: view, below: statusItem.iconFrameOnScreen)
    }

    func dismissAlarm() {
        guard let event = activeAlarm else { return }
        // Weggedrueckt heisst erledigt: dieses Vorkommen laeutet nicht wieder.
        handled.insert(event.id)
        stopActiveAlarm()
        scheduleNextAlarm()   // ein direkt folgender Termin kommt jetzt dran
    }

    /// Beendet Ton und Panel, ohne das Vorkommen zu vermerken. Getrennt von
    /// `dismissAlarm`, weil Pausieren den Alarm zwar abstellt, ihn aber nicht
    /// als erledigt zaehlen darf.
    private func stopActiveAlarm() {
        // Vor dem Guard und ohne Bedingung: Auf welchem Weg der Alarm auch
        // endet — Beitreten, Stumm, Wegdruecken, Pausieren, Selbstabschaltung —,
        // der Endtimer darf nie stehen bleiben und in einen spaeteren Alarm
        // hineinfeuern.
        alarmEndTimer?.invalidate()
        alarmEndTimer = nil
        guard activeAlarm != nil else { return }
        activeAlarm = nil
        player.stop()
        panel.close()
        statusItem.setAlarming(false)
    }

    // MARK: - Pause

    /// Schaltet die Alarme ab oder wieder scharf — ohne Ablauf, der Nutzer
    /// entscheidet selbst. Die eigentliche Regel steht in `AlarmScheduler`.
    func togglePause() {
        settings.paused.toggle()
        if settings.paused {
            // Das Menue ist auch waehrend eines laufenden Alarms erreichbar;
            // sonst laeutete es nach dem Pausieren weiter. Bewusst ohne
            // `handled`: nach dem Fortsetzen wird der Termin wieder normal
            // behandelt, Pausieren ist kein Wegdruecken.
            stopActiveAlarm()
        }
        log.info("Alarme \(self.settings.paused ? "pausiert" : "fortgesetzt")")
        persistLocalChange()
    }

    /// Alle kuenftigen Vorkommen. Laeuft gerade ein Alarm dieser Serie, endet
    /// er mit — Begruendung und Reihenfolge stehen bei `muteEvent`.
    private func muteSeries(_ seriesID: String) {
        settings.mutedSeriesIDs.insert(seriesID)
        persistLocalChange()
        if activeAlarm?.seriesID == seriesID { dismissAlarm() }
    }

    /// Nur dieses eine Vorkommen. Die Kennung enthaelt den Startzeitpunkt,
    /// kuenftige Vorkommen derselben Serie bleiben also scharf.
    ///
    /// Trifft die Stummschaltung genau das Vorkommen, das gerade laeutet, endet
    /// der Alarm sofort: Ton aus, Panel zu, Icon normal, Lautstaerke zurueck.
    /// Das gilt fuer jeden Weg hierher — im Menue halten „Beitreten (Alarm
    /// entfällt)" und „Für diesen Termin nicht alarmieren" damit auch waehrend
    /// eines laufenden Alarms, was sie versprechen. Der Vergleich geht ueber die
    /// Kennung des Vorkommens: wer aus dem Menue einen spaeteren Termin
    /// stummschaltet, darf den laufenden Alarm nicht mit abwuergen.
    ///
    /// Erst speichern, dann abraeumen. `persistLocalChange` liest neu ein und
    /// plant dabei den naechsten Alarm — solange `activeAlarm` noch steht, plant
    /// `scheduleNextAlarm` aber gar nichts und laesst auch keinen alten Timer
    /// stehen. Das abschliessende `dismissAlarm` raeumt Ton, Panel, Icon und den
    /// Endtimer weg und plant danach aus der bereits aktualisierten Terminliste
    /// neu, in der dieses Vorkommen nicht mehr auftaucht. Andersherum plante
    /// `dismissAlarm` noch aus der alten Liste, und dass der Termin nicht sofort
    /// erneut losginge, haenge allein an `handled`.
    private func muteEvent(_ eventID: String) {
        settings.mutedEventIDs.insert(eventID)
        persistLocalChange()
        if activeAlarm?.id == eventID { dismissAlarm() }
    }

    /// Schreibt eine im Menue ausgeloeste Aenderung (Stummschaltung, Pause) und
    /// bewertet danach Menue und Timer neu.
    private func persistLocalChange() {
        do {
            try settingsStore.save(settings)
            scan()
        } catch {
            // Nicht verschlucken: die Aenderung gilt fuer diese Sitzung, aber
            // der Nutzer muss sehen, dass sie den Neustart nicht ueberlebt.
            settingsFileBroken = true
            log.error("Einstellung nicht gespeichert: \(error.localizedDescription)")
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
