"""
Patches app/android/app/src/main/AndroidManifest.xml with the BLE
permissions documented in docs/06_SETUP_ANLEITUNG.md, ADR-007 and ADR-008.
Run from the .github/workflows/bootstrap-android.yml workflow, from the
'app' working directory, right after `flutter create` has generated the
android/ folder.

Deliberately does NOT add a <service> tag for the Android 15+ foreground
service requirement (ADR-008) - that must point to a real
BleForegroundService class, which does not exist yet (Phase 2 work, not
Phase 0). Adding a dangling <service> reference would break the build.
"""
import re
import sys

PATH = "android/app/src/main/AndroidManifest.xml"

PERMISSIONS_BLOCK = """    <!-- BLE permissions - see docs/06_SETUP_ANLEITUNG.md and ADR-007.
         neverForLocation: this app scans for a known, specific
         service/name and does not use scan results to infer location,
         so no ACCESS_FINE_LOCATION is requested on Android 12+ (API 31+). -->
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN"
                      android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <!-- Legacy path for Android 11 (API 30) and below. -->
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />

    <!-- Android 15+ background BLE - see ADR-008. The <service> tag
         itself is intentionally NOT added here yet - see this file's
         module docstring. -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />

"""


def main():
    with open(PATH) as f:
        content = f.read()

    if "BLUETOOTH_SCAN" in content:
        print("Manifest already contains BLE permissions, skipping patch.")
        return

    match = re.search(r"<manifest[^>]*>", content)
    if not match:
        print("ERROR: could not find <manifest> tag in generated AndroidManifest.xml")
        sys.exit(1)

    insert_at = match.end()
    patched = content[:insert_at] + "\n" + PERMISSIONS_BLOCK + content[insert_at:]

    with open(PATH, "w") as f:
        f.write(patched)

    print("Manifest patched successfully.")


if __name__ == "__main__":
    main()
