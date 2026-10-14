# Baseline for iPhone and Apple Watch

A thin native shell around `index.html`. The interface is the web app, unchanged. The native side reads HealthKit and hands the samples to the page, so the page computes recovery, sleep, strain and stress the same way it does from an Apple Health export. It also adds what a web page can't do: widgets, a Live Activity, watch complications, updates in the background, and the Claude coach with your own API key.

**Status: builds and launches; not yet run on a real iPhone.** The `iOS build` GitHub Actions workflow (`.github/workflows/ios.yml`) checks this on every change to `ios/`, `index.html` or the coach's config:
1. The coach's config in the app (`Baseline/coach.json`) matches the server's (`server/coach.mjs`).
2. XcodeGen generates both projects and Xcode 16.4 compiles the full one, with the widgets and complications embedded.
3. The app launches in an iPhone simulator, and the app log shows that the page rendered and that its first sync request reached the HealthKit reader.
4. The watch app launches in a watch simulator, and Baseline Lite builds.

Not yet checked: the HealthKit permission sheet, real Health data, widgets on a home screen, the Live Activity and background updates, which need a device.

## Two Xcode projects

- **`Baseline.xcodeproj`**: everything, including widgets, the Live Activity and watch complications. These run in their own small processes and read today's numbers from an *App Group* (a shared folder the apps write to).
- **`Baseline Lite.xcodeproj`**: the same iPhone and watch apps without widgets, the Live Activity and complications, and without the App Group. A free Apple ID's *Personal Team* may not be allowed App Groups; this project signs with any Apple ID.

Both come from the same spec (`common.yml`, included by `project.yml` and `project-lite.yml`). Lite keeps its generated Info.plist and entitlements in `Lite/`.

## What's on the iPhone besides the app

- **Widgets** (home screen and lock screen): recovery as a ring with strain (small); recovery, strain against today's target, sleep score and hours, and water against your goal (medium); a recovery gauge, a three-number line and an inline line for the lock screen. When the numbers aren't from today they say so ("Yesterday"); before the first sync they say "Open Baseline to sync". The page sends the numbers whenever they change (`{ type: "widget", json }`, the `Glance` in `Shared/Glance.swift`).
- **Live Activity** during a strength workout: on the lock screen and in the Dynamic Island, the workout's time (or the rest left), the exercise and set, and how many sets are done. The page starts, updates and ends it (`{ type: "live", action }`).
- **Background updates**: Health wakes the app when new sleep or a workout is saved (straight away) and when HRV, resting heart rate or water change (at most hourly). The widgets reload, and the page syncs if it's open.
- **Morning notification** (if you turn it on in the app): once last night's sleep reaches Health, between 4:00 and 13:00, "Your recovery is ready" with how long you slept. At most once a morning, and only after at least 3 hours asleep.
- **Save to Apple Health** (off until you turn it on in Settings): water, food, weigh-ins, naps and workouts you log are saved to Health (editing or deleting an entry changes or removes it there), so other apps see them. The sync skips the app's own samples so they aren't counted twice.

## The Claude coach with your own key

The coach normally runs through a small server you deploy (`server/`), which holds the API key. In the iPhone app you can skip the server: paste your own Anthropic API key once and the app talks to Anthropic directly.
- The key is kept in this iPhone's Keychain (not synced, not in backups to other devices). The page never sees it; it's only ever sent to Anthropic, with your coach messages.
- The app sends the same request the server does: the same model, system prompt and tools, from `Baseline/coach.json`. That file is written from `server/coach.mjs` by `cd server && node export-config.mjs`; CI fails if the two differ.
- Get a key at console.anthropic.com → API Keys. Usage is billed to that account.

## The Apple Watch app

`Watch/` is a SwiftUI watch app that ships inside the iPhone app.
- **Today:** recovery, strain and sleep rings, HRV and resting heart rate.
- **Train:** the planned or suggested routine, your other routines, a workout already running on the iPhone (Continue), and quick-start Run, Walk, Ride or Other.
- **Strength workout:** swipe left for pause and end, right for the exercise list. The middle page has the set: tap weight or reps and turn the Digital Crown, then Done. The rest timer taps your wrist when it's up. At the end you rate the effort and save.
- **Phone link:** every set reaches the iPhone's workout logger as you go, and the finished workout is saved in Baseline and to Apple Health with heart rate and energy.
- **Water:** today's water against your goal, and *+ Glass*, which logs one glass on the iPhone.
- **During a workout:** on the exercise list, *Add exercise* picks one from your library; swipe an exercise left to remove it (one with logged sets asks first). The iPhone's logger follows along.
- **Complications** for the watch face: a recovery gauge (circular and corner), recovery, strain and sleep (rectangular), and an inline line. They show what the phone last sent. Not in Baseline Lite.

