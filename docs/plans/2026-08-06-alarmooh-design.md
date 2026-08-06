# alarmooh — Design

**Datum:** 2026-08-06
**Status:** abgestimmt, bereit für die Implementierungsplanung

## Zweck

alarmooh ist eine eigenständige macOS-App in der Menüleiste. Sie liest den lokalen
Kalender, erkennt die nächsten wichtigen Termine und schlägt zwei Minuten vor Beginn
mit einem dauerhaft schleifenden Signalton Alarm. Der Ton läuft, bis der Nutzer ihn
abstellt — entweder durch Klick auf den Meeting-Link oder durch Stummschalten.

Kein Backend, kein Netzwerkzugriff, keine Konten. Ein einzelner lokaler Prozess.

## Rahmenbedingungen

- Swift, macOS, Swift Package Manager, baubar von der Kommandozeile.
- Nur Menüleiste, kein Dock-Icon.
- Minimale Systemlast: seltene Scans, ein präziser Timer, im Leerlauf keine Aktivität.
- Der Ton muss zuverlässig gehört werden, auch bei leise gestelltem Rechner.
- Der Alarm feuert nur, wenn der Rechner aktiv ist.

## Entscheidungen

| Frage | Entscheidung | Grund |
|---|---|---|
| Kalenderquelle | EventKit über Kalender.app | Kein OAuth, kein Google-Cloud-Projekt, kein Netzwerkcode. macOS synchronisiert, alarmooh liest. |
| Terminauswahl | Opt-out | Abonnierte Kalender alarmieren vollständig; einzelne Termine und Serien lassen sich stummschalten. |
| Alarm-Darstellung | Schwebendes Panel unter dem Menüleisten-Icon | Über allen Fenstern und Spaces sichtbar, unabhängig von Fokus-Modus und Mitteilungszentrale. |
| Alarmton | Datei in Application Support, im Repo nur ein Fallback-Ton | Die Tokioter Abfahrtsmelodien sind urheberrechtlich geschützt; privat abspielen ist unkritisch, im Repo verbreiten nicht. |
| Lautstärke | Systemlautstärke temporär anheben, danach wiederherstellen | Volle App-Lautstärke allein bleibt bei leisem Mac unhörbar. |
| Projektsetup | SPM plus `make bundle` | Git-freundlich und ohne Xcode baubar; EventKit verlangt trotzdem ein signiertes App-Bundle. |

## Architektur

Zwei Targets, damit die Logik ohne UI testbar bleibt.

### AlarmoohCore (Library, UI-frei)

- **`CalendarSource`** — Protokoll: liefert Termine im Fenster *jetzt bis +24 h*.
  Implementierungen: `EventKitCalendarSource` produktiv, `FakeCalendarSource` im Test.
- **`EventFilter`** — wendet die Opt-out-Regeln an.
- **`LinkExtractor`** — findet Meeting-URLs in Termindaten.
- **`AlarmScheduler`** — bestimmt den nächsten fälligen Alarm.
- **`Settings`** — abonnierte Kalender, Mute-Liste, Vorlaufzeit, Mindestlautstärke, Sound-Pfad.

### alarmooh (Executable, AppKit mit SwiftUI-Views)

- **`StatusItemController`** — Menüleisten-Icon und Menü.
- **`AlarmPanelController`** — das schwebende Alarm-Fenster.
- **`AlarmPlayer`** — Endlosschleife des Alarmtons.
- **`SystemVolumeController`** — CoreAudio, hebt und stellt die Ausgabelautstärke zurück.

AppKit-Lifecycle statt SwiftUI `MenuBarExtra`: In einem selbst zusammengebauten
SPM-Bundle ist `NSStatusItem` das verlässlichere Fundament, und ein `NSPanel` mit
eigenem Window-Level wird ohnehin gebraucht. Die Fensterinhalte sind SwiftUI.

### Datenfluss

```
EventKit
   │  Scan-Fenster: jetzt … +24 h
   ▼
EventFilter ──► sortierte Terminliste
   │
   ▼
AlarmScheduler ──► genau ein Timer auf (Start − Vorlaufzeit)
   │
   ▼  feuert, sofern der Rechner aktiv ist
AlarmPanel + AlarmPlayer + Systemlautstärke hoch
   │
   ▼  Nutzeraktion
Ton aus, Lautstärke zurück, nächster Timer wird gesetzt
```

