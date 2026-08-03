/* Trading Up — pack & home screen mockups.
   Data mirrors Economy.swift / CardDatabase; art mirrors Theme.swift + cards.js. */

// ---------------------------------------------------------------- data

const PAL = {
  fire:     ['#ffd15c', '#ff7a1a', '#e01f1f', '#5c1004'],
  water:    ['#9fe8ff', '#39a7ff', '#1e5bd6', '#0a2a66'],
  grass:    ['#c6f68d', '#5fd35f', '#2f9e44', '#12481f'],
  electric: ['#fff3a3', '#ffd21a', '#f5a300', '#6b4a00'],
  shadow:   ['#d9b3ff', '#9b5cf6', '#5b2bb3', '#1f0d3d'],
};

const EMOJI = { fire: '🔥', water: '💧', grass: '🌿', electric: '⚡', shadow: '🌑' };

// Owned counts add up to 63 uniques — sets 1-3 unlocked (0/25/50), 4-5 locked (75/100).
const SETS = [
  { n: 1, name: 'Emberfall',    type: 'fire',     price: 10,  owned: 24, unlock: 0 },
  { n: 2, name: 'Tidecaller',   type: 'water',    price: 30,  owned: 21, unlock: 25 },
  { n: 3, name: 'Verdspire',    type: 'grass',    price: 75,  owned: 18, unlock: 50 },
  { n: 4, name: 'Voltcrest',    type: 'electric', price: 160, owned: 0,  unlock: 75 },
  { n: 5, name: 'Umbral Reach', type: 'shadow',   price: 400, owned: 0,  unlock: 100 },
];

const CASH = 248.50, NET = 1062.75, UNIQUES = 63, TOTAL = 250;

const money = v => '$' + v.toFixed(2);
const moneyShort = v => (v >= 1000 ? '$' + (v / 1000).toFixed(1) + 'k' : money(v));
const boxPrice = s => s.price * 11;
const unlocked = s => UNIQUES >= s.unlock;
const bySet = n => SETS[n - 1];
const vars = t => {
  const p = PAL[t];
  return `--e0:${p[0]};--e1:${p[1]};--e2:${p[2]};--e3:${p[3]};`;
};

// ------------------------------------------------- procedural sigil (cards.js port)

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
function makeSigil(seedStr, type) {
  const pal = PAL[type] || PAL.fire;
  const rnd = mulberry32(hashStr(seedStr));
  const arms = 5 + Math.floor(rnd() * 4);
  const ringCount = 2 + Math.floor(rnd() * 3);
  const rot = rnd() * 360;
  let g = '';
  for (let i = 0; i < ringCount; i++) {
    const r = 12 + i * (32 / ringCount);
    g += `<circle cx="50" cy="50" r="${r.toFixed(1)}" fill="none" stroke="${pal[i % pal.length]}" stroke-opacity=".55" stroke-width="${(1 + rnd() * 1.4).toFixed(2)}"/>`;
  }
  for (let i = 0; i < arms; i++) {
    const a = (rot + i * (360 / arms)) * Math.PI / 180;
    const perp = a + Math.PI / 2;
    const x1 = 50 + Math.cos(a) * 13, y1 = 50 + Math.sin(a) * 13;
    const x2 = 50 + Math.cos(a) * (36 + rnd() * 8), y2 = 50 + Math.sin(a) * (36 + rnd() * 8);
    const w = 3.5 + rnd() * 3;
    const bx1 = x1 + Math.cos(perp) * w, by1 = y1 + Math.sin(perp) * w;
    const bx2 = x1 - Math.cos(perp) * w, by2 = y1 - Math.sin(perp) * w;
    g += `<polygon points="${bx1.toFixed(1)},${by1.toFixed(1)} ${bx2.toFixed(1)},${by2.toFixed(1)} ${x2.toFixed(1)},${y2.toFixed(1)}" fill="${pal[0]}" fill-opacity=".85"/>`;
    g += `<circle cx="${x2.toFixed(1)}" cy="${y2.toFixed(1)}" r="${(1.8 + rnd() * 2).toFixed(1)}" fill="#fff" fill-opacity=".9"/>`;
  }
  const sides = 3 + Math.floor(rnd() * 4);
  const pts = [];
  for (let i = 0; i < sides; i++) {
    const a = (rot + i * (360 / sides)) * Math.PI / 180;
    pts.push(`${(50 + Math.cos(a) * 11).toFixed(1)},${(50 + Math.sin(a) * 11).toFixed(1)}`);
  }
  g += `<polygon points="${pts.join(' ')}" fill="${pal[0]}" fill-opacity=".9" stroke="#fff" stroke-opacity=".65" stroke-width="1"/>`;
  g += `<circle cx="50" cy="50" r="3" fill="#fff" fill-opacity=".95"/>`;
  return `<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">${g}</svg>`;
}

