# Freepeople

Freepeople is a **self-organizing village economy simulation** built in **Godot 4.6** (mobile,
landscape). You don't command people directly — each inhabitant is autonomous: it picks a
profession, builds or reclaims a hut, gathers resources, runs a production chain, trades on a
market, buys food, and starves if it can't eat. Your settlement lives or dies by whether the
economy keeps everyone fed. The game ends when the population reaches zero — the score is how many
in-game days you survived.

## Mechanics at a glance

- **Autonomous inhabitants** with a state machine: seek work, build, produce, deliver, trade, eat.
- **Professions & production chains** — Woodcutter → Wood → Sawmill → Planks; Quarry → Stone; and the
  food chain **Farmer → Grain → Windmill → Flour → Bakery → Food** that keeps everyone alive.
- **Decentralized market** — storages and granaries host exchanges with order matching, price drift,
  per-person margins/break-even, and distance costs; unprofitable workers switch jobs.
- **Hunger & survival** — inhabitants eat 3 meals/day; too many missed meals means death, and an empty
  village is game over.
- **Living world** — 64×64 tile map with forests, stone and water, emergent desire paths from foot
  traffic, resource depletion/regrowth, and crop fields around farms.
- **Time controls** (pause / 1× / 2× / 5×) and **save/load**.

**Deep dive:** see [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md) for the full current-state reference,
and [`CLAUDE.md`](CLAUDE.md) for the code architecture map. Build instructions follow below.

---

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