### Installing the watch app

**If Install in the Watch app on the iPhone fails:** the watch isn't in your signing profile yet, or Developer Mode is off on the watch. Do the steps below once; `run-on-iphone.sh` does steps 4 and 5 for you (it builds for the watch and installs on it directly) when Xcode can see the watch.

With a personal (free) Apple ID, the watch app can't be installed from the Watch app on the iPhone until Xcode has seen your Apple Watch; Xcode adds the watch to your signing profile the first time it runs something on it. Run it on the watch from Xcode once:

1. Watch on your wrist, unlocked, near the Mac, on the same Wi-Fi; iPhone connected by cable and unlocked.
2. In Xcode: *Window → Devices and Simulators*. Your Apple Watch should appear under the iPhone. If Xcode asks, trust the Mac on the watch.
3. On the watch: *Settings → Privacy & Security → Developer Mode* → on (the watch restarts). The option appears after step 2.
4. In Xcode, every target (*Baseline*, *BaselineWatch*, and in the full project *BaselineWidgets* and *BaselineWatchWidgets*) → *Signing & Capabilities* → *Team* → your Apple ID.
5. At the top of the Xcode window pick the scheme *BaselineWatch* and your Apple Watch as the destination, then press ▶. The first install over Wi-Fi can take several minutes.

**If Developer Mode doesn't appear on the watch:** the watch only shows it after Xcode has connected to it. Check, in order:
- the iPhone is in Developer Mode (*Settings → Privacy & Security → Developer Mode* on the iPhone, then restart it);
- the Mac has Wi-Fi and Bluetooth on, on the same Wi-Fi as the iPhone, and the watch is unlocked, on your wrist or the charger, with Wi-Fi on;
- Xcode is up to date (App Store → Updates): an older Xcode doesn't recognise a newer watchOS;
- in *Window → Devices and Simulators*, select the watch under the iPhone and wait; Xcode may say it's preparing the watch (several minutes). Then look again on the watch at *Settings → Privacy & Security*, at the bottom;
- still nothing: restart the watch, the iPhone and Xcode, and plug the iPhone in again.

The watch needs watchOS 10 or later. A free Apple ID can have at most 3 of your own apps on a device at once; delete old test apps if Xcode says the limit is reached. If it still fails, Xcode shows the reason in a red banner or the Issue navigator.

## Run it on your iPhone (no Terminal)

1. Download this branch as a ZIP from GitHub (Code → Download ZIP) and double-click it to unzip.
2. Open `ios/Baseline.xcodeproj` (double-click).
3. Connect your iPhone, unlock it, and pick it at the top of the Xcode window.
4. Click *Baseline* in the left sidebar. For each target in the list (*Baseline*, *BaselineWatch*, *BaselineWidgets*, *BaselineWatchWidgets*): *Signing & Capabilities* → *Team* → your Apple ID.
5. Press ▶ (Run).

If Xcode shows a red error saying a personal team doesn't support App Groups (or that a provisioning profile doesn't include the App Groups capability), your free Apple ID can't sign the widgets. Close the project and open **`ios/Baseline Lite.xcodeproj`** instead, then do steps 3 to 5 again (it only has *Baseline* and *BaselineWatch*). It's the same app without widgets, the Live Activity and watch complications; everything else works.

Both projects are generated from the specs by CI and committed, so don't edit them by hand.

## Run it on your iPhone (Terminal)

With the iPhone connected and unlocked, and Developer Mode on (Settings → Privacy & Security → Developer Mode):

```
./ios/run-on-iphone.sh
```

Sign in to Xcode with your Apple ID first (Xcode → Settings → Accounts; a free Apple ID works). The script finds your team from that, or you can set `TEAM`. It:
1. installs XcodeGen if needed and generates both projects;
2. finds the iPhone;
3. builds and signs with your team, using `com.<your username>.baseline` unless you set `BUNDLE`; if your team can't sign App Groups, it says so and builds Baseline Lite instead;
4. installs the app and opens it.

