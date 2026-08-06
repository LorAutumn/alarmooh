import AlarmoohCore
import AppKit
import Observation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Haelt den Stand des Einstellungsfensters und schreibt jede Aenderung sofort.
///
/// Es gibt bewusst kein „Sichern"-Knopf: das Fenster ist die einzige Stelle, an
/// der ein Nutzer die App ueberhaupt scharf schaltet, und ein halb uebernommener
/// Stand waere hier schlimmer als ein Schreibvorgang pro Klick.
@MainActor
@Observable
final class SettingsModel {
    // Voll qualifiziert: SwiftUI hat eine eigene Szene namens `Settings`.
    var settings: AlarmoohCore.Settings
    private(set) var calendars: [CalendarInfo] = []
    private(set) var fileBroken: Bool
    /// Fehler des letzten Schreibversuchs; nil, wenn alles sitzt.
    private(set) var saveError: String?
    /// Fehler von `SMAppService`, getrennt gehalten, weil er in einem anderen
    /// Abschnitt steht und nichts mit der Datei zu tun hat.
    private(set) var loginError: String?

    private let coordinator: AlarmCoordinator

    init(coordinator: AlarmCoordinator, source: EventKitCalendarSource) {
        self.coordinator = coordinator
        self.settings = coordinator.currentSettings
        self.fileBroken = coordinator.settingsFileBroken
        self.calendars = (try? source.calendars()) ?? []
    }

    /// Uebernimmt den aktuellen Stand. Scheitert das Schreiben, faellt die
    /// Anzeige auf den tatsaechlich geltenden Stand zurueck — ein Haekchen, das
    /// nirgends ankommt, waere eine Luege.
    func save() {
        do {
            try coordinator.apply(settings)
            saveError = nil
        } catch {
            settings = coordinator.currentSettings
            saveError = error.localizedDescription
        }
        fileBroken = coordinator.settingsFileBroken
    }

    // MARK: - Kalender

    func isSubscribed(_ id: String) -> Bool { settings.subscribedCalendarIDs.contains(id) }

    func setSubscribed(_ id: String, _ subscribed: Bool) {
        if subscribed {
            settings.subscribedCalendarIDs.insert(id)
        } else {
            settings.subscribedCalendarIDs.remove(id)
        }
        save()
    }

    // MARK: - Alarmton

    /// Kopiert die gewaehlte Datei neben die Einstellungen. Wuerde alarmooh nur
    /// den Pfad merken, waere der Alarm stumm, sobald der Nutzer die Datei
    /// verschiebt oder loescht — und das faellt erst im Ernstfall auf.
    func chooseSound(_ url: URL) {
        do {
            let directory = SettingsStore.supportDirectory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Der erzeugte Ersatzton liegt im selben Verzeichnis und darf nicht
            // von einer gleichnamigen Nutzerdatei ueberschrieben werden.
            let name = url.lastPathComponent == "fallback-tone.wav"
                ? "alarm-\(url.lastPathComponent)"
                : url.lastPathComponent
            let target = directory.appendingPathComponent(name)
            if target != url {
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.copyItem(at: url, to: target)
            }
            settings.soundPath = target.path
            save()
        } catch {
            saveError = "Ton nicht übernommen: \(error.localizedDescription)"
        }
    }

    func resetSound() {
        settings.soundPath = nil
        save()
    }

    // MARK: - Stummschaltungen

    func unmuteEvent(_ id: String) {
        settings.mutedEventIDs.remove(id)
        save()
    }

    func unmuteSeries(_ id: String) {
        settings.mutedSeriesIDs.remove(id)
        save()
    }

    // MARK: - Anmeldeobjekt

    func setLaunchAtLogin(_ enabled: Bool) {
        // Erst umschalten, damit SwiftUI den Schalter im Fehlerfall sichtbar
        // zuruecknehmen kann.
        settings.launchAtLogin = enabled
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            settings.launchAtLogin = !enabled
            loginError = error.localizedDescription
            return
        }
        loginError = nil
        save()
    }
}

struct SettingsView: View {
    // Kein `@Bindable`: dessen dynamische Mitglieder verdecken in den
    // Closures unten den eigentlichen Wert. Bindings deshalb von Hand.
    let model: SettingsModel

