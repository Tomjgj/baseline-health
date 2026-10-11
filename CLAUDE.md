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

## Next steps (in order)
1. ~~Polish~~ (done, Oct 2026): Today in ~1.5 screens, one add button on Food, 44 px targets and 11 px+ scalable text, forgiving streaks with pauses, lazy-drawn Health.
2. Honest insights: ranges and Clear / Likely / Not clear yet labels on habit effects, corrections for weekday, strain and exams, two-week experiments.
3. Claude coach with editable memory and confirm/undo actions (needs the backend).
4. Data pipeline from Apple Health, then the iOS app.
