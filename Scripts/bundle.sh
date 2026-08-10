#!/usr/bin/env bash
# Baut das Release-Executable und verpackt es als Alarmooh.app.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

# Im versteckten .build/ ablegen: Spotlight indexiert Dot-Ordner nicht,
# sonst erscheint die App doppelt im Apps-Viewer/Launchpad.
APP=".build/Alarmooh.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/alarmooh "$APP/Contents/MacOS/alarmooh"
cp Scripts/Info.plist "$APP/Contents/Info.plist"

# --- Signier-Identitaet bestimmen ---
#
# Die Identitaet bestimmt, als *wer* die App gegenueber macOS auftritt, und
# daran haengt die einmal erteilte Kalenderberechtigung. Bei einer Ad-hoc-
# Signatur ist die Identitaet der cdhash des Binaries, der sich bei jedem Build
# aendert -- macOS sieht dann jedes Mal eine fremde App und fragt die
# Berechtigung erneut ab. Ein festes Zertifikat behebt genau das.
#
# Reihenfolge: ausdrueckliche Vorgabe, sonst passendes Zertifikat im
# Schluesselbund, sonst ad hoc. Der letzte Fall ist kein Fehler: ohne
# Zertifikat muss der Build weiterhin durchlaufen.
if [ -n "${ALARMOOH_SIGN_IDENTITY:-}" ]; then
	IDENTITY="$ALARMOOH_SIGN_IDENTITY"
	SIGNATUR="Vorgabe aus ALARMOOH_SIGN_IDENTITY ($IDENTITY)"
else
	# 'security find-identity -v' listet nur gueltige Identitaeten, je Zeile
	#   1) <SHA-1-Fingerabdruck> "alarmooh"
	# Gesucht wird der Name in den Anfuehrungszeichen; verwendet wird dann der
	# Fingerabdruck, denn der ist auch bei mehreren gleichnamigen Zertifikaten
	# eindeutig. Das '|| true' faengt den leeren Fall ab, sonst wuerde grep
	# zusammen mit 'pipefail' das ganze Skript abbrechen.
	FINGERABDRUCK=$(security find-identity -v -p codesigning 2>/dev/null \
		| grep -iE '"[^"]*alarmooh[^"]*"' \
		| head -n 1 \
		| awk '{print $2}' || true)
	if [ -n "$FINGERABDRUCK" ]; then
		IDENTITY="$FINGERABDRUCK"
		SIGNATUR="Zertifikat aus dem Schluesselbund ($FINGERABDRUCK)"
	else
		IDENTITY="-"
		SIGNATUR="ad hoc -- kein Zertifikat namens 'alarmooh' gefunden"
	fi
fi

# --options runtime schaltet die Hardened Runtime ein. Sie ist hier der
# eigentliche Schutz: alarmooh laeuft dauerhaft mit vollem Kalenderzugriff,
# und ohne Hardened Runtime kann sich jeder Prozess des angemeldeten Nutzers
# an sie anhaengen (Task-Port) oder sie mit DYLD_INSERT_LIBRARIES neu starten
# und den kompletten Kalender mitlesen -- ohne eigene Nachfrage, weil die
# Berechtigung am Bundle haengt und nicht am fremden Prozess.
#
# --entitlements gehoert zwingend dazu und darf nicht als "ungenutzt" entfernt
# werden: unter der Hardened Runtime verlangt macOS fuer den Kalender zusaetzlich
# die Resource-Access-Berechtigung com.apple.security.personal-information.calendars.
# Fehlt sie, lehnt tccd den Zugriff ohne Rueckfrage ab, mit der Meldung
#   "Prompting policy for hardened runtime; service: kTCCServiceCalendar requires
#    entitlement com.apple.security.personal-information.calendars but it is missing"
# und die App meldet "Kalenderzugriff verweigert", obwohl die Systemeinstellungen
# den Zugriff weiterhin als erlaubt anzeigen.
#
# --timestamp=none: der Zeitstempel-Dienst von Apple braucht Netz und nuetzt
# nur bei einer Notarisierung. Die ist mit einem selbst ausgestellten
# Zertifikat ohnehin unmoeglich, also bleibt der Build offline lauffaehig.
codesign --force --options runtime --entitlements Scripts/alarmooh.entitlements \
	--timestamp=none --sign "$IDENTITY" "$APP"

echo "Signatur: $SIGNATUR"
echo "Fertig: $APP"
echo "Installieren mit: make install  (kopiert nach /Applications)"
