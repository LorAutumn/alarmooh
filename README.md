# alarmooh

## Was es ist

alarmooh ist eine eigenständige macOS-App in der Menüleiste. Sie liest über EventKit
den lokalen Kalender — also das, was Kalender.app ohnehin schon synchronisiert — und
schlägt standardmäßig zwei Minuten vor Terminbeginn mit einem schleifenden Signalton
Alarm. Ein schwebendes Panel unter dem Menüleisten-Icon bietet dazu den Meeting-Link
an: „Beitreten" öffnet ihn und stellt den Ton ab, „Stumm" stellt nur den Ton ab,
„Diese Serie nie wieder" schaltet die ganze Serie dauerhaft still.

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
make bundle    # Release bauen, Alarmooh.app zusammensetzen, ad-hoc signieren
make run       # dasselbe und anschließend starten
make test      # Tests gegen AlarmoohCore, ohne Bundle
make clean     # .build und Alarmooh.app löschen
```

Ein nacktes `swift build`-Binary reicht nicht. EventKit gibt Kalenderdaten nur an ein
signiertes App-Bundle heraus, das eine Bundle-ID und den Schlüssel
`NSCalendarsFullAccessUsageDescription` mitbringt; ohne Bundle kommt schlicht kein
Kalender an. Die Bundle-ID (`io.github.lorautumn.alarmooh`) bleibt deshalb fest, damit
macOS die einmal erteilte Berechtigung wiedererkennt.

`make bundle` signiert ad-hoc (`codesign --sign -`). Damit ändert sich die
Code-Identität bei jedem Build, und macOS fragt die Kalenderberechtigung gelegentlich
erneut ab. Wen das stört, der legt sich einmalig ein selbstsigniertes Zertifikat im
Schlüsselbund an und signiert damit; dann bleibt die Identität über Builds hinweg
gleich.

## Einrichten

1. Beim ersten Start fragt macOS nach Zugriff auf die Kalender. Ohne diesen Zugriff
   zeigt das Menü nur „Kein ueberwachter Termin".
2. Über das Menüleisten-Icon „Einstellungen…" öffnen und **mindestens einen Kalender
   anhaken**.

Der zweite Schritt ist nicht optional: `subscribedCalendarIDs` ist im Auslieferungs-
zustand leer, und ein leeres Abo bedeutet, dass **nichts** alarmiert. alarmooh läuft
dann still in der Menüleiste und tut genau nichts.

Innerhalb der abonnierten Kalender gilt Opt-out: Alles alarmiert, einzelne Serien
lassen sich aus dem Alarm-Panel heraus stummschalten. Ganztägige, abgesagte und selbst
abgelehnte Termine alarmieren grundsätzlich nie.

Weiter im Einstellungsfenster:

- **Vorlaufzeit** — 1 bis 15 Minuten, Standard 2.
- **Mindestlautstärke** — Standard 80 %. Auf diesen Wert hebt alarmooh die
  Systemlautstärke für die Dauer des Alarms an, hebt eine Stummschaltung auf und
  stellt beides danach wieder her.
- **Stummgeschaltet** — Liste der stillgelegten Serien und Termine, jeweils mit
  „Wieder alarmieren".
- **Bei Anmeldung starten** — über `SMAppService`. Zuverlässig erst, wenn
  `Alarmooh.app` in `/Applications` liegt.

Der Ton läuft in Endlosschleife, bis einer der drei Knöpfe im Panel gedrückt wird. Es
gibt bewusst kein Auto-Timeout und kein Snooze. Schläft der Rechner, feuert kein
Alarm; alarmooh weckt ihn auch nicht.

## Eigener Alarmton

Im Repository liegt keine Audiodatei. Beim ersten Alarm erzeugt alarmooh sich selbst
einen Ersatzton — zwei gehaltene Töne (H5, E5), je 0,55 Sekunden — und legt ihn als
`fallback-tone.wav` neben die Einstellungen.

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
  und warnt im Menü und im Einstellungsfenster.
- `fallback-tone.wav` beziehungsweise die kopierte eigene Tondatei.
- `volume-snapshot.json` — die Lautstärke vor dem Alarm. Existiert nur, solange ein
  Alarm läuft, oder nach einem Absturz während eines Alarms; beim nächsten Start wird
  daraus die alte Lautstärke wiederhergestellt und die Datei gelöscht.

## Projektaufbau

```
Package.swift          AlarmoohCore (Library) + alarmooh (Executable) + Tests
Makefile               bundle / run / test / clean
Resources/Info.plist   LSUIElement, Bundle-ID, Kalender-Nutzungstext
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

Aktueller Stand: **49 Tests, alle grün**. Abgedeckt sind Filterregeln,
Link-Extraktion, Zeitplanung samt Nachholfrist, das Laden und Speichern der
Einstellungen und der erzeugte Ersatzton. Panel, Menüleiste und die CoreAudio-Anbindung
sind nicht getestet und werden von Hand geprüft.

## Bekannte Grenzen

- Abgestellte Alarme merkt sich nur der laufende Prozess. Wird alarmooh innerhalb der
  Vorlaufzeit neu gestartet, kann derselbe Alarm ein zweites Mal kommen.
- Einzelne Vorkommen lassen sich in der Oberfläche nur wieder scharf schalten, nicht
  stummschalten: Das Alarm-Panel bietet ausschließlich „Diese Serie nie wieder", und
  das auch nur bei Serienterminen. Ein einzelner Termin landet nur durch Eintrag in
  `mutedEventIDs` von Hand in der Mute-Liste.
- Die Ad-hoc-Signatur ändert die App-Identität bei jedem Build; macOS fragt die
  Kalenderberechtigung deshalb gelegentlich erneut ab.
- Wird das Ausgabegerät gewechselt, während ein Alarm läuft, bleibt das ursprüngliche
  Gerät auf der angehobenen Lautstärke stehen.

Die vollständige Liste — unter anderem zur Stabilität von EventKit-Kennungen über
Synchronisationen hinweg und zur Erkennung von Absagen — steht im Abschnitt „Bekannte
Grenzen" von `docs/plans/2026-08-06-alarmooh-design.md`.
