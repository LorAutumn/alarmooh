BUNDLE     := Alarmooh.app
BUNDLE_ID  := io.github.lorautumn.alarmooh
BINARY     := .build/release/alarmooh

.PHONY: build test bundle run clean

build:
	swift build -c release

test:
	swift test

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/alarmooh
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	codesign --force --sign - $(BUNDLE)

run: bundle
	open $(BUNDLE)

clean:
	rm -rf .build $(BUNDLE)
