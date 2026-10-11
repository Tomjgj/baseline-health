# Baseline for iPhone

A thin native shell around `index.html`. The interface is the web app, unchanged. The native side reads HealthKit and hands the samples to the page, so the page computes recovery, sleep, strain and stress the same way it does from an Apple Health export.

**Status: written but not yet built.** It was written in an environment without Xcode, so the Swift code has not been compiled or run. Expect a round of small compile fixes on the first build. The page side of the bridge is tested: a simulated native app answers sync requests in Chromium.

## Build

1. Install XcodeGen: `brew install xcodegen`
2. `cd ios && xcodegen generate && open Baseline.xcodeproj`
3. In the target's *Signing & Capabilities*, pick your team and change the bundle id (`com.example.baseline`). HealthKit is already listed in `Baseline.entitlements`.
4. Run on an iPhone (HealthKit has no real data in the simulator). Allow the Health categories when asked.

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
