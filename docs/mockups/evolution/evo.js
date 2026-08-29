/* Trading Up — stage pips in the card header.
   The same pips read against a different "owned" pool per mode: the current
   Classic run (GameCore.instances), the current Gauntlet Showcase
   (GauntletRun.showcase), or the permanent all-time Binder (Binder).
   Data mirrors CardDatabase / GauntletEconomy; art is the real ../art/*.svg.
   Static mockup: no app code is imported or changed. */

// ------------------------------------------------------------- palette (Theme.swift)

const ELEM = {
  fire:     { pal: ['#ffd15c', '#ff7a1a', '#e01f1f', '#5c1004'], tint: '#ff9a6b', label: 'Fire' },
  rock:     { pal: ['#f0c27a', '#c98a3c', '#8a5a2b', '#3d2413'], tint: '#e0b483', label: 'Rock' },
  water:    { pal: ['#9fe8ff', '#39a7ff', '#1e5bd6', '#0a2a66'], tint: '#8fd3ff', label: 'Water' },
  grass:    { pal: ['#c6f68d', '#5fd35f', '#2f9e44', '#12481f'], tint: '#9fe08a', label: 'Grass' },
  electric: { pal: ['#fff3a3', '#ffd21a', '#f5a300', '#6b4a00'], tint: '#ffdf66', label: 'Electric' },
  shadow:   { pal: ['#d9b3ff', '#9b5cf6', '#5b2bb3', '#1f0d3d'], tint: '#c6a3ff', label: 'Shadow' },
};
const RARITY = {
  common:   { accent: '#8a94a6', label: 'Common' },
  uncommon: { accent: '#3fbf7f', label: 'Uncommon' },
  rare:     { accent: '#3b82f6', label: 'Rare' },
  ultra:    { accent: '#b06cf7', label: 'Ultra Rare' },
};

// Each set is themed by a signature element (Theme.theme(forSet:)); the pips take
// that *set* colour, not the individual card's element — so a whole set reads as
// one family. Set 1 Emberfall = fire, 2 Tidecaller = water, 3 Verdspire = grass,
// 4 Voltcrest = electric, 5 Umbral Reach = shadow.
const SET_THEME = { 1: 'fire', 2: 'water', 3: 'grass', 4: 'electric', 5: 'shadow' };
const setOf = id => parseInt(String(id).slice(1), 10) || 0;   // 'S1-004' -> 1
const setTintOf = set => ELEM[SET_THEME[set] || 'shadow'].tint;

// ------------------------------------------------------------- real Set 1 data

const C = {};
function def(id, number, name, el, rarity, lineId, stage, stageCount, value) {
  C[id] = { id, set: setOf(id), number, name, el, rarity, lineId, stage, stageCount, value };
  return C[id];
}
// Line A — Emberpup (3-stage fire)
def('S1-001', 1, 'Emberpup',    'fire', 'common',   'A', 1, 3, 0.36);
def('S1-002', 2, 'Cinderhound', 'fire', 'uncommon', 'A', 2, 3, 1.09);
def('S1-003', 3, 'Pyrewolf',    'fire', 'rare',     'A', 3, 3, 3.40);
// Line E — Ashling (2-stage fire)
def('S1-019', 19, 'Ashling',  'fire', 'common',   'E', 1, 2, 0.39);
def('S1-020', 20, 'Cendrake', 'fire', 'uncommon', 'E', 2, 2, 1.20);
// Line F — Flicktail (2-stage fire)
def('S1-021', 21, 'Flicktail', 'fire', 'common',   'F', 1, 2, 0.31);
def('S1-022', 22, 'Emberdon',  'fire', 'uncommon', 'F', 2, 2, 2.15);
// Line R — Pebblit (3-stage ROCK, but still in Emberfall/Set 1 → ember pips)
def('S1-004', 4, 'Pebblit',    'rock', 'common',   'R', 1, 3, 0.40);
def('S1-005', 5, 'Boulderkin', 'rock', 'uncommon', 'R', 2, 3, 0.98);
def('S1-006', 6, 'Magmalith',  'rock', 'rare',     'R', 3, 3, 3.82);
// Singles
def('S1-035', 35, 'Wispfox', 'fire', 'common',   'x', 1, 1, 0.32);
def('S1-045', 45, 'Magmaw',  'fire', 'uncommon', 'x', 1, 1, 1.14);

// ------------------------------------------------------------- helpers

const money = v => '$' + v.toFixed(2);
const pad3 = n => String(n).padStart(3, '0');

