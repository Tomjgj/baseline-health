// Baseline Health: the Claude coach backend.
//
// The page never sees the API key. It sends the conversation (with a snapshot of the person's data in it);
// this function adds the fixed system prompt and tools, calls Claude, and streams the reply back as
// newline-delimited JSON: {"t":"text","v":"..."} while Claude writes, then {"t":"done","message":{...}}.
//
// Runs as a Cloudflare Worker (export default { fetch }), and under Node with dev.mjs.
// Environment:
//   ANTHROPIC_API_KEY   required
//   COACH_ACCESS_CODE   required: the page sends it as "Authorization: Bearer <code>", so a leaked URL can't spend your key
//   ALLOWED_ORIGINS     comma-separated origins allowed to call this (e.g. https://you.github.io); "*" allows any

import Anthropic from '@anthropic-ai/sdk';

export const MODEL = 'claude-opus-5-5';
const MAX_BODY = 600_000; // bytes; a long chat with data snapshots stays well under this
const MAX_MESSAGES = 120;

// Never changes within a conversation: the system prompt and tools must stay byte-identical so earlier
// thinking blocks stay valid and the prompt cache keeps hitting. Day-to-day data arrives in the messages.
export const SYSTEM = `You are the coach inside Baseline, the person's own health app. Each conversation starts with a snapshot of their data inside <app-data>; a later system message may carry a fresher snapshot, which replaces the earlier one.

How the app's numbers work: recovery (0-100) compares this morning's HRV, resting heart rate and sleep with their own last 30 days (67+ high, 34-66 moderate, below 34 low). Strain (0-21) is heart-rate training load for the day. Sleep score (0-100) weighs time asleep against need, efficiency, deep and REM share, regular timing and interruptions. Stress (0-100) comes from daytime heart rate above resting plus HRV below the daytime normal, while awake and still. Calorie targets come from an adaptive expenditure estimate. Habit effects are adjusted for weekends, training load and exam days and carry a label: Clear, Likely or Not clear yet. Only Clear and Likely effects are findings; never present a Not clear yet effect as one.

How to answer: they read on a phone. Lead with the answer, then a few short points. Quote real numbers from the data and never invent any; if something isn't in the data, say so. Patterns in their data are not proof of cause, so say "goes with" rather than "causes". You are not a doctor: for symptoms, injuries, medication or anything that sounds medical, suggest a professional. Use the units the snapshot names.

Tools: you can propose changes to their log with log_food, tag_activity, answer_habits and move_workout, and propose a note to remember with remember. Each one is shown to the person as a card they confirm or dismiss, so propose only what they asked for or clearly agreed to, and say in a sentence what you're proposing. A tool result tells you whether they confirmed it. Use the habit ids, plan ids and activity types listed in the snapshot, and dates as YYYY-MM-DD. When a trend is easier to see than to describe, call show_chart; the app draws it from their data and returns a short summary of the values.

Notes the person keeps in memory are listed in the snapshot. Use them, and propose remember only for lasting facts they'd want you to know next time (goals, exam dates, injuries, routines), not for one-off details.`;

const date = { type: 'string', description: 'A day as YYYY-MM-DD.' };
const tool = (name, description, properties, extra = {}) => ({
  name, description, strict: true, eager_input_streaming: true,
  input_schema: { type: 'object', properties, required: Object.keys(properties), additionalProperties: false, ...extra },
});
export const TOOLS = [
  tool('log_food', 'Propose adding foods to the food log. Estimate amounts and macros when the person describes a meal; the entry is marked as an estimate.', {
    date, meal: { type: 'string', enum: ['breakfast', 'lunch', 'dinner', 'snack'] },
    items: { type: 'array', description: 'One entry per food.', items: { type: 'object', additionalProperties: false, required: ['name', 'amount', 'kcal', 'protein_g', 'carbs_g', 'fat_g'],
      properties: { name: { type: 'string' }, amount: { type: 'string', description: 'For example "150 g" or "1 bowl".' }, kcal: { type: 'number' }, protein_g: { type: 'number' }, carbs_g: { type: 'number' }, fat_g: { type: 'number' } } } },
  }),
  tool('tag_activity', 'Propose tagging a block of the day (school, work, studying, an exam...) so its stress is tracked.', {
    date, type: { type: 'string', description: 'One of the activity types listed in the snapshot.' },
    start: { type: 'string', description: 'HH:MM, 24-hour.' }, end: { type: 'string', description: 'HH:MM, 24-hour.' },
    label: { type: 'string', description: 'A name for type "other"; empty otherwise.' },
  }),
  tool('answer_habits', 'Propose answers to habit questions for one day.', {
    date, answers: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['habit_id', 'yes'], properties: { habit_id: { type: 'string' }, yes: { type: 'boolean' } } } },
  }),
  tool('move_workout', 'Propose moving one planned workout to another day and time.', {
    plan_id: { type: 'string', description: 'A plan id from the snapshot.' }, from_date: date, to_date: date,
    time: { type: 'string', description: 'HH:MM, or empty to keep the planned time.' },
  }),
  tool('remember', 'Propose a short note for your memory about the person, which they can edit or delete in Settings.', {
    note: { type: 'string', description: 'One sentence, under 160 characters.' },
  }),
  tool('show_chart', 'Show a chart of one of their measures. Runs at once, without confirmation.', {
    metric: { type: 'string', enum: ['recovery', 'sleep_score', 'sleep_hours', 'strain', 'hrv', 'resting_hr', 'stress', 'weight', 'steps', 'calories', 'protein', 'active_energy'] },
    days: { type: 'integer', description: 'How many days back, 7 to 180.' },
    title: { type: 'string' },
  }),
];

