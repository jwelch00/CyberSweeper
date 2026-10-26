/* CyberSweeper mockup board generator + renderer.
   Mockup-only code: produces a believable, rule-consistent board state for screenshots.
   It is NOT the game's generator (no no-50/50 guarantee here). */
(function () {
  const CS = {};

  // ---------- palette from ?palette= ----------
  CS.applyPalette = function () {
    const p = new URLSearchParams(location.search).get("palette");
    if (p) document.documentElement.setAttribute("data-palette", p);
    return p || "signal";
  };

  // ---------- glyph sprite ----------
  CS.GLYPHS = `
  <svg class="sprite" aria-hidden="true">
    <symbol id="g-mine" viewBox="0 0 24 24">
      <g stroke="currentColor" stroke-width="2.2" stroke-linecap="square">
        <line x1="12" y1="1.8" x2="12" y2="22.2"/><line x1="1.8" y1="12" x2="22.2" y2="12"/>
        <line x1="4.8" y1="4.8" x2="19.2" y2="19.2"/><line x1="19.2" y1="4.8" x2="4.8" y2="19.2"/>
      </g>
      <polygon fill="currentColor" points="9.3,5.5 14.7,5.5 18.5,9.3 18.5,14.7 14.7,18.5 9.3,18.5 5.5,14.7 5.5,9.3"/>
      <rect x="10.2" y="10.2" width="3.6" height="3.6" fill="var(--void)" transform="rotate(45 12 12)"/>
    </symbol>
    <symbol id="g-flag" viewBox="0 0 24 24">
      <path d="M6.5 2.5v19" stroke="currentColor" stroke-width="2.2" fill="none"/>
      <path d="M8 3.5h11l-3.2 4.6L19 12.7H8z" fill="currentColor"/>
      <path d="M3.5 21.5h7" stroke="currentColor" stroke-width="2.2"/>
    </symbol>
  </svg>`;
  CS.injectGlyphs = function () { document.body.insertAdjacentHTML("afterbegin", CS.GLYPHS); };
  CS.svg = (id) => `<svg><use href="#${id}"/></svg>`;

  // ---------- seeded helpers ----------
  function mulberry32(a) { return function () { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
  function hash2(x, y, s) { let h = (x * 374761393 + y * 668265263 + s * 2147483647) | 0; h = Math.imul(h ^ (h >>> 13), 1274126177); return ((h ^ (h >>> 16)) >>> 0) / 4294967296; }
  function vnoise(x, y, s) {
    const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi;
    const sm = (t) => t * t * (3 - 2 * t);
    const a = hash2(xi, yi, s), b = hash2(xi + 1, yi, s), c = hash2(xi, yi + 1, s), d = hash2(xi + 1, yi + 1, s);
    const u = sm(xf), v = sm(yf);
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
  }
  CS.hash2 = hash2;

  // ---------- board state ----------
  // opts: { W, H, seed, density, start:[x,y], blobs:[{x,y,r}], noise, flagRate, frontierFlagRate, hits, wrongFlags, gameOver }
  CS.makeBoard = function (o) {
    const W = o.W, H = o.H, N = W * H, rnd = mulberry32(o.seed);
    const idx = (x, y) => y * W + x;
    const inb = (x, y) => x >= 0 && y >= 0 && x < W && y < H;
    const nb = (i) => { const x = i % W, y = (i / W) | 0, out = []; for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { if (!dx && !dy) continue; if (inb(x + dx, y + dy)) out.push(idx(x + dx, y + dy)); } return out; };
    const mine = new Uint8Array(N), num = new Uint8Array(N), rev = new Uint8Array(N), flag = new Uint8Array(N), hit = new Uint8Array(N);
    const [sx, sy] = o.start;
    for (let i = 0; i < N; i++) {
      const x = i % W, y = (i / W) | 0;
      if (Math.abs(x - sx) <= 1 && Math.abs(y - sy) <= 1) continue;
      const dist = Math.hypot(x - sx, y - sy);
      const dens = o.density + (o.densityRamp || 0) * dist;
      if (rnd() < dens) mine[i] = 1;
    }
    for (let i = 0; i < N; i++) num[i] = nb(i).reduce((a, j) => a + mine[j], 0);
    // reveal by blob mask
    const inMask = (x, y) => {
      let d = Infinity;
      for (const b of o.blobs) d = Math.min(d, Math.hypot((x - b.x) / b.r, (y - b.y) / (b.ry || b.r)));
      return d + (vnoise(x * 0.16, y * 0.16, o.seed) - 0.5) * (o.noise ?? 0.6) < 1;
    };
    const q = [];
    for (let i = 0; i < N; i++) { const x = i % W, y = (i / W) | 0; if (!mine[i] && inMask(x, y)) { rev[i] = 1; q.push(i); } }
    rev[idx(sx, sy)] = 1; q.push(idx(sx, sy));
    while (q.length) { const i = q.pop(); if (num[i] === 0) for (const j of nb(i)) if (!rev[j] && !mine[j]) { rev[j] = 1; q.push(j); } }
    // fill tiny hidden safe pockets fully enclosed by revealed cells (players would have opened them)
    for (let i = 0; i < N; i++) if (!rev[i] && !mine[i] && nb(i).every((j) => rev[j] || mine[j]) && nb(i).some((j) => rev[j])) rev[i] = 1;
    // flags
    const touchesRev = (i) => nb(i).some((j) => rev[j]);
    for (let i = 0; i < N; i++) {
      if (!mine[i] || !touchesRev(i)) continue;
      const enclosed = nb(i).every((j) => rev[j] || mine[j]);
      if (rnd() < (enclosed ? o.flagRate : o.frontierFlagRate)) flag[i] = 1;
    }
    // hits: mines touching revealed area, nearest to requested points
    for (const [hx, hy] of (o.hits || [])) {
      let best = -1, bd = Infinity;
      for (let i = 0; i < N; i++) if (mine[i] && !hit[i] && touchesRev(i)) { const d = Math.hypot(i % W - hx, ((i / W) | 0) - hy); if (d < bd) { bd = d; best = i; } }
      if (best >= 0) { hit[best] = 1; flag[best] = 0; rev[best] = 1; }
    }
    const wrong = new Uint8Array(N);
    for (const [wx, wy] of (o.wrongFlags || [])) {
      let best = -1, bd = Infinity;
      for (let i = 0; i < N; i++) if (!mine[i] && !rev[i] && touchesRev(i)) { const d = Math.hypot(i % W - wx, ((i / W) | 0) - wy); if (d < bd) { bd = d; best = i; } }
      if (best >= 0) { flag[best] = 1; wrong[best] = 1; }
    }
    const st = { W, H, mine, num, rev, flag, hit, wrong, seed: o.seed, gameOver: !!o.gameOver, start: o.start };
    st.stats = CS.stats(st);
    return st;
  };

  CS.stats = function (st) {
    const counts = [0, 0, 0, 0, 0, 0, 0, 0, 0]; let tiles = 0, score = 0;
    for (let i = 0; i < st.W * st.H; i++) if (st.rev[i] && !st.mine[i]) { counts[st.num[i]]++; tiles++; score += st.num[i]; }
    return { counts, tiles, score };
  };

  // find a hidden safe cell on the frontier closest to (x,y)
  CS.frontierSafe = function (st, x, y) {
    let best = null, bd = Infinity;
    for (let i = 0; i < st.W * st.H; i++) {
      if (st.rev[i] || st.mine[i] || st.flag[i]) continue;
      const cx = i % st.W, cy = (i / st.W) | 0;
      let t = false; for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { const j = (cy + dy) * st.W + cx + dx; if (cx + dx >= 0 && cx + dx < st.W && st.rev[j] && !st.mine[j]) t = true; }
      if (!t) continue; const d = Math.hypot(cx - x, cy - y); if (d < bd) { bd = d; best = [cx, cy]; }
    }
    return best;
  };
  CS.revealedNumberNear = function (st, x, y, n) {
    let best = null, bd = Infinity;
    for (let i = 0; i < st.W * st.H; i++) { if (!st.rev[i] || st.mine[i] || (n ? st.num[i] !== n : !st.num[i])) continue; const d = Math.hypot(i % st.W - x, ((i / st.W) | 0) - y); if (d < bd) { bd = d; best = [i % st.W, (i / st.W) | 0]; } }
    return best;
  };

  // ---------- render a window of the board ----------
  // view: { x0, y0, cols, rows, px, py } px/py = pixel offset of cell (x0,y0) inside the container
  CS.render = function (el, st, view, extra = {}) {
    const cs = getComputedStyle(document.documentElement);
    const cell = parseFloat(getComputedStyle(el).getPropertyValue("--cell")) || 40;
    const gap = parseFloat(getComputedStyle(el).getPropertyValue("--gap")) || 3;
    const pitch = cell + gap;
    const board = document.createElement("div");
    board.className = "board";
    board.style.left = view.px + "px"; board.style.top = view.py + "px";
    board.style.gridTemplateColumns = `repeat(${view.cols}, var(--cell))`;
    const key = (x, y) => x + "," + y;
    const hover = extra.hover ? key(...extra.hover) : null;
    const fresh = new Set((extra.fresh || []).map((p) => key(...p)));
    const fresh2 = new Set((extra.fresh2 || []).map((p) => key(...p)));
    const chord = new Set((extra.chord || []).map((p) => key(...p)));
    let html = "";
    for (let y = view.y0; y < view.y0 + view.rows; y++) for (let x = view.x0; x < view.x0 + view.cols; x++) {
      const inb = x >= 0 && y >= 0 && x < st.W && y < st.H;
      const i = y * st.W + x;
      const byte = Math.floor(hash2(x, y, 99) * 256).toString(16).toUpperCase().padStart(2, "0");
      const wave = 0.5 + 0.5 * Math.sin((x * 0.42 + y * 0.31) + vnoise(x * 0.2, y * 0.2, 5) * 4);
      const co = (0.18 + 0.82 * Math.pow(wave, 2.2)).toFixed(2);
      if (!inb) { html += `<div class="c h" data-b="${byte}" style="--co:${co}"></div>`; continue; }
      const k = key(x, y);
      if (st.hit[i]) { html += `<div class="c m hit">${CS.svg("g-mine")}</div>`; continue; }
      if (st.gameOver && st.mine[i] && !st.flag[i] && CS.nearRevealed(st, x, y, 2)) { html += `<div class="c m shown">${CS.svg("g-mine")}</div>`; continue; }
      if (st.flag[i]) { html += `<div class="c h f${st.gameOver && st.wrong[i] ? " wrong" : ""}">${CS.svg("g-flag")}</div>`; continue; }
      if (st.rev[i]) {
        const n = st.num[i];
        html += `<div class="c r${fresh.has(k) ? " fresh" : fresh2.has(k) ? " fresh2" : ""}"${n ? ` data-n="${n}"` : ""}>${n || ""}</div>`;
        continue;
      }
      html += `<div class="c h${k === hover ? " hover" : ""}${chord.has(k) ? " chord" : ""}" data-b="${byte}" style="--co:${co}"></div>`;
    }
    board.innerHTML = html;
    el.appendChild(board);
    // popups
    for (const p of extra.pops || []) {
      const d = document.createElement("div");
      d.className = "pop"; d.textContent = p.text;
      d.style.setProperty("--pc", `var(--n${p.n})`);
      d.style.left = (view.px + (p.x - view.x0) * pitch + (p.dx || 0)) + "px";
      d.style.top = (view.py + (p.y - view.y0) * pitch + (p.dy || -26)) + "px";
      el.appendChild(d);
    }
    return { pitch, cellToPx: (x, y) => [view.px + (x - view.x0) * pitch, view.py + (y - view.y0) * pitch] };
  };

  // ---------- minimap ----------
  CS.minimap = function (canvas, st, view, scale = 2) {
    const css = getComputedStyle(document.documentElement);
    const col = (v) => css.getPropertyValue(v).trim();
    canvas.width = st.W * scale; canvas.height = st.H * scale;
    const g = canvas.getContext("2d");
    g.fillStyle = col("--void"); g.fillRect(0, 0, canvas.width, canvas.height);
    for (let i = 0; i < st.W * st.H; i++) {
      const x = i % st.W, y = (i / st.W) | 0;
      if (st.hit[i]) g.fillStyle = col("--danger");
      else if (st.flag[i]) g.fillStyle = col("--warn");
      else if (st.rev[i]) g.fillStyle = col("--accent") + (st.num[i] ? "AA" : "55");
      else continue;
      g.fillRect(x * scale, y * scale, scale, scale);
    }
    if (view) { g.strokeStyle = col("--ink"); g.lineWidth = 1.5; g.strokeRect(view.x0 * scale + .5, view.y0 * scale + .5, view.cols * scale, view.rows * scale); }
    const [sx, sy] = st.start; g.fillStyle = col("--accent2"); g.fillRect(sx * scale - 2, sy * scale - 2, 5, 5);
  };

  CS.nearRevealed = function (st, x, y, r) {
    for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) { const X = x + dx, Y = y + dy; if (X >= 0 && Y >= 0 && X < st.W && Y < st.H && st.rev[Y * st.W + X] && !st.mine[Y * st.W + X]) return true; }
    return false;
  };
  CS.fmt = (n) => n.toLocaleString("en-US");
  window.CS = CS;
})();