function cardVars(card) {
  const e = ELEM[card.el];
  const rarity = card.rarity;
  const set = card.set != null ? card.set : setOf(card.id || '');
  const frame = rarity === 'ultra'
    ? 'linear-gradient(135deg, #ffd54a, #ff8ad6, #b06cf7)'
    : `linear-gradient(135deg, ${RARITY[rarity].accent}, color-mix(in srgb, ${RARITY[rarity].accent} 62%, #0b0e14))`;
  return `--el1:${e.pal[0]};--el2:${e.pal[1]};--el3:${e.pal[2]};--el-tint:${e.tint};`
       + `--set-tint:${setTintOf(set)};`
       + `--rar-accent:${RARITY[rarity].accent};--rar-frame:${frame};`;
}

/** Header stage pips that REPLACE the element label (top-right of the card).
    state: {owned:[stages], now:stage|0}. Solid = owned, lit = this pull, hollow = missing.
    A one-pip cluster (a single) never draws a connector, so “not a line” reads instantly. */
function headPips(c, state) {
  const present = s => state.owned.includes(s) || state.now === s;
  const parts = [];
  for (let s = 1; s <= c.stageCount; s++) {
    if (s > 1) parts.push(`<span class="lnk ${present(s - 1) && present(s) ? 'have' : ''}"></span>`);
    const now = state.now === s;
    parts.push(`<span class="pip ${now ? 'now' : (state.owned.includes(s) ? 'have' : '')}"></span>`);
  }
  const held = state.owned.length + (state.now && !state.owned.includes(state.now) ? 1 : 0);
  return `<span class="tc-pips" title="${held} / ${c.stageCount} stages">${parts.join('')}</span>`;
}

/** A trading card whose top-right shows the stage pips instead of the element label. */
function card(c, opts = {}) {
  const w = opts.w || 168;
  return `
  <div class="tcard ${c.rarity}" style="--w:${w};${cardVars(c)}">
    <div class="frame"></div>
    <div class="tc-head"><span class="tc-name">${c.name}</span>${headPips(c, opts.headPips)}</div>
    <div class="tc-art"><img src="../art/${c.id}.svg" alt="${c.name}" loading="lazy"></div>
    <div class="tc-meta"><span><i class="gem"></i>Emberfall</span><span class="mono">${pad3(c.number)} / 050</span></div>
    <div class="tc-val"><span class="tc-rar">${RARITY[c.rarity].label.toUpperCase()}</span><span class="tc-money">${money(c.value)}</span></div>
  </div>`;
}

// =================================================================== MODES

/* How "owned" (a solid pip) is scoped in each place the pips appear — drawn
   straight from the real rules:
   • Classic    → GameCore.instances (this run); one-time Economy.evolutionBonus
                  on completion; wiped by newGame(), a line re-opens on a sale.
   • Gauntlet   → GauntletRun.showcase (this run, slot-capped); GauntletCore.aura
                  lifts a complete line by evoLineBonus (+125%) while it stands.
   • Binder     → the permanent Binder: best copy ever owned, spans every run and
                  Gauntlet, only grows. A browser, so there is no "this pull". */
const MODES = {
  classic: {
    tab: 'Classic — this run', ownedLabel: 'In this run', pull: true,
    headline: 'Classic Mode · the current run’s collection',
    rows: [
      ['Solid pip', 'A stage in your <b>current run’s collection only</b> — cards from past runs don’t count here.'],
      ['Line bonus', 'Holding every stage pays a <b>one‑time cash bonus</b> the instant the line is whole.'],
      ['Resets', 'Wiped on <b>New Game</b>, and a line re‑opens if you <b>sell a stage</b>. Your all‑time Binder is tracked separately.'],
    ],
  },
  gauntlet: {
    tab: 'Gauntlet — this Showcase', ownedLabel: 'In this Showcase', pull: true,
    headline: 'Gauntlet Mode · the current run’s Showcase',
    rows: [
      ['Solid pip', 'A stage <b>standing in the Showcase</b> you’re building this run (capped by your slots).'],
      ['Line bonus', 'A complete line lifts <b>Aura by +125%</b> for as long as every stage stays in the Showcase.'],
      ['Resets', 'Scoped to <b>this run</b>. Drop a stage for space and the bonus <b>switches off</b> until the line is whole again.'],
    ],
  },
  binder: {
    tab: 'Binder — main menu', ownedLabel: 'In the Binder', pull: false,
    headline: 'Main‑menu Binder · the all‑time collection',
    rows: [
      ['Solid pip', 'Any stage in your <b>global Binder</b> — every best copy you’ve ever owned, across all Classic runs and Gauntlet.'],
      ['No pull', 'A <b>browsing view</b>: no card‑in‑hand and no live bonus — just which stages you’ve ever landed.'],
      ['Resets', '<b>Only ever grows.</b> New Game and lost Gauntlet runs never erase it.'],
    ],
  },
};
const MODE_ORDER = ['classic', 'gauntlet', 'binder'];

/** In a pull mode the "now" pip lights up; in the Binder there is no pull, so a
    pulled stage simply reads as owned (solid). */
