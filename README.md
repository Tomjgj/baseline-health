# Baseline Health

Personal health app, version 1.5. One self-contained page, `index.html`, with sample data, wrapped by the iPhone and Watch apps in `ios/`. Dark-first design with a liquid glass navigation layer, built for a phone-width column.

## Run it

Open `index.html` in a browser, or serve the folder:

```
python3 -m http.server 8000
```

Then visit http://localhost:8000. Outside Claude the app stores your logs in the browser's `localStorage` (see `initLocal()` in `index.html`). Inside Claude it used the artifact's private database instead.

## The Claude coach

The coach needs a small server that holds your Anthropic API key, so the key never sits in the page. It's in `server/`; see `server/README.md` (about five minutes on Cloudflare Workers, or `node dev.mjs` locally). Then open Settings → Claude coach in the app and enter the server's address and your access code.

## Apple Health

- **Web:** Settings → Data → Import. Choose the `export.zip` from the Health app, or a `baseline.health/1` JSON file.
- **iPhone app (`ios/`):** reads HealthKit directly and syncs each time it opens. See `ios/README.md`. CI builds it and launches it in the simulator; it hasn't yet run on a real iPhone.

## Where things live in `index.html`

- Styles: the first ~1,400 lines (design tokens and light/dark themes; the liquid glass rules sit just before the narrow-screen media query).
- Store (data layer): search for `async function init()`. It picks `db` mode (Claude artifact runtime) or `local` mode (localStorage).
- App boot: the last lines (`App.boot()`).
- Claude runtime hooks that only work inside Claude: `window.claude.use('db' | 'user' | 'sample' | 'downloads')`. The coach no longer needs `sample`: it talks to `server/` (search for `const Coach =`).

## Roadmap

1. Run the iOS app on a device with real Health data, then add HealthKit background delivery.
2. Widgets, a Live Activity for workouts, a Watch complication for stress, live Watch heart rate, and school/work blocks synced with Apple Calendar.

Design notes: `docs/fitness-overhaul.md` (Train), `docs/food-overhaul.md` (Food) and `docs/liquid-glass.md` (the glass layer). See `CLAUDE.md` for the working notes used by Claude Code.