Allow the Health categories when asked. If iOS says the developer isn't trusted, trust your Apple ID under Settings → General → VPN & Device Management.

To work in Xcode instead: `cd ios && xcodegen generate && open Baseline.xcodeproj`, set your team and bundle id under *Signing & Capabilities*, and run.

## How it fits together

- `WebView.swift` serves `index.html` from the app bundle at `baseline://app/`, a fixed origin so the page's `localStorage` persists. It also registers the `baseline` message handler.
- The page (`HealthSync` in `index.html`) syncs on launch, when the app returns to the foreground and when new watch readings arrive, at most every 5 minutes. It asks for the days from the day before its last sync up to today. The first sync asks for the last 30 days, so Today fills in quickly; older months follow 30 days at a time in the background until 180 days are in (`meta.syncedFrom` remembers how far it got). The request is `postMessage({ type: "sync", id, from, to })`.
- `HealthReader` reads the types in parallel. Steps, energy and daylight come from Health's statistics in half-hour buckets (Health merges iPhone and Watch without double counting); heart rate is averaged per minute.
- `HealthReader.swift` reads the samples in that window (from noon the day before `from`, so the first night is whole) and replies with `BaselineBridge.receive({ id, ok, payload })`. The payload format is `baseline.health/1`, documented above `HI.fromJSON` in `index.html`.
- The page runs the payload through the same aggregation as the export import and saves the daily summaries. Your phone keeps the data. Nothing goes to a server except what you send to your own coach server.
- "Right now" (heart rate, HRV, stress) is the watch's real readings. The page asks for `{ type: "latest" }` and gets the last 3 hours of heart rate and 6 of HRV. An `HKObserverQuery` calls `BaselineBridge.changed()` when the watch delivers new ones, and the page then refreshes and syncs (at most every 5 minutes). The watch measures heart rate every few minutes in the background and hands readings to the iPhone in batches, so the latest one is usually a few minutes old. Second-by-second heart rate would need a Watch app running a workout session.
- Food barcodes: `{ type: "scan" }` opens VisionKit's live scanner (`BarcodeScanner.swift`, iPhone XS or newer) and returns `{ code }`. `{ type: "food", path }` fetches that path from Open Food Facts in the app, so the page doesn't depend on the web view's cross-origin rules.
- Every request the page can make is listed above `userContentController` in `WebView.swift`.
- Widgets and complications: the iPhone app stores the page's glance in the App Group and reloads the widgets (`Widgets/`); the watch app stores the same glance from the phone's context and reloads the complications (`WatchWidgets/`). Without an App Group (Lite) nothing is stored and the requests still answer ok.
- Live Activity: `LiveWorkout.swift` in the app, the views in `Widgets/WorkoutLiveActivity.swift`, and `Shared/WorkoutAttributes.swift` compiled into both. In Lite (no widget extension) the request answers `unavailable`.
- Background: `HealthReader` registers its observers and `enableBackgroundDelivery` at launch (`AppDelegate`), once the person has answered the Health sheet. The morning check is in `HealthReader` too; the page's notification settings arrive as `{ type: "prefs", json }`.
- Coach: `Coach.swift` streams Claude's reply (server-sent events), rebuilds the final message (thinking blocks and their signatures kept as they came, since they go back on later turns) and hands the page the same events the server sends, through `BaselineBridge.coach(id, ev)`.

## Read, and written

Read: heart rate, resting heart rate, HRV, breathing rate, blood oxygen, wrist temperature, VO₂ max, steps, active and resting energy, time in daylight, caffeine, water, alcoholic drinks, blood pressure, weight, body fat, lean mass, waist, height, food energy and macros, sleep stages, mindful minutes, workouts, date of birth and sex.

Written, only once you turn on **Save to Apple Health** in Settings → Apple Health (off until then): water, food (calories and macros), weigh-ins (weight, body fat, waist), naps and workouts you log in Baseline, and workouts you track on the watch. Each sample carries the entry's id, so editing or deleting an entry in Baseline changes or removes it in Health, and *Remove what Baseline saved* deletes all of it. The sync skips Baseline's own samples, so nothing is counted twice.

## Next

- Run it on a real iPhone and Apple Watch: the Health sheet, background delivery, the widgets, the Live Activity and the complications.
- A complication for stress, and habits on a widget.
- Updating the Live Activity from the watch while the iPhone is locked.
