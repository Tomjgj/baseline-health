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
- Health: cards below the fold go through `lazy(key, build, guessHeight)`.
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

## Next steps (in order)
1. ~~Polish~~ (done, Oct 2026): Today in ~1.5 screens, one add button on Food, 44 px targets and 11 px+ scalable text, forgiving streaks with pauses, lazy-drawn Health.
2. ~~Honest insights~~ (done, Oct 2026): ranges and Clear / Likely / Not clear yet labels on habit and activity effects, adjusted for weekends, training load and exams, two-week experiments. Not done: Oura-style monthly stress load.
3. ~~Claude coach~~ (done, Oct 2026): backend in `server/`, editable memory, six tools with confirm/undo, inline charts, rare check-in notes, day-specific starting points. Not done: Claude-written check-in notes (they're local rules today), and food describe/photo through the backend.
4. ~~Data pipeline~~ (done, Oct 2026): one aggregation for export and JSON, new Health types, habits answered from data, the `HealthSync` bridge and an iOS shell in `ios/` (builds and launches in CI). Next: run the iOS app on a device with real Health data, background delivery, widgets, a Live Activity for workouts and a Watch complication.
