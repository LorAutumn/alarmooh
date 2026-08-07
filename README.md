# alarmooh

## Was es ist

alarmooh ist eine eigenständige macOS-App in der Menüleiste. Sie liest über EventKit
den lokalen Kalender — also das, was Kalender.app ohnehin schon synchronisiert — und
schlägt standardmäßig zwei Minuten vor Terminbeginn mit einem schleifenden Signalton
Alarm. Ein schwebendes Panel unter dem Menüleisten-Icon bietet dazu den Meeting-Link
an: „Beitreten" öffnet ihn und stellt den Ton ab, „Stumm" stellt nur den Ton ab,
„Diesen Termin nicht alarmieren" legt dieses eine Vorkommen dauerhaft still und „Diese
Serie nie wieder" alle künftigen Vorkommen der Serie. Unter den Knöpfen steht, wohin
„Beitreten" führt: `Ziel: <Host>`, bei Bedarf vorne gekürzt, die vollständige URL als
Tooltip. Gehört der Host zu keinem bekannten Meeting-Anbieter, kommt in Orange
„Unbekannter Anbieter — prüfe die Adresse." dazu. Der Knopf bleibt trotzdem benutzbar:
Ein firmeninternes Meeting liegt zu Recht auf einer eigenen Domain und muss weiterhin
mit einem Klick erreichbar sein.

Auch ohne Alarm lässt sich der nächste Termin schon im Menü erledigen: Wurde ein Link
gefunden, öffnet ihn „Beitreten (Alarm entfällt)" und stellt denselben Termin still —
wer früh beitritt, wird hinterher nicht doch noch angeschrien. „Für diesen Termin nicht
alarmieren" tut dasselbe ohne Link; künftige Vorkommen der Serie bleiben scharf.

Kein Backend, kein Netzwerkzugriff, kein OAuth, keine Konten. Ein einzelner lokaler
Prozess, der zwischen zwei Alarmen nichts tut: aus jedem Kalender-Scan entsteht genau
ein Timer auf den exakten Auslösezeitpunkt.

## Voraussetzungen

- macOS 14 oder neuer (`Package.swift` setzt `.macOS(.v14)`, die Info.plist
  `LSMinimumSystemVersion 14.0`). Entwickelt und geprüft auf macOS 26.6.
- Swift 6 (geprüft mit Apple Swift 6.3.3).
- **Ein vollständiges Xcode ist nicht nötig, die Command Line Tools genügen.**

Genau deshalb hängt das Paket an `swift-testing`: Die Command Line Tools liefern weder
`XCTest` noch `Testing` mit, ein Testtarget ließe sich sonst gar nicht übersetzen.
Sollte irgendwann ein vollständiges Xcode installiert werden, kann diese Abhängigkeit
aus `Package.swift` verschwinden und `import Testing` auf die Version der Toolchain
zeigen.

Hinweis: Der Compiler warnt bei jedem `make test`, die Abhängigkeit sei überflüssig,
Swift Testing stecke inzwischen in der Toolchain. Für die reinen Command Line Tools
stimmt das nicht — ohne die Abhängigkeit endet der Build mit
`no such module 'Testing'`. Die Warnung ist hier also falsch und darf ignoriert werden.

## Bauen und starten

```
make app        # Release bauen, .build/Alarmooh.app zusammensetzen, signieren
make install    # dasselbe und nach /Applications kopieren
make run        # dasselbe und aus .build/ starten, ohne zu installieren
make test       # Tests gegen AlarmoohCore, ohne Bundle
make uninstall  # App, Konfiguration und Kalenderberechtigung entfernen
make clean      # .build löschen
```

Das Bundle entsteht im versteckten `.build/`, weil Spotlight Dot-Ordner nicht
indexiert — sonst stünde die App doppelt im Apps-Viewer beziehungsweise Launchpad.
`make install` kopiert es nach `/Applications`; erst dort arbeitet auch „Bei Anmeldung
starten" zuverlässig. `make uninstall` löscht neben der App auch
`~/Library/Application Support/alarmooh`, also die gesamte Konfiguration.

Ein nacktes `swift build`-Binary reicht nicht. EventKit gibt Kalenderdaten nur an ein
signiertes App-Bundle heraus, das eine Bundle-ID und den Schlüssel
`NSCalendarsFullAccessUsageDescription` mitbringt; ohne Bundle kommt schlicht kein
Kalender an. Die Bundle-ID (`io.github.lorautumn.alarmooh`) bleibt deshalb fest, damit
macOS die einmal erteilte Berechtigung wiedererkennt.

