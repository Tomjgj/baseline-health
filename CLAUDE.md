# Baseline Health: notes for Claude Code

Single-file web app (`index.html`, ~8,500 lines, vanilla JS, no build step). Exported from a Claude artifact (version 7, 2026-10-11).

## Rules
- Keep it one self-contained page unless asked to split it.
- Dark-first "glass instrument" design: solid cards, floating glass tab bar, rounded numerals. Data colours: strain #3b8deb, sleep #8f7bf0, stress #db6a24, HRV #1aa394, heart rate #e0526e.
- All models are measured against the person's own baselines (30-day mean ± 1 SD).
- Trends say how sure they are: use `E.trendFit` and its labels (Clear, Likely, Not clear yet, Holding steady) rather than showing a raw first-to-last change.
- Never put an API key in front-end code. The Claude coach needs a backend function that holds the key.

## Storage
`Store.init()` uses `window.claude.use('db')` when running inside Claude and falls back to `localStorage` otherwise. Standalone, only the localStorage path runs.

## Next steps (in order)
1. Polish: Today screen on about 1.5 screens, 44 px touch targets and 11 px+ text outside Train and Food (the Today rings still use 10 px labels), lazy-draw the Health screen. Food and Train are done (one add button, forgiving streaks): see `docs/`.
2. Honest insights: ranges and Clear / Likely / Not clear yet labels on habit effects (training progress already has them, see `docs/fitness-overhaul.md`), corrections for weekday, strain and exams, two-week experiments.
3. Claude coach with editable memory and confirm/undo actions (needs the backend).
4. Data pipeline from Apple Health, then the iOS app.
