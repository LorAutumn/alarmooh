# alarmooh — Design

**Datum:** 2026-08-06
**Status:** umgesetzt; nach Implementierung und Review am Code nachgezogen

## Zweck

alarmooh ist eine eigenständige macOS-App in der Menüleiste. Sie liest den lokalen
Kalender, erkennt die nächsten wichtigen Termine und schlägt zwei Minuten vor Beginn
mit einem schleifenden Signalton Alarm. Der Ton läuft, bis der Nutzer ihn abstellt —
entweder durch Klick auf den Meeting-Link oder durch Stummschalten —, längstens
jedoch bis der Termin aufhört, aktuell zu sein.

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
| Alarmton | Datei in Application Support, ersatzweise ein zur Laufzeit erzeugter Ton | Die Tokioter Abfahrtsmelodien sind urheberrechtlich geschützt; privat abspielen ist unkritisch, im Repo verbreiten nicht. |
| Lautstärke | Systemlautstärke temporär anheben, danach wiederherstellen | Volle App-Lautstärke allein bleibt bei leisem Mac unhörbar. |
| Projektsetup | SPM plus `make app` | Git-freundlich und ohne Xcode baubar; EventKit verlangt trotzdem ein signiertes App-Bundle. |

## Architektur

Zwei Targets, damit die Logik ohne UI testbar bleibt.

### AlarmoohCore (Library, UI-frei)

- **`CalendarSource`** — Protokoll: liefert Termine im Fenster *jetzt bis +24 h*.
  Implementierungen: `EventKitCalendarSource` produktiv, `FakeCalendarSource` im Test.
- **`EventFilter`** — wendet die Opt-out-Regeln an.
- **`LinkExtractor`** — findet Meeting-URLs in Termindaten.
- **`AlarmScheduler`** — bestimmt den nächsten fälligen Alarm, den nächsten noch
  aktuellen Termin und das Ende eines laufenden Alarms.
- **`Settings`** — abonnierte Kalender, Mute-Liste, Vorlaufzeit, Mindestlautstärke, Sound-Pfad.

### alarmooh (Executable, AppKit mit SwiftUI-Views)

- **`StatusItemController`** — Menüleisten-Icon und Menü.
- **`AlarmPanelController`** — das schwebende Alarm-Fenster.
- **`AlarmPlayer`** — schleifende Wiedergabe des Alarmtons, bis er abgestellt wird.
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
2. Stummgeschaltetes entfällt: einzelnes Vorkommen über seine Vorkommens-Kennung,
   ganze Serie über `calendarItemExternalIdentifier`, womit alle künftigen Vorkommen
   still sind.
3. Grundsätzlich ausgeblendet, weil ein Alarm dort sinnlos ist:
   - ganztägige Termine — kein sinnvoller Startzeitpunkt,
   - abgesagte Termine,
   - explizit abgelehnte Termine.

   Zugesagte und unbeantwortete Termine alarmieren beide.

### Vorkommens-Kennung

Ein Vorkommen wird **nicht** allein über `eventIdentifier` identifiziert. Bei
Serienterminen gehört dieser Wert der ganzen Serie: Alle Vorkommen teilen sich
denselben. Am echten Kalender des Nutzers gemessen ergaben 40 Termine nur 21
verschiedene Kennungen.

Die Kennung ist deshalb das Paar aus `eventIdentifier` und dem Beginn des
Vorkommens, geschrieben als ganze Sekunden seit 1970 — damit ist sie bei jedem Scan
bitgleich und unabhängig von Locale, Zeitzone und Fließkomma-Formatierung. Ohne den
Startzeitpunkt würde ein einmal weggeklickter Alarm die komplette Serie stummschalten,
und „dieses eine Vorkommen" wäre nicht mehr von „die ganze Serie" zu unterscheiden.
Bitte nicht vereinfachen.