`make app` signiert immer mit `--options runtime`, also mit eingeschalteter Hardened
Runtime. Das ist hier kein Formalismus: alarmooh läuft dauerhaft mit erteiltem
Kalender-Vollzugriff, und ohne Hardened Runtime kann sich jeder andere Prozess des
angemeldeten Nutzers an sie hängen und über sie den gesamten Kalender mitlesen — ohne
eigene Nachfrage, weil die Berechtigung am Bundle hängt. Mit Hardened Runtime wird
etwa ein `lldb -p` auf den laufenden Prozess mit „Not allowed to attach to process"
abgewiesen. Entitlements braucht die App dafür keine.

Die Signier-Identität sucht `Scripts/bundle.sh` in dieser Reihenfolge:

1. `ALARMOOH_SIGN_IDENTITY` — ist die Umgebungsvariable gesetzt, wird ihr Wert
   unverändert an `codesign --sign` gereicht. Damit lässt sich jede beliebige Identität
   erzwingen, etwa ein anders benanntes Zertifikat oder ein Fingerabdruck.
2. Sonst ein gültiges Code-Signing-Zertifikat aus dem Schlüsselbund, dessen Name
   `alarmooh` enthält (`security find-identity -v -p codesigning`). Signiert wird dann
   über den Fingerabdruck, nicht über den Namen — der ist auch bei mehreren
   gleichnamigen Zertifikaten eindeutig.
3. Sonst ad hoc (`--sign -`). Das ist kein Fehler: Ohne Zertifikat muss der Build
   weiterhin durchlaufen.

Welcher Fall gegriffen hat, schreibt das Skript zum Schluss als „Signatur: …" hin. Bei
Ad-hoc-Signatur ist die Code-Identität der cdhash des Binaries; der ändert sich bei
jedem Build, macOS sieht dann jedes Mal eine fremde App und fragt die
Kalenderberechtigung erneut ab. Genau das behebt ein eigenes Zertifikat.

## Signierzertifikat anlegen

Einmalig, danach hören die wiederkehrenden Kalenderabfragen auf:

1. Schlüsselbundverwaltung öffnen.
2. Menü „Schlüsselbundverwaltung" → „Zertifikatsassistent" → „Zertifikat erstellen…".
3. Name: `alarmooh` — genau so, denn `Scripts/bundle.sh` sucht nach diesem Namen.
4. Identitätstyp: „Selbstsigniertes Root-Zertifikat".
5. Zertifikatstyp: „Codesignatur".
6. „Erstellen", dann „Fertig".

Prüfen mit:

```
security find-identity -v -p codesigning
```

In der Liste muss eine Zeile mit `"alarmooh"` stehen. Das nächste `make app` meldet
dann „Signatur: Zertifikat aus dem Schluesselbund (…)".

Der Wechsel von Ad-hoc auf Zertifikat ändert die Identität der App ein letztes Mal:
macOS fragt danach noch einmal nach Kalenderzugriff. Ab da bleibt die Identität über
alle Builds hinweg gleich, und die Frage kommt nicht wieder.

## Einrichten

1. Beim ersten Start fragt macOS nach Zugriff auf die Kalender. Der Dialogtext
   (`NSCalendarsFullAccessUsageDescription` in `Scripts/Info.plist`) benennt den
   Umfang: gelesen werden ausschließlich die Termine der ausgewählten Kalender, geändert
   wird dort nichts, den Vollzugriff verlangt macOS mangels reinem Lesezugriff, und
   dauerhaft gespeichert wird davon nur, welche Termine stummgeschaltet sind. Wird der
   Zugriff verweigert, sagt das Menü das auch: „Kein Kalenderzugriff — alarmooh kann
   nichts überwachen",
   darunter „Kalenderzugriff in den Systemeinstellungen erlauben…" als Direktlink.
2. Über das Menüleisten-Icon „Einstellungen…" öffnen und **mindestens einen Kalender
   anhaken**.

Der zweite Schritt ist nicht optional: `subscribedCalendarIDs` ist im Auslieferungs-
zustand leer, und ein leeres Abo bedeutet, dass **nichts** alarmiert. alarmooh läuft
dann still in der Menüleiste und tut genau nichts — gelesen wird in diesem Fall auch
nichts: Die Abfrage geht nur an die abonnierten Kalender, bei leerer Auswahl wird
EventKit gar nicht erst gefragt.

Innerhalb der abonnierten Kalender gilt Opt-out: Alles alarmiert, einzelne Termine und
ganze Serien lassen sich stummschalten — aus dem Alarm-Panel, aus dem Menü und im
Einstellungsfenster unter „Nächste Termine". Ganztägige, abgesagte und selbst abgelehnte
Termine alarmieren grundsätzlich nie.

Weiter im Einstellungsfenster:

