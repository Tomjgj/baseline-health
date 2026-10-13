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

## Real-app pass (Oct 2026)
- Feel: `buzz(kind)` for haptics (the Taptic Engine through the bridge, a vibration elsewhere); `toast(..., { action: 'Undo' })` buzzes on its own. Rest over plays `chime()`. The back swipe follows the finger: `A.open` keeps the screen beneath (`stack[i].under`, `underY`) and the swipe shows it in `#under`; `A.back({ swiped: true })` skips the pop animation. Sheets drag down by the grabber or header. A redraw of the same screen keeps sideways scroll, open expanders and the focused field (`keepState` in `renderNow`).
- Tab headers in the iPhone app say how fresh the data is (`syncedText()`, refreshed every 30 s); Food skips it.
- Settings is a grouped list (`Pages.settings` with no `focus`); each group opens one section as its own page (`App.open('settings', { focus })`: profile, goal, sleep, notify, health, watch, coach, look, data). New settings go in a section, not on the list.
- Today changes with the time of day: before 11 recovery leads, from 19 the focus card (wind down, tomorrow's plan) leads. `checkInCard` asks the unanswered habits inline (yesterday's until 5 pm). Key metrics follow `profile.todayTiles` (`editMetrics`). Future days on the week strip show a planned workout and open it.
- Food: empty meals fold into one line except the one due now; `profile.favFoods` (star on a logged item) and `profile.savedMeals` ("Save as a meal") lead the search; `weekFood` is the 7-day card. Imperial shows food amounts in oz / fl oz (`qtyText`, `foodUnit`, `toGrams`, `fromGrams`); macros stay in grams.
- Train: a set that beats the lift's best says so at once (`prCheck` on set done, `draft.prSeen`). Load gauges wait for data. `weekRecap` shows on Sunday (week so far) and Monday (last week). Your own exercises carry muscles in `training.customEx` (`{ name: { p, s, bw } }`, `Sheet.exerciseMuscles`); `E.exerciseInfo` / `exerciseParts` read them (set by `context()`).
- Health category pages start with "This month" (`trendOf`: last 30 days vs the 30 before, 12+ days in each). "Summary for your doctor" (`doctorSummary`) makes a 90-day HTML file to share.
- Text wraps rather than clips at large sizes; check with the 135% run (bigtext.js in the scratchpad pattern: set `--fs` to 1.35px).