const json = (status, body, headers) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json', ...headers } });
function cors(request, env) {
  const origin = request.headers.get('origin');
  const allowed = String(env.ALLOWED_ORIGINS || '').split(',').map((s) => s.trim()).filter(Boolean);
  const ok = origin && (allowed.includes('*') || allowed.includes(origin));
  return ok ? { 'access-control-allow-origin': origin, vary: 'origin', 'access-control-allow-headers': 'authorization, content-type', 'access-control-allow-methods': 'POST, OPTIONS' } : {};
}
function sameCode(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}
/** The page sends user, assistant and system turns; anything else is refused before it costs a call. */
function validMessages(messages) {
  if (!Array.isArray(messages) || !messages.length || messages.length > MAX_MESSAGES) return false;
  if (messages[0].role !== 'user') return false;
  return messages.every((m) => m && ['user', 'assistant', 'system'].includes(m.role) && (typeof m.content === 'string' || Array.isArray(m.content)));
}

export async function handleCoach(request, env, { client } = {}) {
  const ch = cors(request, env);
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: ch });
  if (request.method !== 'POST') return json(405, { error: { code: 'method', message: 'Use POST.' } }, ch);
  if (!env.COACH_ACCESS_CODE || !env.ANTHROPIC_API_KEY) return json(500, { error: { code: 'not_configured', message: 'The coach server is missing ANTHROPIC_API_KEY or COACH_ACCESS_CODE.' } }, ch);
  const auth = request.headers.get('authorization') || '';
  if (!sameCode(auth.replace(/^Bearer\s+/i, ''), env.COACH_ACCESS_CODE)) return json(401, { error: { code: 'unauthorized', message: 'Wrong access code.' } }, ch);
  const raw = await request.text();
  if (raw.length > MAX_BODY) return json(413, { error: { code: 'too_large', message: 'This chat is too long. Start a new one.' } }, ch);
  let body;
  try { body = JSON.parse(raw); } catch { return json(400, { error: { code: 'bad_request', message: 'Not JSON.' } }, ch); }
  if (body.ping) return json(200, { ok: true, model: MODEL }, ch);
  if (!validMessages(body.messages)) return json(400, { error: { code: 'bad_request', message: 'The conversation is malformed.' } }, ch);

  const anthropic = client || new Anthropic({ apiKey: env.ANTHROPIC_API_KEY });
  const enc = new TextEncoder();
  const { readable, writable } = new TransformStream();
  const out = writable.getWriter();
  const send = (obj) => out.write(enc.encode(JSON.stringify(obj) + '\n'));
  (async () => {
    try {
      const stream = anthropic.beta.messages.stream({
        model: MODEL,
        max_tokens: 16000,
        thinking: { type: 'adaptive' },
        output_config: { effort: 'medium' },
        // a declined request is re-run on Anthropic's recommended fallback model instead of failing
        betas: ['server-side-fallback-2026-07-01'],
        fallbacks: 'default',
        cache_control: { type: 'ephemeral' },
        system: SYSTEM,
        tools: TOOLS,
        messages: body.messages,
      }, { signal: request.signal });
      stream.on('text', (delta) => { send({ t: 'text', v: delta }); });
      const message = await stream.finalMessage();
      await send({ t: 'done', message: { role: 'assistant', content: message.content, stop_reason: message.stop_reason, stop_details: message.stop_details ?? null, model: message.model, usage: message.usage } });
    } catch (e) {
      const code = e instanceof Anthropic.RateLimitError ? 'rate_limited'
        : e instanceof Anthropic.AuthenticationError ? 'server_key'
        : e instanceof Anthropic.BadRequestError ? 'bad_request'
        : e instanceof Anthropic.APIUserAbortError ? 'cancelled'
        : e instanceof Anthropic.InternalServerError ? 'overloaded'
        : e instanceof Anthropic.APIConnectionError ? 'unreachable'
        : 'error';
      try { await send({ t: 'error', code, message: e?.message || 'Something went wrong.' }); } catch {}
    } finally {
      try { await out.close(); } catch {}
    }
  })();
  return new Response(readable, { status: 200, headers: { 'content-type': 'application/x-ndjson; charset=utf-8', 'cache-control': 'no-store', ...ch } });
}

export default { fetch: (request, env) => handleCoach(request, env || {}) };
