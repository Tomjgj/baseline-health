# Baseline Health

Personal health web app (mock-up stage, version 7). One self-contained page, `index.html`, with sample data. Dark-first design, built for a phone-width column.

## Run it

Open `index.html` in a browser, or serve the folder:

```
python3 -m http.server 8000
```

Then visit http://localhost:8000. Outside Claude the app stores your logs in the browser's `localStorage` (see `initLocal()` in `index.html`). Inside Claude it used the artifact's private database instead.

## Where things live in `index.html`

- Styles: the first ~800 lines (design tokens and light/dark themes).
- Store (data layer): search for `async function init()`. It picks `db` mode (Claude artifact runtime) or `local` mode (localStorage).
- App boot: the last lines (`App.boot()`).
- Claude runtime hooks that only work inside Claude: `window.claude.use('db' | 'user' | 'sample' | 'downloads')`. Replace these when moving to a real backend.

## Roadmap

1. Data pipeline: Apple Health export to app (deferred).
2. Claude coach through a small backend that holds the API key (never in the front end).
3. iOS app with HealthKit sync, live Watch heart rate, workouts and school/work blocks synced with Apple Calendar.

See `CLAUDE.md` for the working notes used by Claude Code.
