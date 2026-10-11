// Checks the coach backend without calling the API: a stand-in client records the request and replays a reply.
import assert from 'node:assert/strict';
import { handleCoach, SYSTEM, TOOLS, MODEL } from './coach.mjs';

const env = { ANTHROPIC_API_KEY: 'test-key', COACH_ACCESS_CODE: 'open-sesame', ALLOWED_ORIGINS: 'https://app.example' };
const reply = { content: [{ type: 'thinking', thinking: '', signature: 'sig' }, { type: 'text', text: 'Hi there.' }], stop_reason: 'end_turn', stop_details: null, model: MODEL, usage: { input_tokens: 10, output_tokens: 3 } };
let seen = null;
const fakeClient = { beta: { messages: { stream(params) {
  seen = params;
  const handlers = {};
  return { on(ev, fn) { handlers[ev] = fn; return this; }, async finalMessage() { handlers.text?.('Hi '); handlers.text?.('there.'); return reply; } };
} } } };
const req = (body, { code = 'open-sesame', origin = 'https://app.example', method = 'POST' } = {}) => new Request('https://coach.example/api/coach', {
  method, headers: { authorization: `Bearer ${code}`, origin, 'content-type': 'application/json' }, body: method === 'POST' ? JSON.stringify(body) : undefined });
const lines = async (res) => (await res.text()).trim().split('\n').map((l) => JSON.parse(l));

// wrong access code
let res = await handleCoach(req({ messages: [{ role: 'user', content: 'hi' }] }, { code: 'nope' }), env, { client: fakeClient });
assert.equal(res.status, 401);
// CORS: only the allowed origin is echoed
res = await handleCoach(req(null, { method: 'OPTIONS' }), env);
assert.equal(res.headers.get('access-control-allow-origin'), 'https://app.example');
res = await handleCoach(req(null, { method: 'OPTIONS', origin: 'https://evil.example' }), env);
assert.equal(res.headers.get('access-control-allow-origin'), null);
// malformed conversation is refused before any call
res = await handleCoach(req({ messages: [{ role: 'assistant', content: 'x' }] }), env, { client: fakeClient });
assert.equal(res.status, 400);
// ping
res = await handleCoach(req({ ping: true }), env, { client: fakeClient });
assert.deepEqual(await res.json(), { ok: true, model: MODEL });
// a normal turn streams text, then the whole message
seen = null;
res = await handleCoach(req({ messages: [{ role: 'user', content: [{ type: 'text', text: '<app-data>…</app-data>' }, { type: 'text', text: 'How did I sleep?' }] }] }), env, { client: fakeClient });
assert.equal(res.status, 200);
const out = await lines(res);
assert.deepEqual(out.filter((x) => x.t === 'text').map((x) => x.v).join(''), 'Hi there.');
assert.equal(out.at(-1).t, 'done');
assert.deepEqual(out.at(-1).message.content, reply.content);
// the server, not the page, picks the model, system prompt and tools
assert.equal(seen.model, 'claude-opus-5-5');
assert.equal(seen.system, SYSTEM);
assert.equal(seen.tools, TOOLS);
assert.deepEqual(seen.thinking, { type: 'adaptive' });
assert.equal(seen.fallbacks, 'default');
assert.deepEqual(seen.betas, ['server-side-fallback-2026-07-01']);
// every tool is strict, with every property required and nothing extra allowed
for (const t of TOOLS) {
  assert.equal(t.strict, true, t.name);
  assert.equal(t.input_schema.additionalProperties, false, t.name);
  assert.deepEqual([...t.input_schema.required].sort(), Object.keys(t.input_schema.properties).sort(), t.name);
}
// an API error arrives as an error line, not a broken stream
const failing = { beta: { messages: { stream() { return { on() { return this; }, finalMessage: () => Promise.reject(new Error('boom')) }; } } } };
res = await handleCoach(req({ messages: [{ role: 'user', content: 'hi' }] }), env, { client: failing });
assert.equal((await lines(res)).at(-1).t, 'error');
console.log('coach backend: all checks passed');