## iPhone features driven by the page
- `HealthSync.pushWidget()` sends `{ type: 'widget', json }` (today's scores, water, next plan) for widgets and complications, debounced, only when something changed. `HealthSync.workoutActivity()` drives the workout Live Activity (`{ type: 'live', action: 'start' | 'update' | 'end', json }`) from `App.saveDraft`.
- Water: `HealthSync.waterOut('add' | 'remove', entry)` saves logged water to Apple Health (`{ type: 'water' | 'unwater' }`) unless `profile.waterToHealth === false`. The app skips its own samples when reading.
- Notifications: `Notify.plan()` (on data changes and coming back) schedules water nudges (`water0-2`, only while behind the pace) and planned-workout reminders (`plan0-1`, 30 min before), and sends `{ type: 'prefs', json: { morning, waterNudges } }`; the app sends "Recovery is ready" itself when last night's sleep arrives in the background. Preferences: `profile.notifyMorning`, `waterNudges`, `planReminders`, `bedReminder`.
- Claude coach with the person's own key: in the iPhone app `Coach.keyAction('status' | 'prompt' | 'clear')` (the app's own secure prompt; the key lives in the Keychain and never reaches the page) and `Coach.mode()` is 'backend' with either a server or a key. Without a server, `call` goes through `{ type: 'coach', id, messages }` and the app streams the server's events back to `BaselineBridge.coach(id, ev)`; `coachCancel` stops it. The app's copy of the model, system prompt and tools is `ios/Baseline/coach.json`, generated from `server/coach.mjs` by `server/export-config.mjs` (CI checks it's current).
- Watch: the context also carries `water` and a `library` of exercises; the watch sends `water`, `add` and `remove` as well.

## Food database and barcodes
- `foods-usda.json` (next to `index.html`, bundled in the iPhone app) is USDA FoodData Central's Foundation Foods and SR Legacy, about 7,800 foods per 100 g with their portions, rows shaped like `FOODS`. It's built by `tools/foods/build-usda.mjs` in `.github/workflows/foods.yml` (CI has internet; this sandbox doesn't), which commits the file. Don't edit it by hand. `FoodDB` loads it on the first search and lists matches under "More foods", after the built-in list; ids are `'u' + fdcId`. Without the file, search works as before.
- Barcodes: your own products first (`myFoods` entries with `code`, per 100 g, added with `Sheet.addProduct` when a scan finds nothing; `FoodNet.mine` turns them into foods), then Open Food Facts (with the pack photo). The camera screen is the app's own (`BarcodeScanner.swift`, `ScanOverlay`): a frame that limits recognition to the cut-out, a scan line, the torch and "Type the number", which comes back to the page as error `manual`. The food log's scan view opens the camera at once and always offers typing the number (the only way on the web).

## Finish pass (Oct 2026)
- First launch in the iPhone app: nothing syncs until the person taps "Connect Apple Health" on `Pages.welcome` (the Health permission sheet comes after an explanation). `HealthSync.hold` blocks `maybeSync`; `App.boot` asks the app `{ type: 'healthStatus' }` (reply `{ asked }`) and holds only on a fresh install that hasn't been asked. `welcomed` in localStorage: '1' connected, 'later' for "Not now" (the banner's Sync still works). CI's log check accepts `sync request` or `health status request`.
- The first sync reads 35 days (`FIRST`), so the 30-day baselines are complete at once. `Store.applyImport` applies the whole import in memory before writing, so no screen draws a half-synced day.
- Selected states (chips, mini buttons, yes/no, day pickers) use `--seg-on`, never white. `.tile2` tiles inside a card lose their boxes and are split by hairlines (shared rule in the CSS).
- Feels native, not like a web page: no text selection or long-press callouts except in fields and coach messages, no pinch or focus zoom, no link previews.
- Keyboard: `visualViewport` sets `--kb` (keyboard height) and `body.kb-open`; sheets sit on top of the keyboard and the tab bar and floating bars step aside while typing.
- Never a black screen: the script right after `<main id="view">` shows "Baseline couldn't start" with the error when nothing has drawn (an error, or nothing after 15 s), and sends the first errors to the app log (`{ type: 'log', text }`). The app reloads the page when iOS ends its process (`webViewWebContentProcessDidTerminate`) and when it's missing on return to the foreground.
- Settings has an About section (`APP_VERSION`, data sources with their licences, privacy). Bump `APP_VERSION` with a release.

## Workout page
- `Pages.session` is the workout view: route map (coloured by pace, start and finish), stat tiles, heart rate over time on the zones plus time in each zone, pace (speed for cycling), splits per km / mile (pace, heart rate, elevation) and elevation. Each part shows only when its data exists.
- Detail comes from `WD.get(s0)`: in the iPhone app the bridge request `{ type: 'workout', start, end, width, dark }` (`HealthSync.workout`, `HealthReader.workoutDetail` + `RouteMap.snapshot`), cached per workout and theme; the sample person gets `DEMO.workoutDetail`; otherwise only the day doc. Shape: `hr [[sec, bpm]]` (10 s), `dist [[sec, m]]` (cumulative), `route [[sec, lat, lon, alt, m]]` (≤ 500 points, alt -9999 when unknown), `climb`, `tempC`, `humidity`, `indoor`, `steps`, `map { img, w, h, xy }` (Apple Maps picture and each route point's place on it; the page draws the route).
- Workout docs from the sync carry `hrs` (heart rate per minute, null for gaps) so the chart works offline and for imported exports.
- Route and distance access (`detailTypes` in HealthReader) is asked with everything else on a new install, and the first time a workout opens on earlier ones.
- `Charts.timeLine({ pts, dur, bands, invert, ticks })` draws a measure over elapsed time.

## Models (Oct 2026 review)
- Normals are robust: `robustNormal(vals, prior)` drops days more than 2.5 SDs (by median absolute deviation) from the median, so a sick week or a night of drinks doesn't stretch the normal, and leans the SD on a typical spread (`SPREAD`: lnHRV 0.15, RHR 2.5, breathing 0.5, temperature 0.25) as if it were 5 more days, which only matters early on. `winStats` (the other baselines) uses it too, without a prior.
- HRV measured only in the daytime (`hrvSrc: 'day'`, watch off overnight) is never compared with the overnight normal: it's left out of the HRV baseline, recovery and the HRV effect outcome (`nightHrv`). Recovery then runs on resting heart rate and sleep. A night with one or two HRV readings weighs less in recovery (`night.hrv.length`).
- Stress measures heart rate above your calm daytime heart rate (`hrCalm`: 10th percentile of the last 14 days' still half hours; resting + 12 until there are two weeks), over 18% of the heart-rate reserve, not above resting + 4: sitting still runs 10–20 bpm above Apple's resting heart rate, differently for everyone.
- `C.bodySigns(d)`: wrist temperature, resting heart rate, breathing rate and HRV well off normal. Two or more together put "Take it easy today" at the top of Today and Highlights, and drop the strain target to 5–10.
- Sleep score interruptions count time awake after first falling asleep (latency is already in efficiency).

## Next steps (in order)
1. ~~Polish~~ (done, Oct 2026): Today in ~1.5 screens, one add button on Food, 44 px targets and 11 px+ scalable text, forgiving streaks with pauses, lazy-drawn Health.
2. ~~Honest insights~~ (done, Oct 2026): ranges and Clear / Likely / Not clear yet labels on habit and activity effects, adjusted for weekends, training load and exams, two-week experiments. Not done: Oura-style monthly stress load.
3. ~~Claude coach~~ (done, Oct 2026): backend in `server/`, editable memory, six tools with confirm/undo, inline charts, rare check-in notes, day-specific starting points. Not done: Claude-written check-in notes (they're local rules today), and food describe/photo through the backend.
5. Daily-use pass (Oct 2026): done as above. Not done: imperial for temperature.
6. Watch app (Oct 2026): built and compiled in CI, not yet run on a watch. Complications, the workout Live Activity and editing exercises on the watch followed in the real-app pass.
7. Real-app pass (Oct 2026): done as above. Not yet run on a device: widgets, Live Activity, complications, background delivery, the own-key coach.
4. ~~Data pipeline~~ (done, Oct 2026): one aggregation for export and JSON, new Health types, habits answered from data, the `HealthSync` bridge and an iOS shell in `ios/` (builds and launches in CI). Next: run the iOS app on a device with real Health data, background delivery, widgets, a Live Activity for workouts and a Watch complication.
