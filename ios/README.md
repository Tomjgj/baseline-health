# Baseline for iPhone

A thin native shell around `index.html`. The interface is the web app, unchanged. The native side reads HealthKit and hands the samples to the page, so the page computes recovery, sleep, strain and stress the same way it does from an Apple Health export.

**Status: builds and launches; not yet run on a real iPhone.** The `iOS build` GitHub Actions workflow (`.github/workflows/ios.yml`) checks this on every change to `ios/` or `index.html`:
1. XcodeGen generates the project and Xcode 16.4 compiles it with no errors or warnings.
2. The app launches in an iPhone simulator.
3. The app log shows that the page rendered and that its first sync request reached the HealthKit reader.

Not yet checked: the HealthKit permission sheet and real Health data, which need a device.

## Run it on your iPhone (no Terminal)

1. Download this branch as a ZIP from GitHub (Code → Download ZIP) and double-click it to unzip.
2. Open `ios/Baseline.xcodeproj` (double-click).
3. Connect your iPhone, unlock it, and pick it at the top of the Xcode window.
4. Click *Baseline* in the left sidebar → *Signing & Capabilities* → *Team* → your Apple ID.
5. Press ▶ (Run).

`Baseline.xcodeproj` is generated from `project.yml` by CI and committed, so don't edit it by hand.

## Run it on your iPhone (Terminal)

With the iPhone connected and unlocked, and Developer Mode on (Settings → Privacy & Security → Developer Mode):

```
./ios/run-on-iphone.sh
```

Sign in to Xcode with your Apple ID first (Xcode → Settings → Accounts; a free Apple ID works). The script finds your team from that, or you can set `TEAM`. It:
1. installs XcodeGen if needed and generates the project;
2. finds the iPhone;
3. builds and signs with your team, using `com.<your username>.baseline` unless you set `BUNDLE`;
4. installs the app and opens it.

Allow the Health categories when asked. If iOS says the developer isn't trusted, trust your Apple ID under Settings → General → VPN & Device Management.

To work in Xcode instead: `cd ios && xcodegen generate && open Baseline.xcodeproj`, set your team and bundle id under *Signing & Capabilities*, and run.

## How it fits together

- `WebView.swift` serves `index.html` from the app bundle at `baseline://app/`, a fixed origin so the page's `localStorage` persists. It also registers the `baseline` message handler.
- The page (`HealthSync` in `index.html`) syncs on launch, when the app returns to the foreground and when new watch readings arrive, at most every 5 minutes. It asks for the days from the day before its last sync up to today; the first sync asks for 180 days. The request is `postMessage({ type: "sync", id, from, to })`.
- `HealthReader.swift` reads the samples in that window (from noon the day before `from`, so the first night is whole) and replies with `BaselineBridge.receive({ id, ok, payload })`. The payload format is `baseline.health/1`, documented above `HI.fromJSON` in `index.html`.
- The page runs the payload through the same aggregation as the export import and saves the daily summaries. Your phone keeps the data. Nothing goes to a server except what you send to your own coach server.
- "Right now" (heart rate, HRV, stress) is the watch's real readings. The page asks for `{ type: "latest" }` and gets the last 3 hours of heart rate and 6 of HRV. An `HKObserverQuery` calls `BaselineBridge.changed()` when the watch delivers new ones, and the page then refreshes and syncs (at most every 5 minutes). The watch measures heart rate every few minutes in the background and hands readings to the iPhone in batches, so the latest one is usually a few minutes old. Second-by-second heart rate would need a Watch app running a workout session.
- Food barcodes: `{ type: "scan" }` opens VisionKit's live scanner (`BarcodeScanner.swift`, iPhone XS or newer) and returns `{ code }`. `{ type: "food", path }` fetches that path from Open Food Facts in the app, so the page doesn't depend on the web view's cross-origin rules.

## Read, never written

Heart rate, resting heart rate, HRV, breathing rate, blood oxygen, wrist temperature, VO₂ max, steps, active and resting energy, time in daylight, caffeine, alcoholic drinks, blood pressure, weight, body fat, lean mass, waist, height, food energy and macros, sleep stages, mindful minutes, workouts, date of birth and sex.

## Next

- Lock-screen and home-screen widgets for the rings and habits, a Live Activity for workouts and the rest timer, and a Watch complication for stress.
- Background delivery (`enableBackgroundDelivery`), so data is fresh before the app opens.
- A Watch app with a workout session for second-by-second heart rate. The page's `Live` module is the place to feed it.
