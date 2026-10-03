# Hatang chat iOS example.
#   make project            generate HatangChatExample.xcodeproj (XcodeGen)
#   make run                build, install and launch on the booted simulator (boots $(SIM) if none is)
#   make run ARGS="-siteId site_… -appKey hak_… -baseURL http://localhost:3002"
SIM ?= iPhone 17 Pro
BUNDLE := dev.hatang.chat.example
APP := build/Build/Products/Debug-iphonesimulator/HatangChatExample.app
ARGS ?=

.PHONY: project build run clean

project:
	xcodegen generate

build: project
	xcodebuild -project HatangChatExample.xcodeproj -scheme HatangChatExample \
		-destination 'platform=iOS Simulator,name=$(SIM)' -derivedDataPath build build -quiet

run: build
	@xcrun simctl list devices booted | grep -q Booted || xcrun simctl boot "$(SIM)"
	open -a Simulator
	xcrun simctl install booted $(APP)
	xcrun simctl launch booted $(BUNDLE) $(ARGS)

clean:
	rm -rf build HatangChatExample.xcodeproj
