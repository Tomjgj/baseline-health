# Baseline Health: notes for Claude Code

Single-file web app (`index.html`, ~8,500 lines, vanilla JS, no build step). Exported from a Claude artifact (version 7, 2026-10-11).

## Rules
- Keep it one self-contained page unless asked to split it.
- Dark-first "glass instrument" design: solid cards, floating glass tab bar, rounded numerals. Data colours: strain #3b8deb, sleep #8f7bf0, stress #db6a24, HRV #1aa394, heart rate #e0526e.
- All models are measured against the person's own baselines (30-day mean ± 1 SD).
- Never put an API key in front-end code. The Claude coach needs a backend function that holds the key.

## Storage
`Store.init()` uses `window.claude.use('db')` when running inside Claude and falls back to `localStorage` otherwise. Standalone, only the localStorage path runs.

## Conventions added in phase 1
- Type: write font sizes as `calc(N * var(--fs))`, never px, and N is at least 11. `--fs` follows the browser text size and, on iPhone, Dynamic Type. Only the tab bar labels and the Food add button stay fixed.
- Touch targets: small controls get a 44 × 44 tap layer from the shared `::after` rule next to `.tap` in the CSS. Add new small control classes to that list.
- Today: one focus card with "Next up" (`planRows` sorts by priority), a habits row, and `foldCard`s that remember open/closed in `App.ui.fold`.
- Streaks: `habitTrack` returns `streak`, `unit` ('day' or 'week'), `atRisk` and `forgiven`. Use `Tabs.streakText(tr)` to show one. Pauses live in `profile.habitPauses`; days answered "Felt sick" pause too.

## Conventions added in phase 2
- Habit effects: use `C.habitEffect(id, date, measure)`, never a plain yes-minus-no difference. It fits outcome ~ habit + weekend + training load + exam days (sleep is deliberately not adjusted for), with a 3-day block bootstrap. It returns `est`, `raw`, `lo80/hi80`, `lo90/hi90`, `label` ('clear' | 'likely' | 'unclear' | 'few'), `more` and `small`.
- Labels: Clear means the 90% range excludes zero and the effect is at least the floor (3 points or a quarter of the person's SD). Likely means the 80% range does. Summaries (Health, tracker, the stress page, Claude's context) list only Clear and Likely; Not clear yet appears only on the habit's own page or as names.
- UI helpers: `Tabs.eff` has `pill`, `range`, `bar`, `num`, `more` and `MEASURES`. Labels use shape as well as tone (filled, half or ring dot).
- Experiments live in `profile.experiments` as `{id, habit, target, from, to, measure, ended?}`. `C.experiment(id)` compares the window with the 28 days before, intention-to-treat. One runs at a time.

## Conventions added in phase 3 (Claude coach)
- The backend is `server/coach.mjs` (a Cloudflare Worker; `dev.mjs` runs it under Node). It holds the key and owns the model, system prompt and tools. The page only sends `messages`. Keep `SYSTEM` and `TOOLS` byte-stable: changing either mid-conversation invalidates Claude's earlier thinking and the cache. Run `cd server && npm test` after touching it.
- `Coach` in `index.html` keeps the conversation as API-shaped messages in localStorage, append-only. The data snapshot (`Coach.snapshot`) goes in the first user message, and a fresh one is appended as a `system` message when the data changed. A failed or refused turn is popped off the end; never edit earlier turns.
- Actions: every proposal goes through `check` → card → Confirm → `run`, which returns an undo record; `show_chart` alone runs without confirmation. A new tool needs a schema in `TOOLS` (strict, all fields required) plus `check`, `describe`, `run` and `undo` in `Coach`.
- Memory lives in `profile.coachMemory` (`profile.coachMemoryOn`), and check-in note frequency in `profile.coachNotes`. The server address and access code stay on the device (`baseline:coach`), never in the profile or the code.
- Gate Claude entry points on `Coach.available()`, not `App.sample`. Food describe/photo still use the artifact runtime only.

