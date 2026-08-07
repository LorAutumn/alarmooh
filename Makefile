.PHONY: app test install uninstall run clean

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
	-tccutil reset Calendar io.github.lorautumn.alarmooh
	@echo "Deinstalliert (App, Konfiguration inkl. settings.json, Alarmton und"
	@echo "Lautstaerke-Schnappschuss, sowie die erteilte Kalenderberechtigung)."

clean:
	rm -rf .build
