APP_NAME = LLMTracker
APP_BUNDLE = $(APP_NAME).app
APP_EXECUTABLE = $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
INFO_PLIST = $(APP_BUNDLE)/Contents/Info.plist
RESOURCES_DIR = $(APP_BUNDLE)/Contents/Resources

SWIFT_SOURCES = $(wildcard Sources/*.swift)

all: $(APP_BUNDLE)

$(APP_BUNDLE): $(SWIFT_SOURCES) Info.plist AppIcon.icns
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(RESOURCES_DIR)
	@cp Info.plist $(INFO_PLIST)
	@cp AppIcon.icns $(RESOURCES_DIR)/AppIcon.icns
	sips -Z 16 LLM_Tracker_icon.png --out $(RESOURCES_DIR)/LLM_Tracker_iconTemplate.png
	sips -Z 32 LLM_Tracker_icon.png --out $(RESOURCES_DIR)/LLM_Tracker_iconTemplate@2x.png
	swiftc $(SWIFT_SOURCES) -o $(APP_EXECUTABLE)

AppIcon.icns: LLM_Tracker_logo.png
	@mkdir -p MyIcon.iconset
	sips -z 16 16     LLM_Tracker_logo.png --out MyIcon.iconset/icon_16x16.png
	sips -z 32 32     LLM_Tracker_logo.png --out MyIcon.iconset/icon_16x16@2x.png
	sips -z 32 32     LLM_Tracker_logo.png --out MyIcon.iconset/icon_32x32.png
	sips -z 64 64     LLM_Tracker_logo.png --out MyIcon.iconset/icon_32x32@2x.png
	sips -z 128 128   LLM_Tracker_logo.png --out MyIcon.iconset/icon_128x128.png
	sips -z 256 256   LLM_Tracker_logo.png --out MyIcon.iconset/icon_128x128@2x.png
	sips -z 256 256   LLM_Tracker_logo.png --out MyIcon.iconset/icon_256x256.png
	sips -z 512 512   LLM_Tracker_logo.png --out MyIcon.iconset/icon_256x256@2x.png
	sips -z 512 512   LLM_Tracker_logo.png --out MyIcon.iconset/icon_512x512.png
	sips -z 1024 1024 LLM_Tracker_logo.png --out MyIcon.iconset/icon_512x512@2x.png
	iconutil -c icns MyIcon.iconset
	mv MyIcon.icns AppIcon.icns
	rm -rf MyIcon.iconset

clean:
	rm -rf $(APP_BUNDLE) AppIcon.icns

run: $(APP_BUNDLE)
	open $(APP_BUNDLE)