    var body: some View {
        Form {
            if model.fileBroken { brokenFileSection }
            calendarSection
            leadTimeSection
            volumeSection
            soundSection
            mutedSection
            loginSection
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 620)
    }

    // MARK: - Abschnitte

    private var brokenFileSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("settings.json ist defekt").bold()
                    Text(
                        "Änderungen in diesem Fenster können nicht gespeichert werden. "
                        + "alarmooh läuft mit dem zuletzt gültigen Stand weiter. "
                        + "Datei reparieren oder löschen: \(SettingsStore.standard().fileURL.path)"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }

    private var calendarSection: some View {
        Section("Kalender") {
            if model.calendars.isEmpty {
                Text("Keine Kalender gefunden — hat alarmooh Zugriff auf deine Kalender?")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.calendars) { calendar in
                    Toggle(calendar.title, isOn: Binding(
                        get: { model.isSubscribed(calendar.id) },
                        set: { model.setSubscribed(calendar.id, $0) }
                    ))
                }
            }
            Text("Nur Termine aus angehakten Kalendern lösen einen Alarm aus.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let saveError = model.saveError {
                Text(saveError).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private var leadTimeSection: some View {
        Section("Vorlaufzeit") {
            Stepper(value: leadMinutes, in: 1...15) {
                Text("\(leadMinutes.wrappedValue) Minuten vor Terminbeginn")
            }
        }
    }

    private var volumeSection: some View {
        Section("Mindestlautstärke") {
            HStack {
                Slider(value: minimumVolume, in: 0...1) { editing in
                    // Erst beim Loslassen schreiben, sonst eine Datei pro Pixel.
                    if !editing { model.save() }
                }
                Text("\(Int((model.settings.minimumVolume * 100).rounded())) %")
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
            }
            Text(
                "alarmooh hebt die Systemlautstärke für die Dauer eines Alarms auf "
                + "mindestens diesen Wert an und stellt danach den vorherigen Wert wieder her."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var soundSection: some View {
        Section("Alarmton") {
            LabeledContent("Datei") {
                Text(model.settings.soundPath ?? "Mitgelieferter Ton")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Datei wählen…") { chooseSound() }
                Button("Mitgelieferten Ton verwenden") { model.resetSound() }
                    .disabled(model.settings.soundPath == nil)
            }
            Text("Die gewählte Datei wird nach ~/Library/Application Support/alarmooh/ kopiert, "
                 + "damit der Alarm auch nach dem Verschieben des Originals funktioniert.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var mutedSection: some View {
        Section("Stummgeschaltet") {
            if model.settings.mutedEventIDs.isEmpty && model.settings.mutedSeriesIDs.isEmpty {
                Text("Nichts stummgeschaltet").foregroundStyle(.secondary)
            } else {
                ForEach(model.settings.mutedSeriesIDs.sorted(), id: \.self) { id in
                    mutedRow(label: "Serie", id: id) { model.unmuteSeries(id) }
                }
                ForEach(model.settings.mutedEventIDs.sorted(), id: \.self) { id in
                    mutedRow(label: "Termin", id: id) { model.unmuteEvent(id) }
                }
            }
        }
    }

    private func mutedRow(label: String, id: String, remove: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(id).font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Wieder alarmieren", action: remove)
        }
    }

    private var loginSection: some View {
        Section("Start") {
            Toggle("Bei Anmeldung starten", isOn: Binding(
                get: { model.settings.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            Text("Zuverlässig erst, wenn Alarmooh.app in /Applications liegt.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let loginError = model.loginError {
                Text(loginError).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Hilfen

    private var minimumVolume: Binding<Float> {
        Binding(
            get: { model.settings.minimumVolume },
            set: { model.settings.minimumVolume = $0 }
        )
    }

    private var leadMinutes: Binding<Int> {
        Binding(
            get: { min(max(Int((model.settings.leadTime / 60).rounded()), 1), 15) },
            set: {
                model.settings.leadTime = TimeInterval($0 * 60)
                model.save()
            }
        )
    }

    private func chooseSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Wählen"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.chooseSound(url)
    }
}
