// Writes the coach's model, system prompt and tools to ios/Baseline/coach.json, for the iPhone app's built-in coach
// (the person's own API key in the Keychain, no server). The app sends them exactly as the server does, so both
// backends behave the same. CI runs this and fails if the committed copy differs, so it can't drift.
//
//   cd server && node export-config.mjs

import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { MODEL, SYSTEM, TOOLS } from './coach.mjs';

const out = fileURLToPath(new URL('../ios/Baseline/coach.json', import.meta.url));
// no spacing and a fixed key order, so the file is byte-stable
writeFileSync(out, JSON.stringify({ model: MODEL, system: SYSTEM, tools: TOOLS }));
console.log(`wrote ${out}`);