// ================================================================ P1 · foil wrapper

/**
 * The wrapper is one template at every size — a top band (brand), a centred
 * sigil, and a bottom band (set name + kind). Detail levels only decide how
 * much of the type survives; the art always stays optically centred.
 *
 * detail: 'full'  — hero pack: brand, big sigil, set name, "6 cards" burst
 *         'mid'   — ~110px: same, no burst
 *         'mini'  — ~60px shop thumbnail: sigil + set name
 *         'micro' — ~34px rail chip: sigil only
 */
function packWrapper(setNo, { w = 190, detail = 'full', isBox = false, cls = '' } = {}) {
  const s = bySet(setNo);
  const full = detail === 'full', mid = detail === 'mid', micro = detail === 'micro';
  const sig = makeSigil(s.name + s.type, s.type);
  return `
  <div class="pack wrapper sz-${detail} ${cls}" style="--w:${w}px;${vars(s.type)}" data-set="${setNo}">
    <div class="crimp crimp-top"></div>
    <div class="face">
      <div class="holo"></div>
      <div class="content">
        <div class="band-top">
          ${micro ? '' : `<div class="brandline">TRADING UP</div>`}
          ${full || mid ? `<div class="rule"></div>` : ''}
        </div>
        <div class="band-mid">
          <div class="emblem">${sig}</div>
        </div>
        <div class="band-bot">
          ${micro ? '' : `<div class="setname">${s.name}</div>`}
          ${full || mid ? `<div class="kind">${isBox ? 'BOOSTER BOX' : 'BOOSTER PACK'}</div>` : ''}
        </div>
      </div>
      ${full ? `<div class="burst"><i>6<small>CARDS</small></i></div>` : ''}
      <div class="sheen"></div>
    </div>
    <div class="crimp crimp-bottom"></div>
  </div>`;
}

// ================================================================ P2 · sealed bundle

function cardBack(setNo, cw) {
  const s = bySet(setNo);
  return `
  <div class="cardback" style="--cw:${cw}px;${vars(s.type)}">
    <div class="diamonds">
      <i style="width:${cw * 0.56}px;height:${cw * 0.56}px"></i>
      <i style="width:${cw * 0.44}px;height:${cw * 0.44}px"></i>
      <i style="width:${cw * 0.32}px;height:${cw * 0.32}px"></i>
    </div>
    <div class="glyph"><span>${EMOJI[s.type]}</span></div>
    <div class="foot">TRADING UP</div>
    <div class="inner-rule"></div>
  </div>`;
}

function bundle(setNo, { cw = 175, cls = '' } = {}) {
  const s = bySet(setNo);
  const layers = [];
  // Back-to-front: a visible edge stack, then the face card.
  for (let i = 5; i >= 0; i--) {
    const dx = i * (cw * 0.022), dy = i * (cw * -0.016), rot = (i - 2.5) * 1.5;
    layers.push(`<div class="layer" style="transform:translate(${dx}px,${dy}px) rotate(${rot}deg)">
      ${cardBack(setNo, cw)}
    </div>`);
  }
  // Below ~100pt the band's type turns to mush, so it becomes a plain paper wrap.
  const bandText = cw >= 100 ? `<b>${s.name}</b><small>6 CARDS · SET ${s.n}</small>` : '';
  return `
  <div class="bundle ${cls}" style="--cw:${cw}px;${vars(s.type)}" data-set="${setNo}">
    ${layers.join('')}
    <div class="band">${bandText}</div>
    <div class="seal">${EMOJI[s.type]}</div>
  </div>`;
}

// ================================================================ P3 · booster box

function box3d(setNo, { bw = 200 } = {}) {
  const s = bySet(setNo);
  return `
  <div class="box3d" style="--bw:${bw}px;${vars(s.type)}">
    <div class="bx-top"></div>
    <div class="bx-side"></div>
    <div class="bx-front">
      <div class="bx-brand">TRADING UP</div>
      <div class="bx-emblem">${makeSigil(s.name + s.type, s.type)}</div>
      <div class="bx-set">${s.name}</div>
      <div class="bx-kind">12 BOOSTER PACKS</div>
      <div class="bx-guarantee">≥3 ULTRA · ≥2 FOIL GUARANTEED</div>
    </div>
    <div class="bx-gloss"></div>
  </div>`;
}