- **Nächste Termine** — die nächsten zehn Termine aus den abonnierten Kalendern, gesucht
  bis 60 Tage voraus, je Zeile mit Titel, Wochentag, Datum, Uhrzeit und Kalendername.
  Dazu ein Schalter für diesen einen Termin und, bei Serienterminen, ein zweiter für die
  ganze Serie. Hier lässt sich ein Termin abstellen, bevor er das erste Mal klingelt.
  Ist die Serie stumm, ist der Schalter des einzelnen Termins ausgegraut, und die Zeile
  sagt auch, warum.
- **Vorlaufzeit** — 1 bis 15 Minuten, Standard 2.
- **Mindestlautstärke** — Standard 80 %. Auf diesen Wert hebt alarmooh die
  Systemlautstärke für die Dauer des Alarms an, hebt eine Stummschaltung auf und
  stellt beides danach wieder her — auch beim Beenden der App mitten im Alarm
  („alarmooh beenden" ist die naheliegendste Reaktion auf einen Alarm, den man
  loswerden will). Endete der letzte Lauf durch einen Absturz, wird die Lautstärke
  beim nächsten Start aus `volume-snapshot.json` zurückgesetzt, und zwar noch bevor
  nach dem Kalenderzugriff gefragt wird — das Zurücksetzen hat mit dem Kalender
  nichts zu tun und darf nicht daran hängen. Darunter steht „Ton testen": Der Alarmton
  läuft einmal durch, mit derselben Anhebung und derselben Wiederherstellung wie bei
  einem echten Alarm, und der Knopf heißt währenddessen „Test stoppen". Ist der Ton
  durch, steht von selbst wieder „Ton testen" da.
- **Stummgeschaltet** — Liste der stillgelegten Serien und Termine, jeweils mit
  „Wieder alarmieren". Einzelne Vorkommen räumt alarmooh sieben Tage nach ihrem
  Startzeitpunkt von selbst aus der Liste; stummgeschaltete Serien bleiben dauerhaft
  stehen, bis sie hier wieder scharf geschaltet werden.
- **Bei Anmeldung starten** — über `SMAppService`. Zuverlässig erst, wenn
  `Alarmooh.app` in `/Applications` liegt, also nach `make install`.

Der Ton wiederholt sich, bis einer der Knöpfe im Panel gedrückt wird — und hört sonst
von selbst auf, sobald der Termin schon zwei Minuten läuft (`catchUpGrace`, dieselbe
Nachholfrist wie überall). Frühestens allerdings 60 Sekunden, nachdem er begonnen hat:
Ein nachgeholter Alarm kann losgehen, wenn der Termin bereits 1:58 läuft, und zwei
Sekunden Ton hätte man genau dann überhört. Ein regulärer Alarm läutet damit vier
Minuten. Ein Snooze gibt es bewusst nicht. Schläft der Rechner, feuert kein
Alarm; alarmooh weckt ihn auch nicht.

Nach derselben Frist verschwindet ein Termin auch aus dem Menü: Was länger als zwei
Minuten läuft, steht nicht mehr unter „Nächster: …" — dort rückt der übernächste nach,
ohne dass man das Menü dafür aufklappen muss.

## Eigener Alarmton

Im Repository liegt keine Audiodatei. Beim ersten Alarm erzeugt alarmooh sich selbst
einen Ersatzton — fünf aufsteigende Töne einer Pentatonik (E5, G5, A5, C6, D6),
zusammen 2,4 Sekunden — und legt ihn als `fallback-tone-2.wav` neben die Einstellungen.
Er darf freundlich klingen: Der Ton wiederholt sich ohnehin minutenlang, die
Dringlichkeit liefert also die Wiederholung und nicht die Klangfarbe.

Ein eigener Ton wird im Einstellungsfenster unter „Alarmton" ausgewählt. Die Datei
wird dabei nach `~/Library/Application Support/alarmooh/` kopiert, nicht bloß
verlinkt: Sonst wäre der Alarm stumm, sobald das Original verschoben oder gelöscht
wird, und das fiele erst im Ernstfall auf. „Mitgelieferten Ton verwenden" schaltet
zurück auf den Ersatzton.

Zum Urheberrecht: Die Tokioter Abfahrtsmelodien, die für diesen Zweck naheliegen, sind
komponierte und geschützte Werke. Sie privat abzuspielen ist unproblematisch; sie ins
Repository zu legen und weiterzugeben wäre es nicht. Deshalb enthält das Repo kein
Tonmaterial, und `Sounds/` steht in der `.gitignore`.

## Dateien

Alles liegt in `~/Library/Application Support/alarmooh/`:

