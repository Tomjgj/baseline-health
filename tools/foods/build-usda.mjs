// Builds foods-usda.json (next to index.html) from USDA FoodData Central: Foundation Foods and SR Legacy, both public domain.
// Runs in CI (.github/workflows/foods.yml), which has internet access: node tools/foods/build-usda.mjs
// Each food is [fdcId, name, kcal, protein, carbs, fat, fiber, servings, group], per 100 g, servings as "label:grams|…",
// the same row shape as the built-in FOODS list in index.html.
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const PAGE = 'https://fdc.nal.usda.gov/download-datasets';
// groups not worth searching in a personal food log
const SKIP_GROUPS = /baby foods|infant/i;
const SKIP_NAMES = /\binfant formula\b|\bbaby food\b|\bUSDA Commodity\b|\bCHILD NUTRITION\b/i;

/** Finds the newest zip of one dataset on the download page (filenames carry dates, so they change). */
async function zipUrl(pattern) {
  for (const page of [PAGE, PAGE + '.html']) {
    try {
      const html = await (await fetch(page)).text();
      const links = [...html.matchAll(/href="([^"]+\.zip)"/g)].map((m) => new URL(m[1], page).href).filter((u) => pattern.test(u));
      if (links.length) return links.sort().pop();
    } catch {}
  }
  throw new Error(`no download link matching ${pattern}`);
}

async function download(url, dir) {
  console.log('downloading', url);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
  const file = join(dir, url.split('/').pop());
  writeFileSync(file, Buffer.from(await res.arrayBuffer()));
  const out = join(dir, url.split('/').pop().replace(/\.zip$/, ''));
  execFileSync('unzip', ['-q', '-o', file, '-d', out]);
  return out;
}

/** The folder inside an unzipped dataset that holds food.csv. */
function csvDir(dir) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (name === 'food.csv') return dir;
    if (statSync(p).isDirectory()) { const d = csvDir(p); if (d) return d; }
  }
  return null;
}

/** A small CSV reader: quoted fields, doubled quotes, commas and newlines inside quotes. Returns objects keyed by header. */
function readCsv(file) {
  const text = readFileSync(file, 'utf8').replace(/^﻿/, '');
  const rows = [];
  let row = [], field = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (q) {
      if (ch === '"') { if (text[i + 1] === '"') { field += '"'; i++; } else q = false; }
      else field += ch;
    } else if (ch === '"') q = true;
    else if (ch === ',') { row.push(field); field = ''; }
    else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && text[i + 1] === '\n') i++;
      row.push(field); field = '';
      if (row.length > 1 || row[0] !== '') rows.push(row);
      row = [];
    } else field += ch;
  }
  if (field !== '' || row.length) { row.push(field); rows.push(row); }
  const head = rows.shift();
  return rows.map((r) => Object.fromEntries(head.map((k, i) => [k, r[i] ?? ''])));
}

const r1 = (v) => Math.round(v * 10) / 10;