function forMode(state, mode) {
  if (mode.pull) return state;
  const owned = state.now && !state.owned.includes(state.now)
    ? state.owned.concat(state.now) : state.owned.slice();
  return { owned, now: 0 };
}

// ------------------------------------------------------------- scenarios (mode-neutral)

const SCENARIOS = [
  ['Singles — one pip, never linked', [
    [C['S1-035'], { owned: [], now: 1 }, 'Single', 'One lone pip, no track — this card has no line.'],
    [C['S1-045'], { owned: [1], now: 0 }, 'Single, owned', 'Solid and alone — already yours, nothing to chain.'],
  ]],
  ['Two‑stage lines — a pair', [
    [C['S1-019'], { owned: [], now: 1 }, 'Base of a pair', 'Stage 1 present · stage 2 still hollow.'],
    [C['S1-020'], { owned: [1], now: 2 }, 'Pair complete ✦', 'Both stages present — the line is whole.', true],
    [C['S1-022'], { owned: [], now: 2 }, 'Top of a pair', 'Stage 2 present · the base below is missing.'],
    [C['S1-021'], { owned: [2], now: 1 }, 'Pair complete ✦', 'Base fills in under a top you had — line whole.', true],
  ]],
  ['Three‑stage lines — the full track', [
    [C['S1-001'], { owned: [], now: 1 }, 'Line begins · 1 / 3', 'Only the base is present so far.'],
    [C['S1-002'], { owned: [1], now: 2 }, 'Building · 2 / 3', 'Base present · one stage still to land.'],
    [C['S1-003'], { owned: [1, 2], now: 3 }, 'Line complete ✦', 'All three present — the full evolution.', true],
    [C['S1-002'], { owned: [3], now: 2 }, 'Bridging · 2 / 3', 'Top and middle present · the base is still out.'],
  ]],
  ['Pip colour follows the set, not the card’s element', [
    [C['S1-005'], { owned: [1], now: 2 }, 'A Rock line in Emberfall', 'Pebblit’s line is Rock — but it lives in Emberfall (Set 1), so the pips glow ember, the set’s colour. The element still reads in the art and the ● gem.'],
    [C['S1-006'], { owned: [1, 2], now: 3 }, 'Same set, same pips ✦', 'At the finish the pips are still ember — every card in a set shares one pip colour, however its own element differs.', true],
  ]],
];

// ------------------------------------------------------------- fragment builders

function tabsHTML(activeKey) {
  return MODE_ORDER.map(k =>
    `<button class="mode-tab ${k === activeKey ? 'on' : ''}" data-mode="${k}">${MODES[k].tab}</button>`
  ).join('');
}

function scopeHTML(mode) {
  const rows = mode.rows.map(([k, v]) =>
    `<div class="scope-row"><div class="scope-key">${k}</div><div class="scope-val">${v}</div></div>`
  ).join('');
  return `<h5>${mode.headline}</h5>${rows}`;
}

function legendHTML(mode) {
  const fireVars = cardVars({ el: 'fire', rarity: 'uncommon', set: 1 });
  const pull = mode.pull ? `<span><span class="pip now"></span> This pull</span>` : '';
  return `<div class="pip-legend" style="${fireVars}">
      ${pull}
      <span><span class="pip have"></span> ${mode.ownedLabel}</span>
      <span><span class="pip"></span> Missing</span>
      <span class="pip-legend-note">Track length tells the type — 1 pip is a single, 2 a pair, 3 a full line.</span>
    </div>`;
}

function groupsHTML(mode) {
  return SCENARIOS.map(([title, cells]) => `
    <div class="pip-group">
      <h4>${title}</h4>
      <div class="pip-row">${cells.map(([c, st, t, sub, win]) => `
        <figure class="pip-ex${win ? ' win' : ''}">
          ${card(c, { w: 168, headPips: forMode(st, mode) })}
          <figcaption><b>${t}</b><span>${sub}</span></figcaption>
        </figure>`).join('')}</div>
    </div>`).join('');
}

// =================================================================== MOUNT

(function () {
  const tabsEl = document.getElementById('mode-tabs');
  const scopeEl = document.getElementById('scope');
  const legendEl = document.getElementById('pip-legend');
  const groupsEl = document.getElementById('pip-groups');
  const requested = new URLSearchParams(location.search).get('mode');
  let active = MODES[requested] ? requested : 'classic';

  function render() {
    const mode = MODES[active];
    tabsEl.innerHTML = tabsHTML(active);
    scopeEl.innerHTML = scopeHTML(mode);
    legendEl.innerHTML = legendHTML(mode);
    groupsEl.innerHTML = groupsHTML(mode);
  }

  tabsEl.addEventListener('click', (e) => {
    const btn = e.target.closest('.mode-tab');
    if (!btn) return;
    active = btn.dataset.mode;
    render();
  });

  render();
})();
