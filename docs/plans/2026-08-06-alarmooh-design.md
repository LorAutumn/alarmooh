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

- **`CalendarSource`** — Protokoll: liefert Termine im Fenster *jetzt bis +24 h*, und
  zwar nur aus den übergebenen Kalendern (`events(from:to:calendarIDs:)`). Der Umfang
  ist ein Parameter und kein Zustand der Quelle, nicht optional und ohne Vorgabewert:
  Es gibt keinen Wert mehr, der „alle Kalender" bedeutet. Implementierungen:
  `EventKitCalendarSource` produktiv, `FakeCalendarSource` im Test.
- **`EventFilter`** — wendet die Opt-out-Regeln an.
- **`LinkExtractor`** — findet Meeting-URLs in Termindaten. `isKnownProvider` ist
  öffentlich, damit das Alarm-Panel vor einem unbekannten Host warnen kann; die Liste
  `knownHosts` bleibt intern.
- **`AlarmScheduler`** — bestimmt den nächsten fälligen Alarm, den nächsten noch
  aktuellen Termin und das Ende eines laufenden Alarms.
- **`OccurrenceID`** — Aufbau, Zerlegung und Verfallsregel der Vorkommens-Kennung.
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
   │  Scan-Fenster: jetzt … +24 h, nur abonnierte Kalender
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

Der Text im Systemdialog (`NSCalendarsFullAccessUsageDescription`) benennt den Umfang
statt nur den Zweck: gelesen werden ausschließlich die Termine der ausgewählten
Kalender, geändert wird dort nichts, den Vollzugriff verlangt macOS mangels reinem
Lesezugriff, und dauerhaft gespeichert wird davon nur, welche Termine stummgeschaltet
sind. Wer der Frage zustimmen soll, muss wissen, worauf.

### Scan-Auslöser

Ausgelesen wird immer nur das Fenster *jetzt bis +24 h*, nie der ganze Kalender — und
darin nur die abonnierten Kalender. Ist das Abo leer oder existiert keiner der
gespeicherten Kalender mehr, wird EventKit gar nicht erst gefragt; `predicateForEvents`
versteht `calendars: nil` als *alle* Kalender, aus „nichts alarmiert" dürfte also
niemals „alles lesen" werden. Drei Auslöser:

