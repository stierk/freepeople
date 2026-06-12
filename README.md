# Freepeople – Android Build Instructions

## Prerequisites

- [Godot Engine 4.3](https://godotengine.org/download/) (standard, not .NET)
- [Android SDK](https://developer.android.com/studio) (API level 28+, recommended: Android Studio)
- [Java JDK 17](https://adoptium.net/)
- Android Export Templates for Godot 4.3 (install via Godot → Editor → Manage Export Templates)

## One-time Setup in Godot

1. Open **Editor → Editor Settings → Export → Android**.
2. Set `Android Sdk Path` to your SDK folder (e.g. `C:/Users/<you>/AppData/Local/Android/Sdk`).
3. Set `Java Sdk Path` to your JDK 17 installation.
4. Generate a debug keystore if you don't have one:
   ```
   keytool -genkey -v -keystore debug.keystore -alias androiddebugkey \
     -keyalg RSA -keysize 2048 -validity 10000 \
     -storepass android -keypass android
   ```
5. In **Editor Settings → Export → Android**, set `Debug Keystore` to the path above, user `androiddebugkey`, password `android`.

## Export

1. Open the project in Godot.
2. Go to **Project → Export…**
3. Select the **Android** preset (already configured in `export_presets.cfg`).
4. Click **Export Project** (debug) or **Export PCK/ZIP**.
5. The APK is written to `builds/android/freepeople.apk`.

The preset is configured for:
- Architecture: `arm64-v8a`
- Package: `de.hirth.freepeople`
- Orientation: landscape (set in `project.godot`)
- Touch emulation from mouse: enabled (set in `project.godot`)

## Install on Device

```bash
adb install builds/android/freepeople.apk
```

## Notes

- For a release build, replace the debug keystore with your release keystore and set the corresponding fields in the Android preset.
- Gradle builds are disabled by default (`gradle_build/use_gradle_build=false`). Enable only if you need custom Android plugins.