// Slots only ever say "still sealed" or "already opened" — never which pack is
// carrying the box guarantee, since that would spoil the pull before the tear.
function tray(setNo, { used = 0 } = {}) {
  const s = bySet(setNo);
  let slots = '';
  for (let i = 0; i < 12; i++) {
    slots += `<div class="slot ${i < used ? 'gone' : ''}"></div>`;
  }
  return `<div><div class="tray" style="${vars(s.type)}">${slots}</div>
    <div class="tray-caption">${12 - used} of 12 packs left</div></div>`;
}

// ================================================================ helpers

function ring(value, total, color, size = 46) {
  const r = size / 2 - 4, c = 2 * Math.PI * r;
  const frac = Math.max(0, Math.min(1, value / total));
  return `<div class="ring" style="width:${size}px;height:${size}px">
    <svg viewBox="0 0 ${size} ${size}">
      <circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="rgba(255,255,255,.09)" stroke-width="4"/>
      <circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="${color}" stroke-width="4"
        stroke-linecap="round" stroke-dasharray="${c}" stroke-dashoffset="${c * (1 - frac)}"/>
    </svg>
    <div class="ring-num">${value}</div>
  </div>`;
}

const ICONS = {
  bag: '<svg viewBox="0 0 24 24"><path d="M6 7h12l1 13H5L6 7zm3 0a3 3 0 016 0"  fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg>',
  grid: '<svg viewBox="0 0 24 24"><path d="M4 4h5v5H4zM10 4h5v5h-5zM16 4h4v5h-4zM4 10h5v5H4zM10 10h5v5h-5zM16 10h4v5h-4zM4 16h5v4H4zM10 16h5v4h-5zM16 16h4v4h-4z"/></svg>',
  chart: '<svg viewBox="0 0 24 24"><path d="M4 14h4v6H4zM10 8h4v12h-4zM16 4h4v16h-4z"/></svg>',
};

function chrome(inner, { tab = 'Shop' } = {}) {
  return `
  <div class="frame"><div class="phone">
    <div class="island"></div>
    <div class="screen">
      <div class="statusbar"><span>9:41</span>
        <span class="icons"><i></i><i></i><i class="batt"></i></span></div>
      <div class="body">${inner}</div>
      <div class="tabbar">
        <div class="tab ${tab === 'Shop' ? 'on' : ''}">${ICONS.bag}<span>${tab === 'Shop' ? 'Shop' : 'Shop'}</span></div>
        <div class="tab">${ICONS.grid}<span>Collection</span></div>
        <div class="tab">${ICONS.chart}<span>Stats</span></div>
      </div>
      <div class="homebar"></div>
    </div>
  </div></div>`;
}

function device(id, title, tagClass, tagText, blurb, inner) {
  return `<figure class="device" id="${id}">
    ${inner}
    <figcaption>
      <span class="tag ${tagClass}">${tagText}</span>
      <h4>${title}</h4>
      <p>${blurb}</p>
    </figcaption>
  </figure>`;
}

// ================================================================ H0 · today