## Kalender lesen und Alarme planen

### Zugriff

Beim ersten Start einmalig `requestFullAccessToEvents`. Wird die Berechtigung
verweigert, zeigt das Menü einen Hinweis mit Direktlink in die Systemeinstellungen,
statt stillschweigend nichts zu tun.

### Scan-Auslöser

Ausgelesen wird immer nur das Fenster *jetzt bis +24 h*, nie der ganze Kalender.
Drei Auslöser:

1. `EKEventStoreChanged` — das System meldet Änderungen von sich aus, kein Polling nötig.
2. Ein Sicherheitstakt alle 30 Minuten (einstellbar).
3. Aufwachen aus dem Ruhezustand.

Der Scan-Takt hat nichts mit der Alarmgenauigkeit zu tun. Aus dem Scan entsteht
genau ein Timer auf den exakten Auslösezeitpunkt. Zwischen zwei Alarmen ist der
Prozess untätig.

### Filterregeln (Opt-out)

1. Nur Termine aus abonnierten Kalendern.
2. Stummgeschaltetes entfällt: einzelner Termin über seine Event-ID, ganze Serie über
   `calendarItemExternalIdentifier`, womit alle künftigen Vorkommen still sind.
3. Grundsätzlich ausgeblendet, weil ein Alarm dort sinnlos ist:
   - ganztägige Termine — kein sinnvoller Startzeitpunkt,
   - abgesagte Termine,
   - explizit abgelehnte Termine.

   Zugesagte und unbeantwortete Termine alarmieren beide.

### Planung

Der Scheduler nimmt den nächsten Termin der gefilterten Liste und setzt einen Timer
auf `Start − Vorlaufzeit` (Standard: 2 Minuten, einstellbar). Nach jedem Alarm und
jedem Scan wird neu gesetzt.

Liegen zwei Termine dicht beieinander, überschreibt der zweite den laufenden Alarm
nicht. Er reiht sich an und erscheint, sobald der erste abgestellt ist.

### Nur bei aktivem Rechner

Schläft der Rechner oder ist der Deckel geschlossen, feuert kein Alarm; alarmooh
weckt den Rechner auch nicht. Der Zustand wird über die Schlaf- und
Aufwach-Benachrichtigungen von `NSWorkspace` verfolgt.

Beim Aufwachen wird ein verpasster Alarm nur nachgeholt, wenn der Termin noch nicht
begonnen hat oder höchstens zwei Minuten läuft. Alles Ältere verfällt still.

### Meeting-Link

Gesucht wird in dieser Reihenfolge: URL-Feld des Termins, Notizen, Ortsfeld.
Erkannt werden Google Meet, Zoom, Teams und Whereby, ersatzweise die erste beliebige
`https://`-URL. Ohne Fund zeigt das Panel nur den Stumm-Button.

## Menüleiste, Alarm-Fenster, Ton

### Menüleisten-Icon

Ein Template-Symbol (Glocke), das im Alarmzustand die Farbe wechselt. Das Menü zeigt
den nächsten überwachten Termin mit Uhrzeit sowie „Einstellungen…" und „Beenden".
Kein Dock-Icon und kein App-Switcher-Eintrag — geregelt über `LSUIElement`.

### Alarm-Fenster

Ein `NSPanel` direkt unter dem Icon, positioniert über die Bildschirmkoordinaten des
Status-Item-Buttons:

- *nonactivating* — stiehlt keinen Tastaturfokus, Weiterarbeiten bleibt möglich.
- Window-Level oberhalb normaler Fenster, dazu `canJoinAllSpaces` und
  `fullScreenAuxiliary`: sichtbar auf jedem Space und über Vollbild-Apps.
- Fallback: Ist das Icon nicht sichtbar (Menüleisten-Überlauf, Notch), erscheint das
  Panel oben mittig auf dem aktiven Bildschirm.

Inhalt: Terminname groß, darunter Startzeit und Kalendername, dann die Aktionen.

- **Beitreten** — nur bei gefundenem Link. Öffnet die URL und stoppt den Ton in einem Klick.
- **Stumm** — beendet den Alarm. Immer vorhanden.
- **Diese Serie nie wieder** — schreibt die Serie direkt in die Mute-Liste.

