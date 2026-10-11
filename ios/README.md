# Baseline for iPhone

A thin native shell around `index.html`. The interface is the web app, unchanged. The native side reads HealthKit and hands the samples to the page, so the page computes recovery, sleep, strain and stress the same way it does from an Apple Health export.

**Status: builds and launches; not yet run on a real iPhone.** The `iOS build` GitHub Actions workflow (`.github/workflows/ios.yml`) checks this on every change to `ios/` or `index.html`:
1. XcodeGen generates the project and Xcode 16.4 compiles it with no errors or warnings.
2. The app launches in an iPhone simulator.
3. The app log shows that the page rendered and that its first sync request reached the HealthKit reader.

Not yet checked: the HealthKit permission sheet and real Health data, which need a device.

## Run it on your iPhone

With the iPhone connected and unlocked, and Developer Mode on (Settings → Privacy & Security → Developer Mode):

```
TEAM=ABCDE12345 ./ios/run-on-iphone.sh
```

`TEAM` is your team id from Xcode → Settings → Accounts (a free Apple ID's Personal Team is fine). The script:
1. installs XcodeGen if needed and generates the project;
2. finds the iPhone;
3. builds and signs with your team, using `com.<your username>.baseline` unless you set `BUNDLE`;
4. installs the app and opens it.

Allow the Health categories when asked. If iOS says the developer isn't trusted, trust your Apple ID under Settings → General → VPN & Device Management.

To work in Xcode instead: `cd ios && xcodegen generate && open Baseline.xcodeproj`, set your team and bundle id under *Signing & Capabilities*, and run.

## How it fits together

- `WebView.swift` serves `index.html` from the app bundle at `baseline://app/`, a fixed origin so the page's `localStorage` persists. It also registers the `baseline` message handler.
- The page (`HealthSync` in `index.html`) syncs on launch and when the app returns to the foreground, at most every 15 minutes. It asks for the days from the day before its last sync up to today; the first sync asks for 180 days. The request is `postMessage({ type: "sync", id, from, to })`.
- `HealthReader.swift` reads the samples in that window (from noon the day before `from`, so the first night is whole) and replies with `BaselineBridge.receive({ id, ok, payload })`. The payload format is `baseline.health/1`, documented above `HI.fromJSON` in `index.html`.
- The page runs the payload through the same aggregation as the export import and saves the daily summaries. Your phone keeps the data. Nothing goes to a server except what you send to your own coach server.

## Read, never written

Heart rate, resting heart rate, HRV, breathing rate, blood oxygen, wrist temperature, VO₂ max, steps, active and resting energy, time in daylight, caffeine, alcoholic drinks, blood pressure, weight, body fat, lean mass, waist, height, food energy and macros, sleep stages, mindful minutes, workouts, date of birth and sex.

## Next

- Lock-screen and home-screen widgets for the rings and habits, a Live Activity for workouts and the rest timer, and a Watch complication for stress.
- Background delivery (`enableBackgroundDelivery`), so data is fresh before the app opens.
- Live heart rate from the Watch during workouts. The page's `Live` module is the place to feed it.