function screenToday() {
  const setCard = s => {
    const lock = !unlocked(s);
    return `<div class="t-setcard" style="${vars(s.type)}">
      <div class="t-banner">
        <div><small>SET ${s.n}</small><b>${s.name}</b></div>
        ${lock ? '<div style="font-size:26px">🔒</div>' : ''}
      </div>
      ${lock ? `<div class="t-setbody">
          <div style="display:flex;justify-content:space-between;font-size:13px;color:var(--subtle)">
            <span>🔒 Locked</span><span class="mono">${UNIQUES} / ${s.unlock}</span></div>
          <div style="font-size:13px;color:var(--subtle)">Collect <b style="color:#e7ecf5">${s.unlock - UNIQUES} more</b> unique cards (${s.unlock} total) to unlock ${s.name}.</div>
          <div class="t-bar"><i style="width:${UNIQUES / s.unlock * 100}%;background:var(--e1)"></i></div>
        </div>`
      : `<div class="t-setbody">
          <div style="display:flex;justify-content:space-between;font-size:12px;color:var(--subtle);font-weight:600">
            <span>${s.owned} / 50 collected</span></div>
          <div class="t-bar"><i style="width:${s.owned / 50 * 100}%;background:var(--e1)"></i></div>
          <div class="t-bigbtn"><div class="ico"></div><div><b>Buy Pack</b><small>6 cards · ${money(s.price)}</small></div></div>
          <div class="t-bigbtn alt"><div class="ico"></div><div><b>Buy Booster Box</b><small>12 packs · ${money(boxPrice(s))} · ≥3 ultra, ≥2 foil</small></div></div>
        </div>`}
    </div>`;
  };

  return chrome(`<div class="scroll" style="padding-top:8px">
    <div class="t-panel">
      <div class="t-cash-row">
        <div><div class="t-label">CASH</div><div class="t-cash">${money(CASH)}</div></div>
        <div style="text-align:right"><div class="t-label">NET WORTH</div><div class="t-net">$1,062.75</div></div>
      </div>
      <div style="display:flex;justify-content:space-between;margin-top:12px;font-size:12px;font-weight:600;color:var(--subtle)">
        <span>Collection</span><span class="mono" style="color:var(--text)">${UNIQUES} / ${TOTAL}</span></div>
      <div class="t-bar"><i style="width:${UNIQUES / TOTAL * 100}%"></i></div>
    </div>
    ${setCard(SETS[0])}
    ${setCard(SETS[1])}
  </div>`);
}

// ================================================================ shared wallet

function wallet() {
  return `<div class="wallet">
    <div class="wallet-row">
      <div class="wallet-cash"><div class="coin">$</div><b>${money(CASH)}</b></div>
      <div class="wallet-net"><small>NET WORTH</small><b>${moneyShort(NET)}</b></div>
    </div>
    <div class="wallet-prog">
      <span>BINDER</span>
      <div class="t-bar"><i style="width:${UNIQUES / TOTAL * 100}%"></i></div>
      <span class="mono" style="color:var(--text)">${UNIQUES}/${TOTAL}</span>
    </div>
  </div>`;
}

// ================================================================ H1 · shelf list

function screenShelfList() {
  const row = s => {
    if (!unlocked(s)) {
      return `<div class="h1-row locked" style="${vars(s.type)}">
        <div class="h1-thumb">${packWrapper(s.n, { w: 58, detail: 'mini' })}</div>
        <div class="h1-main">
          <div class="h1-title">
            <div><b>${s.name}</b><small>Set ${s.n} · locked</small></div>
            <div style="font-size:20px;opacity:.6">🔒</div>
          </div>
          <div class="h1-locked-cta">🔒 <span><b>${s.unlock - UNIQUES} more</b> unique cards to unlock</span></div>
        </div>
      </div>`;
    }
    return `<div class="h1-row" style="${vars(s.type)}">
      <div class="h1-thumb">${packWrapper(s.n, { w: 58, detail: 'mini' })}</div>
      <div class="h1-main">
        <div class="h1-title">
          <div><b>${s.name}</b><small>Set ${s.n} · ${s.owned} of 50 collected</small></div>
          ${ring(s.owned, 50, PAL[s.type][1], 42)}
        </div>
        <div class="h1-cta"><b>Rip a pack</b><span class="price">${money(s.price)}</span></div>
        <div class="h1-sub">
          <span>Booster box · <b>${money(boxPrice(s))}</b> · ≥3 ultra, ≥2 foil</span>
          <span class="chev">›</span>
        </div>
      </div>
    </div>`;
  };

  return chrome(`<div class="scroll">
    ${wallet()}
    <div class="eyebrow"><span>Packs</span><span>5 sets</span></div>
    ${SETS.map(row).join('')}
  </div>`);
}

// ================================================================ H2 · pack counter