## Conventions added in phase 4 (Apple Health pipeline, iOS shell)
- One pipeline, two sources: the export scanner (`HI.importFile`) and the JSON feed (`HI.fromJSON`, format `baseline.health/1`, documented above it) both fill the same raw-sample record (`emptyR`) and go through `aggregate`. A new Health type needs both readers plus an aggregate step; keep the XML-vs-JSON consistency check passing (zero differences on identical samples).
- Day docs can carry `daylight {min, am}`, `caffeine {mg, late}`, `drinks`, `mindful` and `bp {sys, dia, n}`.
- Habits answered from data: `C.autoAnswer(id, date)` returns `{v, why}`, and `C.answerOf(date, id)` (the person's answer, else the data's) is what streaks, effects and experiments read. Never infer a "no" the data can't show: alcohol and stretching are only ever filled in as yes. Your own answer always wins.
- `HealthSync` is the page side of the iPhone bridge (`webkit.messageHandlers.baseline` / `BaselineBridge.receive`). It syncs incrementally from the day before `meta.lastSync.to`. `ios/` holds the SwiftUI shell (XcodeGen `project.yml`). CI (`.github/workflows/ios.yml`, macOS runner) builds it, launches it in the simulator, and checks the app log for `page: Baseline Health | rendered` and `sync request`. Run it after any change to `ios/` or the bridge. See `ios/README.md`.

## Conventions added in the daily-use pass
- No mock-up leftovers: nothing simulated outside the sample person, and no text promising features that don't exist. `Live` uses the watch's real readings in the iPhone app (`HealthSync.latest`, refreshed on `BaselineBridge.changed()`) and simulates only for the sample. Say how old a reading is.
- iPhone app first run: no sample person. `healthBanner` shows the sync state (reading, no data, no access). Where the web says "Import", the app says "Sync" (`getHealth()`). After the first sync, `Sheet.aboutYou` asks sex, birth year, height, weight and goal once (`profile.setupDone`).
- Bridge requests besides `sync`: `latest`, `scan` (VisionKit barcode), `food` (Open Food Facts fetched by the app), `share` (share sheet), `notify` / `unnotify` (local reminders: `rest`, `bedtime`). See the comment above `userContentController` in `ios/Baseline/WebView.swift`.
- Food: `FoodNet` looks up Open Food Facts (barcode, and search under the built-in list). New built-in foods go at the end of `FOODS` (ids are positions); `ALIAS` and `TOP` steer search. Logged food gets `mealAt(date, meal)`, not "now". Show amounts with `qtyText`.
- Time of day matters: after 8 pm Today and Train stop pushing a strain target; `lightsOut` returns `passed`/`left` once the time has gone. Past days never say "today" or "last night".
- Claims need history: changes "vs N months ago" and health-age trends say the real span and wait for 3 weeks (a month for health age). Training load skips days without data; lifting load waits for 3 weeks of logged sets.
- The check-in saves only the person's own answers; answers from data stay the data's (`C.answerOf`).

## Conventions added in the lighter-feel pass
- Weights: 400 body, 500 row titles and secondary labels, 600 card titles, buttons and small caps, 650–700 only for big numbers and page titles. `b`/`strong` are 600. Nothing above 700.
- Every health number opens its history: `App.open('metric', { key, date })` (keys in `METRICS` in ui-pages: the baselines plus active, daylight, recovery, sleepScore, strain, weight). Week / month / 3 months / year, normal band, recent days that open that day.
- Health is four parts: Highlights (only measures outside the person's normal, else one calm line), the Recovery / Sleep / Strain strip (90-day average under each), Categories (six tiles from `CATS` in Tabs: heart, sleep, breathing, activity, stress, body) and Insights (experiment, recovery tracker, stress drivers, health age). A tile opens `Pages.healthCat` (`Tabs.healthCategory(C, date, id)`), which holds that category's number rows and its detail cards. New detail cards go on a category page, not on the tab.
- Motion is quick and quiet: tab change is a 0.16 s fade, push 0.26 s, pop 0.22 s; rows and cards dim when pressed instead of scaling.
- Keep explanations to one short sentence; long ones go in an expander or go.
- Balance: selected segments, pager tabs and days use `--seg-on` (soft grey), not white; solid white (`.btn.primary`) is for the one main action on a screen. No boxes inside cards: tiles in a card are split by hairlines. Big numbers: `.huge-num` 48, hero rings 52 (44 when 4+ characters), tiles 28–30. Empty measurements collapse to one line instead of "–" boxes.

## Muscles
- Two levels: the 10 groups in `E.MUSCLES` (routine suggestions, muscular load, the Train hero text) and 19 muscles in `E.PARTS` (`{name, group, region}`), which the map and the Muscles page use. `EX_PARTS` says which muscles each built-in exercise works (primary | secondary, half a set); `E.exerciseParts(name)` falls back to every muscle of the exercise's groups. A new exercise needs both its `FOODS.EXERCISES` groups and an `EX_PARTS` line.
- `C.muscleParts(d)` gives each muscle `fresh`, `status`, `readyIn` (hours to 70% fresh), `sets7` and `hits`. `Charts.bodyMap(fill, { detail: true })` passes muscle names to `fill`; without `detail` it passes group names. Colours come from `Train.freshColor` / `Train.partFill`.

## Apple Watch app (ios/Watch)
- SwiftUI, watchOS 10+, embedded in the iPhone app (target `BaselineWatch`, bundle id `$(BASE_BUNDLE_ID).watchkitapp`). Same design rules: black, the data colours, rounded numerals, semibold at most except the one big number.
- The page builds the watch's context in `Watch.context()` (today's scores, next and other routines pre-filled like the logger, a workout in progress, tired muscles) and sends it as JSON through the bridge (`{ type: "watch", json }`, `WatchLink.swift`). Keep it plain JSON; the watch decodes it with `Codable` (`Watch/Model.swift`).
- The watch sends `start`, `set`, `finish` and `discard`; `Watch.receive` keeps one `App.draft` for both sides and saves the finished workout (`src: 'watch'`). Weights travel in kg; -1 means empty.
- Strength and cardio sessions run as `HKWorkoutSession`s and are saved to Health; the phone's sync merges the Health workout with the logged one.

