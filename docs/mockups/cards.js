// Trading Up — mockup card renderer with procedural "sigil" art.
// Deterministic art from name+type so the iOS app can reproduce the exact same emblem.

const TYPE_PALETTES = {
  fire:     ['#ffd15c', '#ff7a1a', '#e01f1f', '#5c1004'],
  rock:     ['#f0c27a', '#c98a3c', '#8a5a2b', '#3d2413'],
  water:    ['#9fe8ff', '#39a7ff', '#1e5bd6', '#0a2a66'],
  grass:    ['#c6f68d', '#5fd35f', '#2f9e44', '#12481f'],
  electric: ['#fff3a3', '#ffd21a', '#f5a300', '#6b4a00'],
  shadow:   ['#d9b3ff', '#9b5cf6', '#5b2bb3', '#1f0d3d'],
};

const TYPE_META = {
  fire:     { emoji: '🔥', label: 'Fire' },
  rock:     { emoji: '🪨', label: 'Rock' },
  water:    { emoji: '💧', label: 'Water' },
  grass:    { emoji: '🌿', label: 'Grass' },
  electric: { emoji: '⚡', label: 'Electric' },
  shadow:   { emoji: '🌑', label: 'Shadow' },
};

function hashStr(s) {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); }
  return h >>> 0;
}

function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Symmetric mandala/crest emblem — deterministic from the seed string.
function makeSigil(seedStr, type) {
  const pal = TYPE_PALETTES[type] || TYPE_PALETTES.fire;
  const rnd = mulberry32(hashStr(seedStr));
  const arms = 5 + Math.floor(rnd() * 4);       // 5..8
  const ringCount = 2 + Math.floor(rnd() * 3);  // 2..4
  const rot = rnd() * 360;
  let g = '';

  for (let i = 0; i < ringCount; i++) {
    const r = 12 + i * (32 / ringCount);
    g += `<circle cx="50" cy="50" r="${r.toFixed(1)}" fill="none" stroke="${pal[i % pal.length]}" stroke-opacity="0.45" stroke-width="${(1 + rnd() * 1.4).toFixed(2)}"/>`;
  }

  for (let i = 0; i < arms; i++) {
    const a = (rot + i * (360 / arms)) * Math.PI / 180;
    const perp = a + Math.PI / 2;
    const x1 = 50 + Math.cos(a) * 13, y1 = 50 + Math.sin(a) * 13;
    const x2 = 50 + Math.cos(a) * (36 + rnd() * 8), y2 = 50 + Math.sin(a) * (36 + rnd() * 8);
    const w = 3.5 + rnd() * 3;
    const bx1 = x1 + Math.cos(perp) * w, by1 = y1 + Math.sin(perp) * w;
    const bx2 = x1 - Math.cos(perp) * w, by2 = y1 - Math.sin(perp) * w;
    g += `<polygon points="${bx1.toFixed(1)},${by1.toFixed(1)} ${bx2.toFixed(1)},${by2.toFixed(1)} ${x2.toFixed(1)},${y2.toFixed(1)}" fill="${pal[1]}" fill-opacity="0.8"/>`;
    g += `<circle cx="${x2.toFixed(1)}" cy="${y2.toFixed(1)}" r="${(1.8 + rnd() * 2).toFixed(1)}" fill="${pal[0]}"/>`;
  }

  const sides = 3 + Math.floor(rnd() * 4);
  const pts = [];
  for (let i = 0; i < sides; i++) {
    const a = (rot + i * (360 / sides)) * Math.PI / 180;
    pts.push(`${(50 + Math.cos(a) * 11).toFixed(1)},${(50 + Math.sin(a) * 11).toFixed(1)}`);
  }
  g += `<polygon points="${pts.join(' ')}" fill="${pal[2]}" stroke="#fff" stroke-opacity="0.55" stroke-width="1"/>`;
  g += `<circle cx="50" cy="50" r="3" fill="#fff" fill-opacity="0.85"/>`;

  return `<svg viewBox="0 0 100 100" class="sigil" xmlns="http://www.w3.org/2000/svg">${g}</svg>`;
}

