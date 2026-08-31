APP       := MDReader
CONFIG    := release
BIN       := .build/$(CONFIG)/$(APP)
RESBUNDLE := .build/$(CONFIG)/md-reader_MDReaderKit.bundle
DIST      := dist/$(APP).app
VENDOR    := Sources/MDReaderKit/Resources/web/vendor
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

.PHONY: build app run test install clean

build:
	@test -d $(VENDOR) || (echo "error: $(VENDOR) missing — run scripts/fetch-web-libs.sh first" && exit 1)
	swift build -c $(CONFIG)

app: build
	rm -rf $(DIST)
	mkdir -p $(DIST)/Contents/MacOS $(DIST)/Contents/Resources
	cp $(BIN) $(DIST)/Contents/MacOS/$(APP)
	cp -R $(RESBUNDLE) $(DIST)/Contents/Resources/
	cp packaging/Info.plist $(DIST)/Contents/Info.plist
	@if [ -f packaging/AppIcon.icns ]; then cp packaging/AppIcon.icns $(DIST)/Contents/Resources/AppIcon.icns; fi
	printf 'APPL????' > $(DIST)/Contents/PkgInfo
	plutil -lint $(DIST)/Contents/Info.plist
	codesign --force -o runtime -s - $(DIST)

run: app
	open $(DIST)

test:
	bash scripts/test.sh

install: app
	rm -rf /Applications/$(APP).app
	cp -R $(DIST) /Applications/
	$(LSREGISTER) -f /Applications/$(APP).app
	swift scripts/set-default-handler.swift /Applications/$(APP).app

clean:
	rm -rf .build dist