## Sync
- First sync: the last 30 days, then `HealthSync.backfill` fetches older months 30 days at a time to 180 (`meta.syncedFrom`). `applyImport` kind `'backfill'` doesn't touch `meta.lastSync`.
- `HealthReader` sends steps, energy and daylight as Health statistics in half-hour buckets (source "Health") and heart rate as per-minute averages; everything else raw.

## Water and pull to sync
- Water lives in the day's food doc as `water: [{id, at, ml}]` (`Store.addWater` / `removeWater` / `restoreWater`; `putFood` keeps it). `C.water(date)` adds those logs, food-log items named Water, and `day.water.ml` from Apple Health (other apps' samples; source "Baseline" is skipped). The goal is `profile.waterGoal`, else `C.waterSuggest()` (33 ml per kg, 1.5–4 L). Show amounts with `mlText` / `mlParts`; log with `logWater(date, ml)` (undo toast and a haptic). Colour `--water`. The hydration habit is only ever filled in as yes (2 L or more).
- Pull down at the top of a screen (iPhone app only, not in sheets or flow pages) calls `HealthSync.refresh()`; the indicator is `#ptr`. With data in, background syncs show no banner; only the first sync does.
- `HealthSync.haptic(kind)` sends `{ type: 'haptic', kind: 'light' | 'medium' | 'success' }` and doesn't wait for an answer.

## Next steps (in order)
1. ~~Polish~~ (done, Oct 2026): Today in ~1.5 screens, one add button on Food, 44 px targets and 11 px+ scalable text, forgiving streaks with pauses, lazy-drawn Health.
2. ~~Honest insights~~ (done, Oct 2026): ranges and Clear / Likely / Not clear yet labels on habit and activity effects, adjusted for weekends, training load and exams, two-week experiments. Not done: Oura-style monthly stress load.
3. ~~Claude coach~~ (done, Oct 2026): backend in `server/`, editable memory, six tools with confirm/undo, inline charts, rare check-in notes, day-specific starting points. Not done: Claude-written check-in notes (they're local rules today), and food describe/photo through the backend.
5. Daily-use pass (Oct 2026): done as above. Not done: larger Dynamic Type clipping on habit chips and Health labels, imperial for temperature and food, custom exercises without muscles, Claude coach setup for people who can't deploy a server.
6. Watch app (Oct 2026): built and compiled in CI, not yet run on a watch. Next: complications, a Live Activity for workouts on the phone, editing exercises on the watch.
4. ~~Data pipeline~~ (done, Oct 2026): one aggregation for export and JSON, new Health types, habits answered from data, the `HealthSync` bridge and an iOS shell in `ios/` (builds and launches in CI). Next: run the iOS app on a device with real Health data, background delivery, widgets, a Live Activity for workouts and a Watch complication.
