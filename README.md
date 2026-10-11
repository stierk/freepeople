# Freisassen

Freisassen is a **self-organizing village economy simulation** built in **Godot 4.6** (mobile,
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

# Freisassen – Android Build Instructions

## Prerequisites

- [Godot Engine 4.6](https://godotengine.org/download/) (standard, not .NET)
- [Android SDK](https://developer.android.com/studio) (API level 28+, recommended: Android Studio)
- [Java JDK 17](https://adoptium.net/)
- Android Export Templates for Godot 4.6 (install via Godot → Editor → Manage Export Templates)

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

The **Android** preset (`export_presets.cfg`) is configured for a **release AAB** (App Bundle), the
format Google Play requires:

1. Open the project in Godot.
2. Go to **Project → Export…**, select the **Android** preset.
3. Click **Export Project**. Gradle builds are enabled (`gradle_build/use_gradle_build=true`), so
   this invokes a real Gradle build under the hood — the first run downloads Gradle dependencies and
   can take a few minutes.
4. The signed `.aab` is written to `deployments/freisassen-0.1.0.aab`.

The preset is configured for:
- Architecture: `arm64-v8a`
- Package: `de.hirth.freisassen`
- Min/target SDK: 24 / 36
- Orientation: landscape (set in `project.godot`)
- Touch emulation from mouse: enabled (set in `project.godot`)

### Release signing

Release signing credentials (`keystore/release`, `keystore/release_user`,
`keystore/release_password`) live in `.godot/export_credentials.cfg` — a local-only file (gitignored
via `.godot/`), never checked into the repo. Set them either through **Project → Export → Android →
Release** in the editor, or by editing that file directly; either way writes to the same place. Keep
the release keystore itself outside the repo tree too (e.g. next to your debug keystore under
`%APPDATA%\Godot\keystores\`) — losing it means you can never publish an update under the same
package ID again.

## Local testing

An `.aab` can't be installed directly with `adb install` — it's a publishing format, not a
device-installable package. For local testing, use
[bundletool](https://developer.android.com/tools/bundletool):

```bash
bundletool build-apks --bundle=deployments/freisassen-0.1.0.aab --output=freisassen.apks --local-testing
bundletool install-apks --apks=freisassen.apks
```
