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

## Next steps (in order)
1. ~~Polish~~ (done, Oct 2026): Today in ~1.5 screens, one add button on Food, 44 px targets and 11 px+ scalable text, forgiving streaks with pauses, lazy-drawn Health.
2. ~~Honest insights~~ (done, Oct 2026): ranges and Clear / Likely / Not clear yet labels on habit and activity effects, adjusted for weekends, training load and exams, two-week experiments. Not done: Oura-style monthly stress load.
3. Claude coach with editable memory and confirm/undo actions (needs the backend).
4. Data pipeline from Apple Health, then the iOS app.
