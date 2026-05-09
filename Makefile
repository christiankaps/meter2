DERIVED_DATA_PATH := /private/tmp/meter2-derived-data
PROJECT := Meter2.xcodeproj
SCHEME := Meter2
CONFIGURATION := Debug
DESTINATION := platform=macOS,arch=arm64

.PHONY: build test run clean

build:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA_PATH) \
		build

test:
	./scripts/test_meter2.sh

run:
	./scripts/run_meter2.sh

clean:
	rm -rf /private/tmp/meter2-derived-data