function screenPackCounter(setNo = 1) {
  const s = bySet(setNo);
  const p = PAL[s.type];
  const bg = `background:
      radial-gradient(120% 55% at 50% 4%, ${p[1]}55, transparent 60%),
      radial-gradient(150% 70% at 50% 0%, ${p[2]}88, transparent 66%),
      linear-gradient(180deg, #141b28, #0b0e14 70%);`;
  const rail = SETS.map(x => `
    <div class="r-item ${x.n === setNo ? 'on' : ''} ${unlocked(x) ? '' : 'lock'}" data-rail="${x.n}">
      ${packWrapper(x.n, { w: 34, detail: 'micro' })}
      <span>${unlocked(x) ? x.name.split(' ')[0] : '🔒'}</span>
    </div>`).join('');

  return chrome(`
    <div class="h2-bg" style="${bg}"></div>
    <div style="position:relative;z-index:2;display:flex;flex-direction:column;height:100%;padding:0 16px">
      ${wallet()}
      <div class="h2-hero">
        ${packWrapper(setNo, { w: 158, detail: 'full', cls: 'tiltable clickable' })}
        <div class="h2-setname">${s.name}</div>
        <div class="h2-meta">Set ${s.n} · ${s.owned} of 50 collected</div>
        <div class="h2-progress">
          <div class="t-bar"><i style="width:${s.owned / 50 * 100}%;background:linear-gradient(90deg,${p[0]},${p[1]})"></i></div>
        </div>
        <div class="h2-actions">
          <div class="h2-primary" style="${vars(s.type)}"><b>Rip a pack</b><span>${money(s.price)}</span></div>
          <div class="h2-secondary">
            <div><b>Booster box · 12 packs</b><small>≥3 ultra, ≥2 foil guaranteed</small></div>
            <span style="font-weight:800">${money(boxPrice(s))}</span>
          </div>
        </div>
      </div>
      <div class="h2-rail">${rail}</div>
    </div>`);
}

// ================================================================ H3 · storefront

function screenStorefront() {
  const shelf = s => {
    if (!unlocked(s)) {
      return `<div class="h3-shelf" style="${vars(s.type)}">
        <div class="h3-empty"><div>🔒</div><div>Unlock at ${s.unlock} uniques — <b style="color:#e7ecf5">${s.unlock - UNIQUES} to go</b></div></div>
        <div class="h3-plank" style="margin-top:6px"></div>
        <div class="h3-placard"><div><b>${s.name}</b><small>Set ${s.n} · not in stock yet</small></div>
          <div style="font-size:18px;opacity:.5">🔒</div></div>
      </div>`;
    }
    return `<div class="h3-shelf" style="${vars(s.type)}">
      <div class="h3-stage">
        <div class="standing">${packWrapper(s.n, { w: 62, detail: 'mini' })}</div>
        <div class="standing">${packWrapper(s.n, { w: 76, detail: 'mid', cls: 'tiltable' })}</div>
        <div class="standing">${packWrapper(s.n, { w: 62, detail: 'mini' })}</div>
      </div>
      <div class="h3-plank"></div>
      <div class="h3-placard">
        <div><b>${s.name}</b><small>Set ${s.n} · ${s.owned}/50 · box ${money(boxPrice(s))}</small></div>
        <div class="h3-price">Rip · ${money(s.price)}</div>
      </div>
    </div>`;
  };

  return chrome(`<div class="scroll">
    ${wallet()}
    <div class="eyebrow"><span>The counter</span><span>${UNIQUES}/${TOTAL} binder</span></div>
    ${shelf(SETS[0])}
    ${shelf(SETS[1])}
    ${shelf(SETS[3])}
  </div>`);
}

// ================================================================ render

function el(html) {
  const t = document.createElement('template');
  t.innerHTML = html.trim();
  return t.content.firstElementChild;
}

function stageItem(label, content, hint) {
  return `<div class="stage-item">
    <div class="stage-label">${label}</div>
    ${content}
    ${hint ? `<div class="stage-hint">${hint}</div>` : ''}
  </div>`;
}

// ---- P1 stage: hero pack (clickable), a second set, and shop-size variants
document.getElementById('p1-stage').innerHTML = `
  ${stageItem('Hero · tap to tear', `
    <div class="pack-shell" id="p1-shell">
      <div class="flashburst"></div>
      <div class="spill">${bundle(1, { cw: 150, cls: 'fanned' })}</div>
      ${packWrapper(1, { w: 200, detail: 'full', cls: 'tiltable clickable' })}
    </div>`, 'Emberfall · $10')}
  ${stageItem('Set 5', packWrapper(5, { w: 150, detail: 'full', cls: 'tiltable' }), 'Umbral Reach · $400')}
  ${stageItem('In the shop', `<div style="display:flex;gap:18px;align-items:flex-end">
      ${packWrapper(2, { w: 110, detail: 'mid' })}
      ${packWrapper(3, { w: 58, detail: 'mini' })}
      ${packWrapper(4, { w: 34, detail: 'micro' })}
    </div>`, '110 / 58 / 34 pt')}`;