1. `EKEventStoreChanged` — das System meldet Änderungen von sich aus, kein Polling nötig.
2. Ein Sicherheitstakt alle 30 Minuten (einstellbar).
3. Aufwachen aus dem Ruhezustand — beobachtet über `didWake` und `screensDidWake`,
   was in der Praxis zwei Scans ergibt (siehe „Bekannte Grenzen").

Der Scan-Takt hat nichts mit der Alarmgenauigkeit zu tun. Aus dem Scan entsteht
genau ein Timer auf den exakten Auslösezeitpunkt. Zwischen zwei Alarmen ist der
Prozess untätig.

### Filterregeln (Opt-out)

1. Nur Termine aus abonnierten Kalendern. Das steht schon in der Abfrage; die Prüfung
   im Speicher bleibt bewusst als zweite Verteidigungslinie stehen — eine Lücke in der
   Abfrage darf niemals einen fremden Kalender alarmieren.
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

Format, Zerlegung und Verfallsregel stehen an einer einzigen Stelle, in `OccurrenceID`
im Kern. Gelesen wird die Kennung an mehreren: Das Einstellungsfenster zeigt den
Zeitpunkt an, und das Aufräumen abgelaufener Stummschaltungen braucht ihn ebenfalls.
Zwei Parser nebeneinander wären die Stelle, an der beide Seiten später auseinander
laufen. Zerlegt wird am *letzten* Trennzeichen, weil der `eventIdentifier` eine fremde
Zeichenkette ist, in der ein „|" vorkommen darf.

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
überwachter Termin"), den Schalter „Alarme pausieren" / „Alarme fortsetzen" — bei
laufender Pause dazu ganz oben die graue Zeile „Alarme sind ausgeschaltet" — sowie
„Einstellungen…" und „alarmooh beenden".
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
- **`Ziel: <Host>`** — unter den beiden Knöpfen, sobald ein Link vorhanden ist. Titel,
  Notizen und URL stammen aus einer Einladung, die jeder schicken kann; unter laufendem
  Alarmton wird „Beitreten" im Reflex geklickt, also muss vorher sichtbar sein, wohin er
  führt. Gezeigt wird nur der Host — die volle URL wäre für 320 pt zu lang und schöbe
  genau den beurteilbaren Teil aus dem Blick; sie steht als Tooltip dahinter. Gekürzt
  wird vorne, weil die aussagekräftigen Labels eines Hosts hinten stehen.
- **„Unbekannter Anbieter — prüfe die Adresse."** — eine zusätzliche orange Zeile, wenn
  der Host zu keinem bekannten Meeting-Anbieter gehört (`LinkExtractor.isKnownProvider`).
  Ein unbekannter Host ist kein Beweis für einen Angriff: Ein firmeninternes Meeting
  liegt zu Recht auf einer eigenen Domain. Deshalb nur ein Hinweis, der Knopf wird nie
  gesperrt. Die Warnung steht im Text und nicht in der Farbe allein, sonst trüge sie für
  Farbfehlsichtige nichts.
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
eingestellten Mindestwert und hebt eine Stummschaltung auf. Der vorherige Zustand wird
gemerkt und beim Stoppen zurückgeschrieben; zusätzlich liegt er in
`volume-snapshot.json`, damit ein Absturz während des Alarms die Lautstärke nicht
dauerhaft oben stehen lässt.

Das Anheben ist nur unter der Zusage vertretbar, dass es zurückgenommen wird. Drei
Stellen sichern das ab:

- `applicationWillTerminate` stellt erst das Vorhören ab, dann den Alarm — denselben
  Weg wie ein Klick auf „Stumm" —, und schreibt zuletzt einen noch liegenden
  Schnappschuss zurück. „alarmooh beenden" steht im Menü und ist die naheliegendste
  Reaktion auf einen Alarm, den man loswerden will; vorher endete der Prozess, ohne
  dass je ein `restore()` lief.
- Die Wiederherstellung nach einem Absturz läuft beim Start bedingungslos und **vor**
  der Abfrage der Kalenderberechtigung. Sie hing vorher im Erfolgszweig hinter
  `requestAccess()`: Wurde der Zugriff verweigert oder entzogen, blieb die Lautstärke
  dauerhaft oben. Mit dem Kalender hat das Zurücksetzen nichts zu tun — es liest eine
  Datei und schreibt höchstens eine Lautstärke.
- Der Schnappschuss merkt sich das Ausgabegerät als `kAudioDevicePropertyDeviceUID`,
  nicht als `AudioObjectID`: Die numerischen IDs vergibt CoreAudio pro Systemstart neu.
  Zurückgeschrieben wird nur auf dasselbe Gerät. Der Fall, um den es geht: Lautsprecher
  auf 100 %, Alarm läutet, der Nutzer setzt Kopfhörer auf — ein blindes `restore()`
  schriebe die 1.0 des Lautsprechers ins Ohr.

Passt das Gerät nicht, wird nichts geschrieben und die Datei bleibt liegen. Sie ist
dann das Einzige, was den alten Zustand kennt: Liegt das Gerät beim nächsten Start
wieder vorn, wird es dort leiser gedreht. Ein Schnappschuss aus einer älteren Version
kennt kein Gerät und wird weiterhin angewandt — nichts zu tun wäre schlechter als der
bisherige Stand, und der bisherige Stand ist genau dieses blinde Zurückschreiben.

Was das nicht abdeckt: Lässt sich das aktuelle Gerät nicht benennen, obwohl der
Schnappschuss eines nennt, wird nicht zurückgeschrieben, sondern auf den nächsten
Start vertagt — es ist gerade nicht feststellbar, dass es dasselbe Gerät ist. Und der
Schnappschuss wird zwar vor dem Anheben geschrieben, aber nur mit `try?`; scheitert das
Schreiben, hebt alarmooh trotzdem an und kennt den alten Stand nur im Speicher. Ein
harter Abbruch in diesem Zustand lässt die Lautstärke oben, ohne dass irgendetwas davon
wüsste.

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
- Pause-Schalter und „Bei Anmeldung starten"

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

Stummgeschaltete **Vorkommen** verfallen. Bei jedem Scan fallen Einträge weg, deren
Startzeitpunkt länger als sieben Tage zurückliegt (`OccurrenceID.mutedRetention`); ohne
das wüchse `mutedEventIDs` unbegrenzt, weil jedes weggeklickte Vorkommen einen Eintrag
anlegt und nie einer entfernt wird. Drei Regeln dazu:

- Die Grenze gehört noch dazu — „höchstens sieben Tage alt", dieselbe Lesart wie bei
  `catchUpGrace`.
- Was sich nicht lesen lässt, bleibt stehen. Eine unbekannte Kennung wegzuwerfen hieße,
  etwas wieder scharf zu schalten, das der Nutzer ausdrücklich abgestellt hat.
- Stummgeschaltete **Serien** werden nie angefasst. Sie tragen keinen Zeitpunkt und
  gelten auf Dauer, bis der Nutzer sie im Fenster wieder scharf schaltet.

Geschrieben wird die Datei dabei nur, wenn tatsächlich etwas wegfällt — sonst hätte
jeder Scan eine Schreiblast, alle 30 Minuten und bei jeder Kalenderänderung. Bei
defekter Datei läuft das Aufräumen gar nicht, dort wird grundsätzlich nicht geschrieben.

Das Einstellungsfenster (SwiftUI in einem normalen Fenster) bietet: Kalenderliste mit
Häkchen, „Nächste Termine", Vorlaufzeit, Mindestlautstärke als Regler samt Testton,
Sound-Auswahl, die Mute-Liste mit der Möglichkeit, Einträge wieder scharf zu schalten,
sowie „Bei Anmeldung starten" über `SMAppService`.

**Nächste Termine** listet die nächsten zehn Termine der abonnierten Kalender, gesucht
bis 60 Tage voraus — bewusst viel weiter als das 24-Stunden-Fenster des Alarm-Scans, denn
wer alle zwei Wochen einen Serientermin hat, findet den zehnten sonst nie. Je Zeile
Titel, Wochentag, Datum, Uhrzeit und Kalendername, dazu ein Schalter für das einzelne
Vorkommen und bei Serienterminen ein zweiter für die ganze Serie.

Der Abschnitt ist die einzige Stelle, an der ein Termin vorab stillgelegt werden kann.
Ohne ihn ließe sich ein Serientermin nur stummschalten, während er läutet — man müsste
den Alarm also erst über sich ergehen lassen, um ihn loszuwerden. Gefiltert wird
mit `selectable` statt `alarmable`, damit stummgeschaltete Termine stehen bleiben; sonst
käme man an den Schalter zum Wiedereinschalten gar nicht heran. Ist die Serie stumm, ist
der Schalter des Vorkommens bedeutungslos: Er zeigt „aus", lässt sich nicht bedienen und
die Zeile schreibt den Grund aus, statt ein „an" vorzugaukeln, das nichts bewirkt.
Geschaltet wird über den Koordinator, also denselben Weg wie aus Menü und Alarmpanel,
samt Abstellen eines gerade laufenden Alarms.

**„Ton testen"** unter dem Lautstärkeregler spielt den Alarmton genau einmal und hebt
die Systemlautstärke dafür genauso an wie ein echter Alarm — sonst hörte man irgendeinen
Pegel, nur nicht den eingestellten. Vorgehört wird mit dem Stand aus dem Fenster und
nicht mit dem gespeicherten, weil der Regler erst beim Loslassen schreibt. Während der
Ton läuft, heißt der Knopf „Test stoppen"; er fällt von selbst zurück, wenn der Ton zu
Ende ist. Der Stand kommt dafür vom Player und nie vom Klick — nur der weiß, wann der
Ton aufhört, und ein geratener Timer läge bei jedem eigenen Alarmton daneben. Läuft
gerade ein echter Alarm, passiert nichts: Der Alarm besitzt den Lautstärke-Schnappschuss.

## Build

```
alarmooh/
├── Package.swift          # AlarmoohCore (lib) + alarmooh (exe) + Tests
├── Makefile               # make app / install / uninstall / run / test / clean
├── LICENSE                # MIT, Lorenz Herbst, 2026
├── Scripts/
│   ├── bundle.sh          # Release bauen, .build/Alarmooh.app zusammensetzen, signieren
│   ├── Info.plist         # LSUIElement, Bundle-ID, Kalender-Nutzungstext
│   └── alarmooh.entitlements  # com.apple.security.personal-information.calendars
├── Sources/
│   ├── AlarmoohCore/
│   └── alarmooh/
└── Tests/AlarmoohCoreTests/
```

Der Code steht unter der MIT-Lizenz (`LICENSE`, Lorenz Herbst, 2026). Eine selbst
hinterlegte Tondatei ist davon nicht erfasst — sie liegt in Application Support und
nicht im Repository.

`make app` ruft `Scripts/bundle.sh` auf: Release bauen, `.build/Alarmooh.app` mit
Info.plist anlegen, signieren. Das Bundle liegt im versteckten `.build/`, weil
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

Signiert wird immer mit `--options runtime`, also mit Hardened Runtime, und mit
`--timestamp=none` (der Zeitstempeldienst braucht Netz und nützt nur bei einer
Notarisierung, die mit einem selbst ausgestellten Zertifikat ohnehin unmöglich ist).
Die Hardened Runtime ist hier der eigentliche Schutz: alarmooh läuft dauerhaft mit
erteiltem Kalender-Vollzugriff, und ohne sie kann sich jeder Prozess des angemeldeten
Nutzers an sie hängen (Task-Port) oder sie mit `DYLD_INSERT_LIBRARIES` neu starten und
den kompletten Kalender mitlesen — ohne eigene Nachfrage, weil die Berechtigung am
Bundle hängt und nicht am fremden Prozess. Geprüft: `codesign -dvvv` meldet
`flags=0x10002(adhoc,runtime)`, und `lldb -p` auf eine so signierte Kopie wird mit
„Not allowed to attach to process" abgewiesen.

Die Hardened Runtime kostet dafür eine Berechtigung. Für den Kalender verlangt macOS
unter ihr die Resource-Access-Berechtigung
`com.apple.security.personal-information.calendars` — nicht bloß als
App-Sandbox-Schlüssel, sondern als Bedingung der TCC-Policy. Sie steht in
`Scripts/alarmooh.entitlements`, und `bundle.sh` signiert mit
`--entitlements Scripts/alarmooh.entitlements`. Fehlt sie, lehnt tccd den Zugriff ohne
Rückfrage ab:

```
Prompting policy for hardened runtime; service: kTCCServiceCalendar requires
entitlement com.apple.security.personal-information.calendars but it is missing
```

Der Ausfall ist von außen nicht zu erkennen: Die App meldet „Kein Kalenderzugriff",
während die Systemeinstellungen den Kalender für sie weiterhin als erlaubt führen.
Wer die Datei als „ungenutzt" entfernt, bricht damit den Kalenderzugriff still.

Lehre aus dem Fehlschlag: Eine TCC-Policy lässt sich nur über einen Start via
LaunchServices prüfen, nicht über einen Start aus der Shell. TCC rechnet die Anfrage
der verantwortlichen Anwendung zu; wird der Prozess aus dem Terminal gestartet, ist das
das Terminal, und die Hardened-Runtime-Policy der App greift gar nicht erst. Die
ursprüngliche Prüfung startete die Testkopie so und sah den Fehler deshalb nicht. Für
jede Prüfung an Berechtigungen gilt: über `open` starten, sonst prüft man etwas anderes.

Die Signier-Identität wird in dieser Reihenfolge bestimmt:

1. `ALARMOOH_SIGN_IDENTITY`, unverändert an `codesign --sign` gereicht.
2. Sonst ein gültiges Code-Signing-Zertifikat aus dem Schlüsselbund, dessen Name
   `alarmooh` enthält. Gefunden über `security find-identity -v -p codesigning`,
   verwendet wird der Fingerabdruck und nicht der Name — der ist auch bei mehreren
   gleichnamigen Zertifikaten eindeutig.
3. Sonst ad hoc. Bewusst kein Fehler: Ohne Zertifikat muss der Build durchlaufen.

Welcher Fall gegriffen hat, meldet das Skript als „Signatur: …". Bei Ad-hoc-Signatur
ist die Code-Identität der cdhash des Binaries; der ändert sich mit jedem Build, macOS
sieht jedes Mal eine fremde App und stellt die Kalenderfrage erneut. Ein einmalig
angelegtes selbstsigniertes Zertifikat behebt genau das; die Schritte stehen im README.

Stolperstein beim Übersetzen: `SystemVolumeController` braucht neben `CoreAudio` auch
`import AudioToolbox`. `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` liegt
dort, nicht in `CoreAudio`.

## Tests

`swift test` gegen `AlarmoohCore`, ohne Xcode, mit `FakeCalendarSource`:

**Filter** — ganztägig entfällt, abgelehnt entfällt, stummgeschaltete Serie entfällt,
Termin aus abonniertem Kalender bleibt.

**Umfang der Abfrage** — die Quelle liefert nur Termine der genannten Kalender; eine
leere Menge und eine Kennung, die es nicht mehr gibt, liefern beide nichts statt alles;
Zeitfenster und Kalenderauswahl greifen zusammen.

**Vorkommens-Kennung** — Aufbau und Zerlegung sind umkehrbar, Bruchteile von Sekunden
fallen weg, zerlegt wird am letzten Trennzeichen; ohne oder mit unlesbarem Zeitstempel
gibt es keinen Zeitpunkt. Dazu der Verfall: älter als sieben Tage fällt weg, genau auf
der Grenze bleibt es stehen, eine Sekunde darüber nicht, Unlesbares und Serien bleiben
unberührt, und ohne Änderung kommt dieselbe Menge zurück — daran hängt, dass nicht bei
jedem Scan geschrieben wird.

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
Absturz überleben muss, ist dagegen getestet: Rundlauf mit Gerätekennung, eine Datei
aus einer älteren Version ohne dieses Feld bleibt lesbar, eine ohne Lautstärke gilt als
unbrauchbar, und derselbe Pegel auf einem anderen Gerät ist ein anderer Zustand.

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
- Ohne eigenes Zertifikat wird ad hoc signiert; dann ändert sich die App-Identität bei
  jedem Build und macOS fragt die Kalenderberechtigung erneut ab. Mit einem
  selbstsignierten Code-Signing-Zertifikat namens `alarmooh` im Schlüsselbund entfällt
  das.
- Abgesagt wird über den Teilnehmer mit `isCurrentUser` erkannt. Am Kalender des
  Nutzers gemessen hatten 4 von 40 Terminen Teilnehmer, aber keinen solchen Treffer;
  eine Absage unter einer zweiten Adresse bleibt dann unbemerkt.
- Wird das Ausgabegerät gewechselt, während der Alarm läuft, bleibt das ursprüngliche
  Gerät auf der angehobenen Lautstärke stehen: Die Wiederherstellung unterbleibt
  bewusst, bis dieses Gerät wieder das Standardgerät ist. Auf das neue Gerät wird dabei
  nie ein fremder Pegel geschrieben.
- Der Scan läuft häufiger als geplant. Vorgesehen sind rund zwei Durchläufe pro Stunde
  (Sicherheitstakt alle 30 Minuten), gemessen wurden etwa elf: `EKEventStoreChanged`
  feuert alle 7 bis 19 Minuten und wird nicht zusammengefasst, und beim Aufwachen laufen
  zwei Scans, weil sowohl `didWake` als auch `screensDidWake` beobachtet werden. Ein
  Entprellen wurde bewusst nicht eingebaut: Die Kosten liegen bei etwa einer Sekunde CPU
  pro Tag, die Beschränkung der Abfrage auf die abonnierten Kalender macht jeden Scan
  ohnehin billiger, und eine Verzögerung würde eine echte Kalenderänderung später
  ankommen lassen.