- `settings.json` — die gesamte Konfiguration, lesbar formatiert und ausdrücklich von
  Hand editierbar. Fehlende Schlüssel fallen auf Standardwerte zurück, unsinnige Werte
  werden geklemmt, unbekannte Schlüssel stören nicht. Ist die Datei dagegen kaputt,
  wird sie nicht überschrieben; alarmooh läuft mit dem zuletzt gültigen Stand weiter
  und warnt im Menü und im Einstellungsfenster. Beim Scan fallen stummgeschaltete
  Vorkommen heraus, die länger als sieben Tage zurückliegen; geschrieben wird die Datei
  dabei nur, wenn tatsächlich etwas wegfällt.
- `fallback-tone-2.wav` beziehungsweise die kopierte eigene Tondatei.
- `volume-snapshot.json` — Lautstärke, Stummschaltung und die Kennung des
  Ausgabegeräts vor dem Alarm. Existiert nur, solange ein Alarm oder der Testton läuft,
  oder nach einem Absturz während eines Alarms; beim nächsten Start wird daraus die
  alte Lautstärke wiederhergestellt und die Datei gelöscht. Zurückgeschrieben wird nur
  auf dasselbe Gerät — passt die Kennung nicht, bleibt die Datei liegen, statt einen
  fremden Pegel auf ein anderes Gerät zu schreiben.

## Projektaufbau

```
Package.swift          AlarmoohCore (Library) + alarmooh (Executable) + Tests
Makefile               app / install / uninstall / run / test / clean
LICENSE                MIT
Scripts/bundle.sh      baut Release, setzt .build/Alarmooh.app zusammen, signiert
Scripts/Info.plist     LSUIElement, Bundle-ID, Kalender-Nutzungstext
Sources/AlarmoohCore/  UI-freie Logik
Sources/alarmooh/      AppKit, EventKit, Audio, CoreAudio
Tests/AlarmoohCoreTests/
docs/plans/            Design- und Umsetzungsdokument
```

Der Schnitt zwischen den beiden Targets hat genau einen Grund: `AlarmoohCore` ist frei
von UI und Systemzugriffen und dadurch mit `swift test` prüfbar, während das App-Target
alles sammelt, was ein Bundle und eine erteilte Berechtigung braucht — AppKit, EventKit,
AVFoundation und CoreAudio.

## Tests

```
make test
```

Aktueller Stand: **89 Tests, alle grün**. Abgedeckt sind Filterregeln, die
Beschränkung der Kalenderabfrage auf die abonnierten Kalender, Link-Extraktion,
Zeitplanung samt Nachholfrist und Selbstabschaltung des Tons, Aufbau, Zerlegung und
Verfall der Vorkommens-Kennungen, das Laden und Speichern der Einstellungen, der
Lautstärke-Schnappschuss samt Gerätekennung und älterer Dateien ohne dieses Feld sowie
der erzeugte Ersatzton. Panel, Menüleiste und die CoreAudio-Anbindung sind nicht
getestet und werden von Hand geprüft.

## Bekannte Grenzen

- Abgestellte Alarme merkt sich nur der laufende Prozess. Wird alarmooh innerhalb der
  Vorlaufzeit neu gestartet, kann derselbe Alarm ein zweites Mal kommen.
- Ohne eigenes Zertifikat wird ad hoc signiert, und dann ändert sich die App-Identität
  bei jedem Build; macOS fragt die Kalenderberechtigung deshalb erneut ab. Abhilfe:
  „Signierzertifikat anlegen" weiter oben.
- Wird das Ausgabegerät gewechselt, während ein Alarm läuft, wird nichts
  zurückgeschrieben: Das neue Gerät bleibt unangetastet, das ursprüngliche steht so
  lange auf der angehobenen Lautstärke, bis es wieder das Standardgerät ist — dann
  setzt der nächste Start es aus der liegengebliebenen `volume-snapshot.json` zurück.
- Lässt sich das aktuelle Ausgabegerät gar nicht benennen, wird ebenfalls nicht
  zurückgeschrieben, sondern auf den nächsten Start vertagt. Und scheitert das
  Schreiben der Schnappschuss-Datei, hebt alarmooh die Lautstärke trotzdem an und kennt
  den alten Stand nur noch im Speicher — ein harter Abbruch lässt sie dann oben.
- Der Kalender wird öfter gescannt als geplant — gemessen rund elf statt der
  vorgesehenen zwei Scans pro Stunde. Bewusst nicht entprellt, Begründung im
  Designdokument.

Die vollständige Liste — unter anderem zur Stabilität von EventKit-Kennungen über
Synchronisationen hinweg und zur Erkennung von Absagen — steht im Abschnitt „Bekannte
Grenzen" von `docs/plans/2026-08-06-alarmooh-design.md`.

## Lizenz

MIT, siehe `LICENSE`. Das gilt für den Code im Repository; eine selbst hinterlegte
Tondatei bleibt davon unberührt.
