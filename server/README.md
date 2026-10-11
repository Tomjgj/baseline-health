# Baseline coach server

A small backend for the Claude coach in `index.html`. It holds the Anthropic API key so the page never does, fixes the model (`claude-opus-5-5`), system prompt and tools, and streams Claude's replies back to the page.

The page sends the conversation, including a snapshot of your data. Claude can propose six actions: log food, tag an activity, answer habits, move a planned workout, remember a note, or show a chart. The page runs a proposal only after you tap Confirm, and each one can be undone. Charts are the exception: they only read your data, so they appear without asking.

## What it needs

| Variable | What it is |
| --- | --- |
| `ANTHROPIC_API_KEY` | Your key from console.anthropic.com. A secret. |
| `COACH_ACCESS_CODE` | Any long random string you choose. You type the same code into the app (Settings → Claude coach), so someone who finds the server's address can't spend your key. A secret. |
| `ALLOWED_ORIGINS` | The address the app is served from, e.g. `https://you.github.io`, or `*` for any. |

## Option 1: Cloudflare Worker (free tier is plenty)

```
cd server
npm install
npx wrangler login
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put COACH_ACCESS_CODE
npx wrangler deploy
```

Wrangler prints the Worker's address, e.g. `https://baseline-coach.<you>.workers.dev`. In the app, open Settings → Claude coach, enter that address and your access code, and tap **Save and test**.

## Option 2: run it on your computer

```
cd server
npm install
ANTHROPIC_API_KEY=sk-ant-... COACH_ACCESS_CODE=pick-something node dev.mjs
```

Open http://localhost:8787. The server serves the app there too. In Settings → Claude coach, enter `http://localhost:8787/api/coach` and your code.

## Tests

`npm test` checks the access code, CORS, request validation and the streamed reply format. It uses a stand-in for the API, so it needs no key and costs nothing.

## Notes

- Requests use adaptive thinking at `medium` effort and prompt caching. They opt into server-side refusal fallbacks (`fallbacks: "default"`), so a request a safety classifier declines is re-run on Anthropic's recommended fallback model instead of failing.
- The system prompt and tool list never change during a conversation. Your data reaches Claude inside the messages: a snapshot at the start, plus a fresh one whenever it changes. This keeps Claude's earlier reasoning valid and the cache warm.
- The chat history lives in the browser (`localStorage`), not on the server. The server stores nothing.
