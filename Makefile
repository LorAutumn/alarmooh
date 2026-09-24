.PHONY: app test install uninstall run clean

# Muss zur Bundle-ID passen, mit der gebaut wurde (siehe Scripts/bundle.sh).
BUNDLE_ID := $(or $(ALARMOOH_BUNDLE_ID),io.github.lorautumn.alarmooh)

app:
	Scripts/bundle.sh

test:
	swift test

install: app
	rm -rf /Applications/Alarmooh.app
	cp -R .build/Alarmooh.app /Applications/
	@echo "Installiert. Starten mit: open /Applications/Alarmooh.app"

# Startet die App aus .build/, ohne sie zu installieren.
# Bewusst 'open' und nicht das Binary direkt: erst dadurch registriert
# LaunchServices das Bundle, woran die Kalenderberechtigung haengt.
run: app
	open .build/Alarmooh.app

uninstall:
	-pkill -f Alarmooh.app
	rm -rf /Applications/Alarmooh.app
	rm -rf ~/Library/Application\ Support/alarmooh
	-tccutil reset Calendar $(BUNDLE_ID)
	@echo "Deinstalliert (App, Konfiguration inkl. settings.json, Alarmton und"
	@echo "Lautstaerke-Schnappschuss, sowie die erteilte Kalenderberechtigung)."

clean:
	rm -rf .build