document.getElementById('p1-anatomy').innerHTML = `
    <div class="anatomy">
      <div class="lbl l l1"><b>Crimped seal</b>Serrated heat‑seal, top and bottom</div>
      <div class="lbl l l2"><b>Foil sheen</b>Slow diagonal glint, 3.4s loop</div>
      <div class="lbl l l3"><b>Bulge</b>Inner shadow = cards inside</div>
      <div class="lbl r r1"><b>Card count</b>Foil starburst, 6 cards</div>
      <div class="lbl r r2"><b>Centred art</b>The sigil is the hero at every size</div>
      <div class="lbl r r3"><b>Set stamp</b>Gold‑foil name over BOOSTER PACK</div>
      ${packWrapper(1, { w: 170, detail: 'full' })}
    </div>`;

document.getElementById('p1-swatches').innerHTML =
  [1, 2, 3, 4, 5].map(n => packWrapper(n, { w: 46, detail: 'micro' })).join('');

// ---- P2 stage
document.getElementById('p2-stage').innerHTML = `
  ${stageItem('Sealed · tap to fan', `<div id="p2-bundle">${bundle(1, { cw: 175, cls: 'tiltable clickable' })}</div>`, 'The band is the label')}
  ${stageItem('Fanned', bundle(3, { cw: 140, cls: 'fanned' }), 'Straight into the reveal')}
  ${stageItem('In the shop', `<div style="display:flex;gap:20px;align-items:flex-end">
      ${bundle(2, { cw: 84 })}${bundle(5, { cw: 56 })}</div>`, '84 / 56 pt')}`;

document.getElementById('p2-swatches').innerHTML =
  [1, 3, 5].map(n => cardBack(n, 40)).join('');

// ---- P3 stage
document.getElementById('p3-stage').innerHTML = `
  ${stageItem('Sealed box', box3d(1, { bw: 200 }), 'Emberfall · $110')}
  ${stageItem('Opened · pack tray', tray(1, { used: 4 }), 'Every sealed pack looks identical')}
  ${stageItem('Set 5 box', box3d(5, { bw: 150 }), 'Umbral Reach · $4,400')}`;

document.getElementById('p3-swatches').innerHTML =
  [2, 4].map(n => box3d(n, { bw: 62 })).join('');

// ---- thumbnail comparison strip
document.getElementById('thumb-strip').innerHTML = `
  <div class="thumb-cell"><span>TODAY</span>
    <div style="width:58px;height:76px;border-radius:12px;${vars('fire')}
      background:linear-gradient(140deg,var(--e1),var(--e3));display:grid;place-items:center;font-size:22px">🔥</div></div>
  <div class="thumb-cell"><span>P1 WRAPPER</span>${packWrapper(1, { w: 58, detail: 'mini' })}</div>
  <div class="thumb-cell"><span>P2 BUNDLE</span>${bundle(1, { cw: 58 })}</div>
  <div class="thumb-cell"><span>P3 BOX</span>${box3d(1, { bw: 62 })}</div>
  <div class="thumb-cell"><span>P1 · ALL FIVE SETS</span>
    <div style="display:flex;gap:10px">${SETS.map(s => packWrapper(s.n, { w: 44, detail: 'micro' })).join('')}</div></div>`;

// ---- home screens
document.getElementById('screens').innerHTML = [
  device('h0', 'H0 · Today', 'tag-c', 'Baseline',
    'What ships now: a cash panel plus five banner panels, each with two full-width gradient buttons. Honest and readable, but the pack is never pictured, every button competes, and cash scrolls off the top.',
    screenToday()),
  device('h1', 'H1 · Shelf List', 'tag-a', 'Recommended',
    'Same one-scroll structure, rebuilt as rows. The pack becomes the row’s icon, “Rip a pack · $10” is the only filled button, the box drops to a quiet secondary line, and the wallet pins to the top with a binder progress bar. All five sets fit on one screen.',
    screenShelfList()),
  device('h2', 'H2 · Pack Counter', 'tag-b', 'Boldest',
    'One set at a time, with the pack at hero size and the whole background themed to its element. Exactly one primary action on screen. The rail at the bottom swaps sets — tap the mini packs to try it.',
    screenPackCounter(1)),
  device('h3', 'H3 · Storefront', 'tag-c', 'Most charm',
    'The shop as a physical counter: packs stand on lit shelves, a placard names the set and prices the box, and locked sets are visibly empty shelf space. Highest charm, highest art cost, fewest sets per screen.',
    screenStorefront()),
].join('');