function readDataset(dir) {
  const d = csvDir(dir);
  if (!d) throw new Error('no food.csv in ' + dir);
  const has = (f) => { try { statSync(join(d, f)); return true; } catch { return false; } };
  const foods = readCsv(join(d, 'food.csv'));
  const nutrients = readCsv(join(d, 'nutrient.csv'));
  // nutrient ids by meaning; Foundation Foods often give energy only as Atwater factors
  const idsOf = (test) => new Set(nutrients.filter(test).map((n) => n.id));
  const N = {
    kcal: idsOf((n) => n.name === 'Energy' && /kcal/i.test(n.unit_name)),
    kcalAtw: idsOf((n) => /^Energy \(Atwater (General|Specific)/.test(n.name) && /kcal/i.test(n.unit_name)),
    p: idsOf((n) => n.name === 'Protein'),
    f: idsOf((n) => n.name === 'Total lipid (fat)'),
    c: idsOf((n) => n.name === 'Carbohydrate, by difference'),
    cSum: idsOf((n) => n.name === 'Carbohydrate, by summation'),
    fiber: idsOf((n) => n.name === 'Fiber, total dietary'),
  };
  const val = new Map();
  for (const x of readCsv(join(d, 'food_nutrient.csv'))) {
    const a = parseFloat(x.amount);
    if (!Number.isFinite(a)) continue;
    let k = null;
    for (const key in N) if (N[key].has(x.nutrient_id)) { k = key; break; }
    if (!k) continue;
    const o = val.get(x.fdc_id) || {};
    if (o[k] == null) o[k] = a;
    val.set(x.fdc_id, o);
  }
  const groups = has('food_category.csv') ? Object.fromEntries(readCsv(join(d, 'food_category.csv')).map((g) => [g.id, g.description])) : {};
  const units = has('measure_unit.csv') ? Object.fromEntries(readCsv(join(d, 'measure_unit.csv')).map((u) => [u.id, u.name])) : {};
  const portions = new Map();
  if (has('food_portion.csv')) for (const x of readCsv(join(d, 'food_portion.csv'))) {
    const g = parseFloat(x.gram_weight);
    if (!(g > 0 && g < 5000)) continue;
    const unit = units[x.measure_unit_id];
    const amount = parseFloat(x.amount);
    const what = [unit && unit !== 'undetermined' ? unit : '', x.modifier || x.portion_description || ''].filter(Boolean).join(' ').replace(/\s+/g, ' ').trim();
    if (!what || /^(quantity not specified|guideline amount)/i.test(what)) continue;
    const label = `${Number.isFinite(amount) && amount > 0 ? +amount.toFixed(2) + ' ' : ''}${what}`.slice(0, 40) + ` (${Math.round(g)} g)`;
    const list = portions.get(x.fdc_id) || [];
    if (!list.some((p) => p.label === label)) list.push({ label: label.replace(/:/g, ' ').replace(/\|/g, '/'), g: Math.round(g), seq: +x.seq_num || 0 });
    portions.set(x.fdc_id, list);
  }
  const out = [];
  for (const f of foods) {
    const v = val.get(f.fdc_id);
    if (!v) continue;
    const kcal = v.kcal ?? v.kcalAtw;
    const c = v.c ?? v.cSum;
    if (kcal == null || v.p == null || v.f == null || c == null) continue;
    const group = groups[f.food_category_id] || '';
    const name = String(f.description || '').trim();
    if (!name || SKIP_GROUPS.test(group) || SKIP_NAMES.test(name)) continue;
    const serv = (portions.get(f.fdc_id) || []).sort((a, b) => a.seq - b.seq).slice(0, 4).map((p) => `${p.label}:${p.g}`);
    out.push([+f.fdc_id, name, Math.round(kcal), r1(v.p), r1(c), r1(v.f), r1(v.fiber || 0), serv.join('|'), group]);
  }
  return out;
}

export { readCsv, readDataset };
if (process.argv[1] === fileURLToPath(import.meta.url)) await main();

async function main() {
const dir = mkdtempSync(join(tmpdir(), 'usda-'));
const sets = [];
for (const [label, re] of [['Foundation Foods', /foundation_food_csv/i], ['SR Legacy', /sr_legacy_food_csv/i]]) {
  const url = await zipUrl(re);
  const rows = readDataset(await download(url, dir));
  console.log(label, rows.length, 'foods from', url.split('/').pop());
  sets.push({ label, file: url.split('/').pop(), rows });
}
// Foundation first: where both have a food of the same name, the newer analysis wins
const seen = new Set(), foods = [];
for (const s of sets) for (const r of s.rows) { const k = r[1].toLowerCase(); if (!seen.has(k)) { seen.add(k); foods.push(r); } }
foods.sort((a, b) => a[1].localeCompare(b[1]));
if (foods.length < 3000) throw new Error(`only ${foods.length} foods; the download format may have changed`);
const json = JSON.stringify({ v: 1, source: 'USDA FoodData Central (public domain)', sets: sets.map((s) => s.file), foods });
writeFileSync(join(ROOT, 'foods-usda.json'), json);
console.log(`wrote foods-usda.json: ${foods.length} foods, ${(json.length / 1e6).toFixed(2)} MB`);
}
