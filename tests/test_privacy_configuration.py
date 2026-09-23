import plistlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ENTITLEMENTS = ROOT / "DynamicIsland" / "DynamicIsland.entitlements"
PROJECT = ROOT / "DynamicIsland.xcodeproj" / "project.pbxproj"
# Upstream release automation is retained verbatim outside the active workflow
# directory. Check its original guarantees as well as ToolIsle's active builder.
RELEASE_WORKFLOW = ROOT / ".github" / "workflows" / "release.yml"
if not RELEASE_WORKFLOW.exists():
    RELEASE_WORKFLOW = ROOT / "docs" / "upstream-workflows" / "release.yml"
CI_WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
INTEGRATION_WORKFLOW = ROOT / ".github" / "workflows" / "toolisle-integration.yml"
PREVIEW_BUILDER = ROOT / "scripts" / "build_gitee_settings_preview.sh"


class PrivacyConfigurationTests(unittest.TestCase):
    def test_camera_capture_is_explicitly_entitled(self):
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())
        self.assertTrue(entitlements.get("com.apple.security.device.camera"))

    def test_notes_sync_is_authorized_for_apple_events(self):
        project = PROJECT.read_text()
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())
        self.assertNotIn("AUTOMATION_APPLE_EVENTS = NO;", project)
        self.assertIn("com.apple.Notes", entitlements["com.apple.security.temporary-exception.apple-events"])

    def test_automation_usage_text_names_notes(self):
        self.assertEqual(2, PROJECT.read_text().count(
            'INFOPLIST_KEY_NSAppleEventsUsageDescription = "ToolIsle uses AppleScripts to control Spotify, Apple Music, and Notes.";'))

    def test_full_access_reminder_api_has_matching_usage_text(self):
        self.assertEqual(2, PROJECT.read_text().count("INFOPLIST_KEY_NSRemindersFullAccessUsageDescription ="))

    def test_release_resigning_preserves_archived_entitlements(self):
        workflow = RELEASE_WORKFLOW.read_text()
        for required in [
            'codesign -d --entitlements :- "$APP_PATH" > "$ENTITLEMENTS_PATH"',
            '--entitlements "$ENTITLEMENTS_PATH"',
            'FINAL_ENTITLEMENTS_PATH="$RUNNER_TEMP/${APP_NAME}-final.entitlements"',
            'codesign -d --entitlements :- "$APP_PATH" > "$FINAL_ENTITLEMENTS_PATH"',
            '/usr/libexec/PlistBuddy -c "Print :com.apple.security.device.camera" "$FINAL_ENTITLEMENTS_PATH" | grep -qx "true"',
            '/usr/libexec/PlistBuddy -c "Print :com.apple.security.automation.apple-events" "$FINAL_ENTITLEMENTS_PATH" | grep -qx "true"',
        ]:
            self.assertIn(required, workflow)
        if INTEGRATION_WORKFLOW.exists():
            builder = PREVIEW_BUILDER.read_text()
            self.assertIn('codesign -d --entitlements :- "$APP" > "$OUT/entitlements.plist"', builder)
            self.assertIn('--entitlements "$OUT/entitlements.plist" "$APP"', builder)
            self.assertIn('codesign --verify --deep --strict', builder)

    def test_ci_checks_the_privacy_configuration(self):
        command = "python3 -m unittest tests.test_privacy_configuration"
        if INTEGRATION_WORKFLOW.exists():
            workflow = INTEGRATION_WORKFLOW.read_text()
            self.assertIn("scripts/build_gitee_settings_preview.sh", workflow)
            self.assertIn("bash scripts/.build_integration.sh", workflow)
            self.assertIn(command, PREVIEW_BUILDER.read_text())
        else:
            self.assertIn(command, CI_WORKFLOW.read_text())


if __name__ == "__main__":
    unittest.main()