`ESC` und ein Klick aufs Menüleisten-Icon beenden den Alarm ebenfalls.

### Ton und Lautstärke

`AVAudioPlayer` mit `numberOfLoops = -1`: endlos, bis der Nutzer stoppt. Kein
Auto-Timeout.

Parallel setzt `SystemVolumeController` per CoreAudio die Ausgabelautstärke auf den
eingestellten Mindestwert und hebt eine Stummschaltung auf. Der vorherige Zustand
wird gemerkt und beim Stoppen sowie beim Beenden der App zurückgeschrieben.
Zusätzlich wird er auf Platte geschrieben, damit ein Absturz während des Alarms die
Lautstärke nicht dauerhaft oben stehen lässt — beim nächsten Start wird sie
wiederhergestellt.

### Alarmton-Datei

Die App nutzt die Audiodatei in `~/Library/Application Support/alarmooh/`. Der Nutzer
legt sie dort ab oder wählt sie einmalig im Einstellungsfenster. Im Repository liegt
nur ein schlichter, selbst erzeugter Fallback-Ton; das Audio-Verzeichnis ist
gitignored.

Hintergrund: Die Tokioter Abfahrtsmelodien sind komponierte, geschützte Werke. Privat
abspielen ist unkritisch, sie ins Repository zu legen und weiterzugeben wäre es nicht.

## Einstellungen und Persistenz

`settings.json` in `~/Library/Application Support/alarmooh/` — lesbar und im Test
beschreibbar, statt `UserDefaults`:

- abonnierte Kalender-IDs
- Mute-Liste (Event-IDs und Serien-IDs)
- Vorlaufzeit
- Mindestlautstärke
- Sound-Pfad
- Scan-Intervall

Das Einstellungsfenster (SwiftUI in einem normalen Fenster) bietet: Kalenderliste mit
Häkchen, Vorlaufzeit, Mindestlautstärke als Regler, Sound-Auswahl, die Mute-Liste mit
der Möglichkeit, Einträge wieder scharf zu schalten, sowie „Bei Anmeldung starten"
über `SMAppService`.

## Build

```
alarmooh/
├── Package.swift          # AlarmoohCore (lib) + alarmooh (exe) + Tests
├── Makefile               # make bundle / run / test
├── Resources/Info.plist   # LSUIElement, Bundle-ID, Kalender-Nutzungstext
├── Sources/
│   ├── AlarmoohCore/
│   └── alarmooh/
└── Tests/AlarmoohCoreTests/
```

`make bundle` baut Release, legt `Alarmooh.app` mit Info.plist an und signiert
ad-hoc. `make run` startet sie, `make test` läuft ohne Bundle.

EventKit gibt Kalenderdaten nur an ein signiertes App-Bundle mit Bundle-ID und
`NSCalendarsFullAccessUsageDescription` heraus; ein nacktes `swift build`-Binary
bekommt keinen Zugriff. Die Bundle-ID bleibt fest, damit macOS die einmal erteilte
Berechtigung wiedererkennt.

Bei Ad-hoc-Signatur ändert sich die Code-Identität mit jedem Build, weshalb macOS die
Kalenderfrage gelegentlich erneut stellt. Ein einmalig angelegtes selbstsigniertes
Zertifikat im Schlüsselbund behebt das, falls es stört.

## Tests

`swift test` gegen `AlarmoohCore`, ohne Xcode, mit `FakeCalendarSource`:

**Filter** — ganztägig entfällt, abgelehnt entfällt, stummgeschaltete Serie entfällt,
Termin aus abonniertem Kalender bleibt.

**Link-Extraktion** — Meet, Zoom, Teams aus URL-Feld, Notizen und Ort; ohne Link `nil`.

**Scheduler** — nächster Termin korrekt gewählt; dicht aufeinanderfolgende Termine;
verpasster Alarm wird nach dem Aufwachen nur innerhalb der Nachholfrist ausgelöst;
vergangene Termine lösen nicht aus.

Panel, Audio und Lautstärkesteuerung bleiben ungetestet und werden von Hand geprüft —
ein Mock-Gerüst lohnt dafür nicht.

## Bewusst weggelassen

Snooze, Auto-Timeout des Tons, mehrere Sounds pro Kalender, Kalender-Schreibzugriff,
Countdown in der Menüleiste, Google-Calendar-API als zweite Quelle.