Apple dokumentiert `eventIdentifier` ausdrücklich als über eine Synchronisation hinweg
veränderlich. Wird ein Termin anderswo bearbeitet, kann eine Stummschaltung oder ein
abgestellter Alarm dadurch verlorengehen.

### Planung

Der Scheduler nimmt den nächsten Termin der gefilterten Liste und setzt einen Timer
auf `Start − Vorlaufzeit` (Standard: 2 Minuten, einstellbar). Nach jedem Alarm und
jedem Scan wird neu gesetzt.

Liegen zwei Termine dicht beieinander, überschreibt der zweite den laufenden Alarm
nicht. Ob er danach noch kommt, entscheidet dieselbe Regel wie überall: Alarmiert wird
ein Termin nur, solange er noch nicht begonnen hat oder höchstens `catchUpGrace`
(Standard: 120 Sekunden) zurückliegt. Wird der erste Alarm später abgestellt, entfällt
der zweite still.

Das ist keine Panne, sondern dieselbe Regel, die verhindert, dass ein zehn Minuten
alter Termin nach dem Aufklappen des Deckels noch losschreit. Wer ein längeres Fenster
möchte, stellt `catchUpGrace` hoch.

### Wann ein Termin aufhört, aktuell zu sein

`catchUpGrace` nach seinem Beginn — und das gilt an allen drei Stellen, an denen die
Frage auftaucht:

- Es wird kein Alarm mehr für ihn geplant (`nextAlarm`).
- Er verschwindet aus dem Menü: `nextRelevantEvent` liefert dann den übernächsten.
  Das ist nötig, weil EventKit auf ein Zeitfenster alles zurückgibt, was es
  überlappt — eine seit einer Viertelstunde laufende Besprechung steht sonst als
  frühester Termin weiter unter „Nächster: …".
- Ein laufender Alarm stellt sich selbst ab (`alarmEndDate`).

Beide Menü-Funktionen sind dieselbe Regel wie beim Alarm, nur ohne die Pause: Wer die
Alarme abgestellt hat, will trotzdem sehen, was ansteht, und beitreten können.
`nextAlarm` ist deshalb über `nextRelevantEvent` definiert — es gibt genau eine
Definition von „nächster Termin", Menü und Alarm können nicht auseinanderlaufen.

Damit das Menü nicht bis zum nächsten Sicherheitstakt veraltet dasteht, setzt der
Koordinator einen einzigen Timer auf genau diesen Ablaufzeitpunkt, der nichts weiter
tut als das Menü neu aufzubauen. Kein Takt, keine Schleife: Der Timer wird bei jedem
Neuaufbau verworfen und neu gestellt.

### Nur bei aktivem Rechner

Schläft der Rechner oder ist der Deckel geschlossen, feuert kein Alarm; alarmooh
weckt den Rechner auch nicht. Geprüft wird beim Auslösen über `CGDisplayIsAsleep`;
läuft der Timer währenddessen ab, verfällt der Alarm und wird beim Aufwachen neu
bewertet. Die Aufwach-Benachrichtigungen von `NSWorkspace` stoßen dafür einen Scan an.

Beim Aufwachen wird ein verpasster Alarm nur nachgeholt, wenn der Termin noch nicht
begonnen hat oder höchstens `catchUpGrace` (Standard: 2 Minuten) zurückliegt. Alles
Ältere verfällt still.

### Meeting-Link

Gesucht wird in dieser Reihenfolge: URL-Feld des Termins, Notizen, Ortsfeld.
Als Anbieter erkannt werden Google Meet, Zoom, Zoom Gov, Teams, Whereby, Webex,
GoToMeeting, Jitsi, BlueJeans, Chime, RingCentral, Around, Discord und Slack,
ersatzweise die erste beliebige `http(s)`-URL. Ohne Fund fehlt im Panel der
Beitreten-Knopf.

Drei Regeln greifen davor, weil der Knopf „Beitreten" heißt und den Alarm abstellt —
ein Abmeldelink an dieser Stelle wäre fatal:

