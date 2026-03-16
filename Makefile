THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:latest:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = SentinelCrash

# ── Swift Sources ──
SentinelCrash_SWIFT_FILES = \
	SentinelCrash/SentinelCrashApp.swift \
	SentinelCrash/Models/CrashLog.swift \
	SentinelCrash/Models/DpkgPackage.swift \
	SentinelCrash/Services/AutoBlameEngine.swift \
	SentinelCrash/Services/CloudSyncService.swift \
	SentinelCrash/Services/CrashExporter.swift \
	SentinelCrash/Services/CrashGrouper.swift \
	SentinelCrash/Services/CrashLogParser.swift \
	SentinelCrash/Services/CrashMonitorService.swift \
	SentinelCrash/Services/DpkgPackageManager.swift \
	SentinelCrash/Services/LocalizationHelper.swift \
	SentinelCrash/Services/SettingsManager.swift \
	SentinelCrash/Services/SymbolicationService.swift \
	SentinelCrash/Services/TweakConflictDetector.swift \
	SentinelCrash/Views/AboutView.swift \
	SentinelCrash/Views/AnalyticsView.swift \
	SentinelCrash/Views/AutoBlameView.swift \
	SentinelCrash/Views/ContentView.swift \
	SentinelCrash/Views/CrashDetailView.swift \
	SentinelCrash/Views/CrashDiffView.swift \
	SentinelCrash/Views/CrashGroupListView.swift \
	SentinelCrash/Views/CrashListView.swift \
	SentinelCrash/Views/DashboardView.swift \
	SentinelCrash/Views/ExportView.swift \
	SentinelCrash/Views/JailbreakInfoView.swift \
	SentinelCrash/Views/LiveConsoleView.swift \
	SentinelCrash/Views/SettingsView.swift \
	SentinelCrash/Views/TimelineView.swift \
	SentinelCrash/Views/ToolsHubView.swift \
	SentinelCrash/Views/TweakConflictView.swift

# ── Frameworks ──
SentinelCrash_FRAMEWORKS = UIKit Foundation SwiftUI Combine UserNotifications CoreFoundation

# ── Swift Flags ──
SentinelCrash_SWIFTFLAGS = -ISentinelCrash

# ── Codesign with entitlements ──
SentinelCrash_CODESIGN_FLAGS = -SSentinelCrash/SentinelCrash.entitlements

# ── Resources to bundle ──
SentinelCrash_RESOURCE_DIRS = SentinelCrash/Assets.xcassets

include $(THEOS_MAKE_PATH)/application.mk

# ── Post-build: copy lproj + assets into app bundle ──
after-SentinelCrash-stage::
	@echo "  [LANG] Copying localization bundles..."
	@for lproj in SentinelCrash/*.lproj; do \
		if [ -d "$$lproj" ]; then \
			cp -R "$$lproj" $(THEOS_STAGING_DIR)/Applications/SentinelCrash.app/; \
		fi; \
	done
	@echo "  [INFO] Creating Info.plist..."
	@/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.barabadev.sentinelcrash" \
		$(THEOS_STAGING_DIR)/Applications/SentinelCrash.app/Info.plist 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.barabadev.sentinelcrash" \
		$(THEOS_STAGING_DIR)/Applications/SentinelCrash.app/Info.plist
	@/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string SentinelCrash" \
		$(THEOS_STAGING_DIR)/Applications/SentinelCrash.app/Info.plist 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.1.0" \
		$(THEOS_STAGING_DIR)/Applications/SentinelCrash.app/Info.plist 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" \
		$(THEOS_STAGING_DIR)/Applications/SentinelCrash.app/Info.plist 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string 15.0" \
		$(THEOS_STAGING_DIR)/Applications/SentinelCrash.app/Info.plist 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Add :UIDeviceFamily array" \
		$(THEOS_STAGING_DIR)/Applications/SentinelCrash.app/Info.plist 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Add :UIDeviceFamily:0 integer 1" \
		$(THEOS_STAGING_DIR)/Applications/SentinelCrash.app/Info.plist 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Add :UILaunchScreen dict" \
		$(THEOS_STAGING_DIR)/Applications/SentinelCrash.app/Info.plist 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Add :UIRequiredDeviceCapabilities array" \
		$(THEOS_STAGING_DIR)/Applications/SentinelCrash.app/Info.plist 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Add :UIRequiredDeviceCapabilities:0 string arm64" \
		$(THEOS_STAGING_DIR)/Applications/SentinelCrash.app/Info.plist 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Add :UISupportedInterfaceOrientations array" \
		$(THEOS_STAGING_DIR)/Applications/SentinelCrash.app/Info.plist 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Add :UISupportedInterfaceOrientations:0 string UIInterfaceOrientationPortrait" \
		$(THEOS_STAGING_DIR)/Applications/SentinelCrash.app/Info.plist 2>/dev/null || true
	@echo "  [✓] Stage complete"