// ---- interactions
document.getElementById('tear-tap').innerHTML = `
  <div class="stage-item">
    <div class="pack-shell" id="tap-shell">
      <div class="flashburst"></div>
      <div class="spill">${bundle(2, { cw: 120, cls: 'fanned' })}</div>
      ${packWrapper(2, { w: 155, detail: 'full', cls: 'clickable' })}
    </div>
    <button class="reset-btn" data-reset="tap-shell">Reset</button>
  </div>`;

document.getElementById('tear-swipe').innerHTML = `
  <div class="stage-item">
    <div class="pack-shell" id="swipe-shell">
      <div class="flashburst"></div>
      <div class="spill">${bundle(4, { cw: 120, cls: 'fanned' })}</div>
      ${packWrapper(4, { w: 155, detail: 'full', cls: 'clickable' })}
    </div>
    <div class="tearmeter" id="swipe-meter"><i></i></div>
    <div class="stage-hint">Drag right across the pack →</div>
    <button class="reset-btn" data-reset="swipe-shell">Reset</button>
  </div>`;

// ================================================================ behaviour

function tear(shell) {
  if (shell.classList.contains('opened')) return;
  const pack = shell.querySelector('.pack');
  pack.classList.add('tearing');
  shell.classList.add('opened');
}

function resetShell(shell) {
  const pack = shell.querySelector('.pack');
  shell.classList.remove('opened');
  pack.classList.remove('tearing');
  const top = pack.querySelector('.crimp-top');
  top.style.transform = '';
  top.style.opacity = '';
  const meter = document.getElementById('swipe-meter');
  if (meter) { meter.querySelector('i').style.right = '100%'; meter.classList.remove('armed'); }
}

// tap-to-tear on the P1 hero + interaction A
['p1-shell', 'tap-shell'].forEach(id => {
  const shell = document.getElementById(id);
  shell.addEventListener('click', () => {
    if (shell.classList.contains('opened')) resetShell(shell); else tear(shell);
  });
});

// reset buttons
document.querySelectorAll('[data-reset]').forEach(btn => {
  btn.addEventListener('click', e => {
    e.stopPropagation();
    resetShell(document.getElementById(btn.dataset.reset));
  });
});

// swipe-to-rip (interaction B)
(function () {
  const shell = document.getElementById('swipe-shell');
  const pack = shell.querySelector('.pack');
  const top = pack.querySelector('.crimp-top');
  const meter = document.getElementById('swipe-meter');
  const fill = meter.querySelector('i');
  let dragging = false, startX = 0, prog = 0;

  const apply = p => {
    top.style.transform = `translate(${p * 26}px, ${-p * 20}px) rotate(${-p * 12}deg)`;
    top.style.opacity = String(1 - p * 0.35);
    fill.style.right = `${100 - p * 100}%`;
    meter.classList.toggle('armed', p > 0.6);
  };

  pack.addEventListener('pointerdown', e => {
    if (shell.classList.contains('opened')) { resetShell(shell); return; }
    dragging = true; startX = e.clientX;
    pack.setPointerCapture(e.pointerId);
    e.preventDefault();
  });
  pack.addEventListener('pointermove', e => {
    if (!dragging) return;
    prog = Math.max(0, Math.min(1, (e.clientX - startX) / (pack.offsetWidth * 0.9)));
    apply(prog);
  });
  const end = () => {
    if (!dragging) return;
    dragging = false;
    if (prog > 0.6) { tear(shell); fill.style.right = '0%'; }
    else { prog = 0; apply(0); }
  };
  pack.addEventListener('pointerup', end);
  pack.addEventListener('pointercancel', end);
})();

// P2 · tap the sealed bundle to fan it
(function () {
  const host = document.getElementById('p2-bundle');
  host.addEventListener('click', () => host.firstElementChild.classList.toggle('fanned'));
})();

// H2 · rail switches the hero set
document.addEventListener('click', e => {
  const item = e.target.closest('[data-rail]');
  if (!item) return;
  const n = Number(item.dataset.rail);
  if (!unlocked(bySet(n))) return;
  const fig = document.getElementById('h2');
  const caption = fig.querySelector('figcaption');
  fig.innerHTML = screenPackCounter(n);
  fig.appendChild(caption);
});