- Was erkennbar kein Beitreten-Link ist, fällt zuerst weg: Abmelde- und
  Opt-out-Adressen, Einwahlnummern, Hilfeseiten, Links auf Besprechungsoptionen.
- HTML-Entities aus Outlook-Einladungen werden aufgelöst; sonst bricht ein
  Zoom-Link mit `&amp;` im Parameterteil beim Öffnen ab.
- Übernommen wird nur, was im Text tatsächlich mit `http://` oder `https://` begann.
  Der Link-Detektor erkennt sonst auch eine bloß erwähnte Domain, und die stünde dann
  auf dem Beitreten-Knopf.

Bekannte Grenze: Eine URL, die ein Mailprogramm über zwei Zeilen umgebrochen hat, wird
nicht zusammengesetzt.

## Menüleiste, Alarm-Fenster, Ton

### Menüleisten-Icon

Ein Template-Symbol (Glocke), das im Alarmzustand die Farbe wechselt. Das Menü zeigt
den nächsten überwachten Termin mit Uhrzeit („Nächster: … um …", sonst „Kein
überwachter Termin") sowie „Einstellungen…" und „alarmooh beenden".
Kein Dock-Icon und kein App-Switcher-Eintrag — geregelt über `LSUIElement`.

Gezeigt wird nur ein Termin, der noch aktuell ist: Läuft er länger als `catchUpGrace`,
rückt der übernächste nach — von selbst, ohne dass man das Menü aufklappen muss.

Zum nächsten Termin kommen zwei Aktionen dazu:

- **Beitreten (Alarm entfällt)** — nur, wenn für den Termin ein Link gefunden wurde.
  Öffnet ihn und legt dieses eine Vorkommen still, damit frühes Beitreten nicht später
  doch noch angeschrien wird.
- **Für diesen Termin nicht alarmieren** — immer vorhanden, solange es einen nächsten
  Termin gibt. Betrifft nur dieses eine Vorkommen; künftige der Serie bleiben scharf.

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
- **Diesen Termin nicht alarmieren** — schreibt die Vorkommens-Kennung in `mutedEventIDs`.
  Immer vorhanden, auch bei einmaligen Terminen. Betrifft nur dieses eine Vorkommen.
- **Diese Serie nie wieder** — schreibt die Serien-ID in `mutedSeriesIDs`. Nur, wenn der
  Termin zu einer Serie gehört. Betrifft alle künftigen Vorkommen.

Die beiden Stummschalt-Aktionen stehen nebeneinander, damit der Unterschied „nur dieses
Vorkommen" gegen „alle künftigen" beim Lesen sofort da ist.

Abgestellt wird der Alarm ausschließlich über diese Knöpfe. Sie funktionieren, ohne dass
das Fenster den Fokus übernimmt.

`ESC` und ein Klick aufs Menüleisten-Icon tun es nicht — beides war vorgesehen und ist
technisch nicht möglich:

- Das Panel ist ein `nonactivatingPanel` und wird mit `orderFrontRegardless()`
  gezeigt. Es wird nie Key-Window, also feuert SwiftUIs
  `keyboardShortcut(.cancelAction)` dort nie.
- Sobald ein `NSStatusItem` ein Menü hat, öffnet ein Klick aufs Icon das Menü. Die
  Button-Action läuft dann gar nicht mehr an.

### Ton und Lautstärke

`AVAudioPlayer` mit `numberOfLoops = -1`: Der Ton wiederholt sich, bis er abgestellt
wird. Ein Snooze gibt es nicht.

Abgestellt wird er auf zwei Wegen. Normalerweise vom Nutzer — Beitreten, Stumm,
Wegdrücken, Pausieren. Tut er nichts, hört der Ton von selbst auf, sobald der Termin
aufhört, aktuell zu sein, also `catchUpGrace` nach seinem Beginn. Beim Standard-Vorlauf
und der Standard-Nachfrist läutet ein regulärer Alarm damit vier Minuten.

Eine Untergrenze gibt es trotzdem: frühestens 60 Sekunden, nachdem der Ton begonnen
hat. Ein nachgeholter Alarm kann losgehen, wenn der Termin schon 1:58 läuft; die
strenge Regel ließe ihn dann zwei Sekunden läuten — ein Piepser, den der Nutzer genau
in dem Fall verpasst, für den die Nachholfrist überhaupt da ist.

Die Selbstabschaltung nimmt denselben Weg wie ein Klick auf „Stumm": Ton aus, Panel
zu, Icon wieder normal, und das Vorkommen wird als erledigt vermerkt — ohne den
Vermerk fiele der Termin sofort wieder in die Nachholfrist und läutete erneut. Endet
der Alarm auf einem anderen Weg, wird der Timer verworfen; er darf nie in einen
späteren Alarm hineinfeuern.

Parallel setzt `SystemVolumeController` per CoreAudio die Ausgabelautstärke auf den
eingestellten Mindestwert und hebt eine Stummschaltung auf. Der vorherige Zustand
wird gemerkt und beim Stoppen sowie beim Beenden der App zurückgeschrieben.
Zusätzlich wird er auf Platte geschrieben, damit ein Absturz während des Alarms die
Lautstärke nicht dauerhaft oben stehen lässt — beim nächsten Start wird sie
wiederhergestellt.

### Alarmton-Datei

Die App nutzt die Audiodatei in `~/Library/Application Support/alarmooh/`. Der Nutzer
legt sie dort ab oder wählt sie einmalig im Einstellungsfenster. Im Repository liegt
keine Audiodatei; der Ersatzton wird beim ersten Alarm erzeugt und daneben abgelegt.

Der Ersatzton besteht aus fünf aufsteigenden Tönen einer Pentatonik — E5, G5, A5, C6,
D6 —, die sich überlappen und zusammen 2,4 Sekunden ergeben. Jede Note ist ein Sinus
plus ein leiser zweiter Oberton, beide exponentiell abklingend; alle Noten werden
summiert und die Summe auf Spitze 0,85 normalisiert, gemessener RMS 0,17.

Die Dringlichkeit liefert die Wiederholung, nicht die Klangfarbe: Der Ton wiederholt
sich minutenlang, bis er abgestellt wird, und darf deshalb freundlich klingen. Die
frühere Fassung hielt zwei Töne fast durchgängig auf voller Amplitude und tauschte
damit ein Glöckchen gegen eine Sirene — der falsche Tausch.

Jede Note bekommt neben dem kurzen Einsatz eine eigene Ausblendung von 90 ms. Die muss
bleiben: Ohne sie bricht die Note mitten im Ausklingen bei rund 11 % Amplitude ab, und
das knackt hörbar. Messbar ist es an der zweiten Differenz des Signals, deren Maximum
ohne Rampe das 15-fache des Mittelwerts erreichte, und zwar genau an den Notenenden;
mit Rampe bleiben 9 übrig, also nur noch die natürliche Krümmung der hohen Töne.

Weil der Ersatzton nur erzeugt wird, wenn die Datei noch fehlt, heißt sie seit dieser
Fassung `fallback-tone-2.wav`; sonst behielte jeder, der den alten Ton schon einmal
gehört hat, ihn für immer. Eine liegengebliebene `fallback-tone.wav` wird dabei
gelöscht.

Hintergrund: Die Tokioter Abfahrtsmelodien sind komponierte, geschützte Werke. Privat
abspielen ist unkritisch, sie ins Repository zu legen und weiterzugeben wäre es nicht.

## Einstellungen und Persistenz

`settings.json` in `~/Library/Application Support/alarmooh/` — lesbar und im Test
beschreibbar, statt `UserDefaults`:

- abonnierte Kalender-IDs
- Mute-Liste (Vorkommens-Kennungen und Serien-IDs)
- Vorlaufzeit
- Mindestlautstärke
- Sound-Pfad
- Scan-Intervall
- Nachholfrist (`catchUpGrace`)

Die Datei ist ausdrücklich von Hand editierbar, und das hat zwei Konsequenzen, die im
Code stehen müssen:

- Swifts synthetisiertes `Codable` ignoriert Standardwerte und macht jeden
  nicht-optionalen Schlüssel zur Pflicht. Ein einziger fehlender Schlüssel hätte die
  ganze Datei unlesbar gemacht — und mit leerer Liste abonnierter Kalender alarmiert
  nichts mehr. `Settings` dekodiert deshalb jeden Schlüssel einzeln mit Rückfall auf
  den Standardwert und klemmt unsinnige Werte (negative Vorlaufzeit, Lautstärke
  außerhalb 0…1, Scan-Intervall unter einer Minute).
- `SettingsStore` unterscheidet die fehlende von der defekten Datei. Fehlt sie, gelten
  Standardwerte. Ist sie da, aber unlesbar, wird sie nicht überschrieben — eine von
  Hand geschriebene Konfiguration soll ein Tippfehler nicht vernichten. Der Zustand
  ist über `lastLoadFailed` abfragbar, damit der Nutzer gewarnt werden kann, statt
  still ohne Abos weiterzulaufen.

Das Einstellungsfenster (SwiftUI in einem normalen Fenster) bietet: Kalenderliste mit
Häkchen, Vorlaufzeit, Mindestlautstärke als Regler, Sound-Auswahl, die Mute-Liste mit
der Möglichkeit, Einträge wieder scharf zu schalten, sowie „Bei Anmeldung starten"
über `SMAppService`.

## Build

```
alarmooh/
├── Package.swift          # AlarmoohCore (lib) + alarmooh (exe) + Tests
├── Makefile               # make app / install / uninstall / run / test / clean
├── Scripts/
│   ├── bundle.sh          # Release bauen und .build/Alarmooh.app zusammensetzen
│   └── Info.plist         # LSUIElement, Bundle-ID, Kalender-Nutzungstext
├── Sources/
│   ├── AlarmoohCore/
│   └── alarmooh/
└── Tests/AlarmoohCoreTests/
```

`make app` ruft `Scripts/bundle.sh` auf: Release bauen, `.build/Alarmooh.app` mit
Info.plist anlegen, ad-hoc signieren. Das Bundle liegt im versteckten `.build/`, weil
Spotlight Dot-Ordner nicht indexiert und die App sonst doppelt im Launchpad stünde.
`make install` kopiert es nach `/Applications`, `make run` startet es von dort aus
`.build/` heraus ohne Installation — bewusst über `open`, weil erst dadurch
LaunchServices das Bundle registriert, woran die Kalenderberechtigung hängt.
`make uninstall` entfernt App, `~/Library/Application Support/alarmooh` und die
erteilte Kalenderberechtigung. `make test` läuft ohne Bundle.

EventKit gibt Kalenderdaten nur an ein signiertes App-Bundle mit Bundle-ID und
`NSCalendarsFullAccessUsageDescription` heraus; ein nacktes `swift build`-Binary
bekommt keinen Zugriff. Die Bundle-ID (`io.github.lorautumn.alarmooh`) bleibt fest, damit macOS
die einmal erteilte Berechtigung wiedererkennt.

Bei Ad-hoc-Signatur ändert sich die Code-Identität mit jedem Build, weshalb macOS die
Kalenderfrage gelegentlich erneut stellt. Ein einmalig angelegtes selbstsigniertes
Zertifikat im Schlüsselbund behebt das, falls es stört.

Stolperstein beim Übersetzen: `SystemVolumeController` braucht neben `CoreAudio` auch
`import AudioToolbox`. `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` liegt
dort, nicht in `CoreAudio`.

## Tests

`swift test` gegen `AlarmoohCore`, ohne Xcode, mit `FakeCalendarSource`:

**Filter** — ganztägig entfällt, abgelehnt entfällt, stummgeschaltete Serie entfällt,
Termin aus abonniertem Kalender bleibt.

**Link-Extraktion** — Meet, Zoom, Teams aus URL-Feld, Notizen und Ort; ohne Link `nil`;
Anbieter schlägt Abmeldelink; HTML-Entities; bloße Domain im Fließtext ist kein Link.

**Scheduler** — nächster Termin korrekt gewählt; dicht aufeinanderfolgende Termine;
verpasster Alarm wird nach dem Aufwachen nur innerhalb der Nachholfrist ausgelöst;
vergangene Termine lösen nicht aus. Dazu der nächste noch aktuelle Termin fürs Menü —
ein länger laufender fällt heraus, ein gerade begonnener bleibt, ein erledigter wird
übersprungen, und pausiert bleibt er sichtbar, obwohl kein Alarm mehr geplant wird.
Und das Ende eines laufenden Alarms: regulär Beginn plus Nachfrist, beim nachgeholten
Alarm mindestens eine Minute ab jetzt.

**Einstellungen** — leeres und unvollständiges JSON ergeben Standardwerte, unbekannte
Schlüssel stören nicht, unsinnige Werte werden geklemmt, eine defekte Datei wird
gemeldet und nicht überschrieben.

**Ersatzton** — abspielbar, und die Samples belegen Pegel und klickfreie Ränder. Der
Test fällt, sobald jemand den Ton leise dreht; zusätzlich prüft er über die zweite
Differenz, dass die Ausblendung je Note nicht wegrationalisiert wurde.

Panel, Menüleiste und die CoreAudio-Anbindung bleiben ungetestet und werden von Hand
geprüft — ein Mock-Gerüst lohnt dafür nicht. Der Lautstärke-Snapshot, der einen
Absturz überleben muss, ist dagegen getestet.

## Bewusst weggelassen

Snooze, ein eigener einstellbarer Auto-Timeout des Tons (das Ende hängt an
`catchUpGrace` und braucht keinen zweiten Wert), eine Meldung beim Selbstabschalten,
mehrere Sounds pro Kalender, Kalender-Schreibzugriff, Countdown in der Menüleiste,
Google-Calendar-API als zweite Quelle.

## Bekannte Grenzen

Was die Implementierung nicht abdeckt:

- Abgestellte Alarme merkt sich nur der laufende Prozess. Startet die App innerhalb
  der Vorlaufzeit neu, kann derselbe Alarm ein zweites Mal kommen.
- `events(matching:)` von EventKit ist synchron und läuft auf dem Hauptthread.
  Gemessen 5–48 ms für das 24-Stunden-Fenster — bei dieser Größenordnung
  unproblematisch, aber nach oben nicht begrenzt.
- Die Ad-hoc-Signatur ändert die App-Identität bei jedem Build, macOS kann die
  Kalenderberechtigung deshalb erneut abfragen.
- Abgesagt wird über den Teilnehmer mit `isCurrentUser` erkannt. Am Kalender des
  Nutzers gemessen hatten 4 von 40 Terminen Teilnehmer, aber keinen solchen Treffer;
  eine Absage unter einer zweiten Adresse bleibt dann unbemerkt.
- Wird das Ausgabegerät gewechselt, während der Alarm läuft, bleibt das ursprüngliche
  Gerät auf der angehobenen Lautstärke stehen.
- `mutedEventIDs` wächst unbegrenzt. Jedes stummgeschaltete Vorkommen legt einen
  dauerhaften Eintrag an, dessen Kennung den Startzeitpunkt enthält; nichts entfernt
  Einträge, deren Termin längst vorbei ist. In der Praxis sind das Bytes pro Jahr, aber
  die Mute-Liste im Einstellungsfenster füllt sich langsam mit toten Einträgen.
- Die Mute-Liste im Einstellungsfenster zeigt die rohen Vorkommens-Kennungen
  (etwa `…|1754485200`). Für einen Menschen, der entscheiden will, was er wieder scharf
  schaltet, sind die nicht lesbar.