const GRADE_WORD = { 10: 'GEM MINT', 9: 'MINT', 8: 'NM-MINT', 1: 'AUTHENTIC ODDITY' };

function money(v) { return '$' + v.toFixed(2); }
function pad3(n) { return String(n).padStart(3, '0'); }
const RARITY_LABEL = { common: 'Common', uncommon: 'Uncommon', rare: 'Rare', ultra: 'Ultra Rare' };

function cardHTML(c) {
  const t = TYPE_META[c.type];
  let val = c.value;
  if (c.foil) val *= 3;
  if (c.grade) val *= c.gradeMult;
  const foil = c.foil ? `<div class="foil-overlay"></div>` : '';
  return `
  <div class="card rarity-${c.rarity}">
    ${foil}
    <div class="card-top">
      <span class="card-name">${c.name}</span>
      <span class="type-badge type-${c.type}">${t.label}</span>
    </div>
    <div class="art-window aw-${c.type}">${c.art ? `<img class="art-img" src="art/${c.art}.svg" alt="${c.name}">` : makeSigil(c.name + c.type, c.type)}</div>
    <div class="card-meta">
      <span><span class="rarity-gem gem-${c.rarity}"></span>Emberfall</span>
      <span>${pad3(c.number)} / 050</span>
    </div>
    <div class="flavor">${c.flavor}</div>
    <div class="value-bar">
      <span class="rarity-label rl-${c.rarity}">${RARITY_LABEL[c.rarity]}</span>
      <span class="value">${money(val)}</span>
    </div>
  </div>`;
}

function slabHTML(c) {
  const word = GRADE_WORD[c.grade] || 'GRADED';
  const cert = 'TU-' + hashStr(c.name + c.grade).toString().slice(0, 8);
  return `
  <div class="slab">
    <div class="slab-label">
      <div class="slab-grade">PSA ${c.grade}</div>
      <div class="slab-grade-word">${word}<small>Sprytes · ${c.name}</small></div>
    </div>
    ${cardHTML(c)}
    <div class="slab-cert">Trading Up Grading · Cert #${cert}</div>
  </div>`;
}

// ---- Sample Set 1 (Emberfall) cards ----
const emberpup    = { name: 'Emberpup',    type: 'fire', rarity: 'common',   number: 1,  value: 0.40, art: 'S1-001', flavor: 'A pup with a permanently singed tail.' };
const cinderhound = { name: 'Cinderhound', type: 'fire', rarity: 'uncommon', number: 2,  value: 1.60, art: 'S1-002', flavor: 'Its bark smolders the morning fog.' };
const pyrewolf    = { name: 'Pyrewolf',    type: 'fire', rarity: 'rare',     number: 3,  value: 6.50, art: 'S1-003', flavor: 'A single howl can melt a glacier.' };
const ignarok     = { name: 'Ignarok',     type: 'fire', rarity: 'ultra',    number: 48, value: 22.00, art: 'S1-048', flavor: 'The Everflame stirs beneath Emberfall.' };
const magmalith   = { name: 'Magmalith',   type: 'rock', rarity: 'rare',     number: 6,  value: 5.00, art: 'S1-006', flavor: 'A mountain that decided to walk.' };

function render() {
  const grade10 = { gradeMult: 5 };
  document.getElementById('rarities').innerHTML =
    [emberpup, cinderhound, pyrewolf, ignarok].map(cardHTML).join('');

  document.getElementById('special').innerHTML =
    cardHTML({ ...pyrewolf, foil: true }) +
    slabHTML({ ...pyrewolf, grade: 10, gradeMult: 5 }) +
    cardHTML({ ...ignarok, foil: true });

  document.getElementById('evo').innerHTML =
    cardHTML(emberpup) + '<div class="evo-arrow">→</div>' +
    cardHTML(cinderhound) + '<div class="evo-arrow">→</div>' +
    cardHTML(pyrewolf);
}
render();
