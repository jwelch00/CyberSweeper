/* Screen builders for v2 mockups: jagged street-deck HUD over a corporate-clean board. */
(function () {
  const barcode = (n, seed) => { let s = ""; for (let i = 0; i < n; i++) s += `<i style="width:${1 + (CS.hash2(i, seed, 3) * 3 | 0)}px"></i>`; return s; };

  /* Jagged panel silhouette. Deterministic per seed, recomputed whenever the panel resizes.
     Features: uneven cut corners (top-left big, bottom-right big, others small), an optional
     rectangular notch bitten out of the top edge, optional sawtooth teeth near the top-right,
     a 45-degree jog that pulls the right edge in 6px partway down, and a 6px step in the bottom edge. */
  CS.jagPoints = function (w, h, seed) {
    const R = (k) => CS.hash2(seed, k, 11);
    const ctl = 14 + Math.round(R(1) * 12), cbr = 16 + Math.round(R(2) * 14), cbl = 6, jog = 6, step = 6;
    const jogY = Math.round(h * (0.38 + R(3) * 0.25));
    const nx = Math.round(w * (0.30 + R(4) * 0.25)), nw = 34 + Math.round(R(5) * 40), nd = 5;
    const stepX = Math.round(w * (0.28 + R(6) * 0.3));
    const pts = [[ctl, 0]];
    if (R(8) > 0.3 && nx + nw < w - 60) pts.push([nx, 0], [nx + nd, nd], [nx + nw - nd, nd], [nx + nw, 0]);
    if (R(7) > 0.35) { for (let x = w - 46; x < w - 10; x += 10) pts.push([x, 0], [x + 5, 5]); pts.push([w - 10, 0], [w - 6, 0], [w, 6]); }
    else pts.push([w - 6, 0], [w, 6]);
    pts.push([w, jogY], [w - jog, jogY + jog], [w - jog, h - cbr], [w - jog - cbr, h], [stepX + step, h], [stepX, h - step], [cbl, h - step], [0, h - step - cbl], [0, ctl]);
    return { pts, hot: [[[0, ctl + 18], [0, ctl], [ctl, 0], [ctl + 44, 0]], [[w - jog, h - cbr - 22], [w - jog, h - cbr], [w - jog - cbr, h], [w - jog - cbr - 34, h]]] };
  };
  CS.jag = function (grp, seed) {
    grp.classList.add("jagged");
    const panel = grp.querySelector(":scope > .panel");
    const NS = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(NS, "svg"); svg.setAttribute("class", "jag"); grp.appendChild(svg);
    const draw = () => {
      const w = panel.offsetWidth, h = panel.offsetHeight; if (!w || !h) return;
      const { pts, hot } = CS.jagPoints(w, h, seed);
      panel.style.clipPath = `polygon(${pts.map(([x, y]) => `${x}px ${y}px`).join(",")})`;
      const P = (a) => a.map(([x, y]) => `${x + .5},${y + .5}`).join(" ");
      svg.setAttribute("width", w + 12); svg.setAttribute("height", h + 12);
      const term = (x, y) => `<rect class="term" x="${x - 2}" y="${y - 2}" width="4" height="4"/>`;
      let ticks = ""; for (let i = 0; i < 7; i++) ticks += `<line class="tick" x1="${w - 70 + i * 6}.5" y1="${h - 4}" x2="${w - 70 + i * 6}.5" y2="${h - (i % 3 ? 8 : 12)}"/>`;
      svg.innerHTML = `<polygon class="ghost" points="${P(pts.map(([x, y]) => [x + 4, y + 4]))}"/><polygon class="hair" points="${P(pts)}"/>` +
        hot.map((h) => `<polyline class="hot" points="${P(h)}"/>` + term(...h[0]) + term(...h[h.length - 1])).join("") + (w > 200 ? ticks : "");
    };
    draw(); new ResizeObserver(draw).observe(panel);
  };
  CS.jagAll = function (root) { root.querySelectorAll(".grp.deck").forEach((g, i) => { if (!g.classList.contains("jagged")) CS.jag(g, (+g.dataset.seed || 0) + i * 7 + 3); }); };

  CS.setSignal = function (screen, p) {
    const mc = p < 10 ? "var(--danger)" : p < 30 ? "var(--warn)" : "var(--accent)";
    const sig = screen.querySelector(".sig"); sig.style.setProperty("--mc", mc);
    sig.querySelector(".read").innerHTML = Math.round(p) + "<small>%</small>";
    sig.querySelector(".sigbar").style.setProperty("--p", p + "%");
    const m = sig.querySelector(".meter"); m.querySelectorAll("i").forEach((i, k) => i.classList.toggle("on", k < Math.round(p / 2.5)));
    m.classList.toggle("low", p < 30 && p >= 10); m.classList.toggle("crit", p < 10);
    screen.querySelector(".g-sig .tagl").style.setProperty("--tc", mc);
  };

  CS.buildGame = function (screen, o = {}) {
    const links = o.links ?? 2, signal = o.signal ?? 72;
    screen.classList.add("screen", "fx-scanlines", "fx-vignette");
    const pips = [0, 1, 2].map((i) => `<i class="link${i >= links ? " lost" : ""}"></i>`).join("");
    const mc = signal < 10 ? "crit" : signal < 30 ? "low" : "";
    screen.innerHTML = `
      <div class="board-viewport"></div>

      <div class="grp deck g-tl" data-seed="11">
        <div class="panel">
          <div class="row"><span class="wordmark">CYBERSWEEPER</span></div>
          <div class="row"><span class="tagl">links</span><div class="links">${pips}</div><span class="lbl num" style="font-size:13px">${links}/3</span></div>
          <span class="micro" style="left:24px;bottom:12px">SN 7F3A-91C2  REV 2.1b</span>
        </div>
        <i class="slashes" style="right:-40px;top:22px"></i>
      </div>

      <div class="grp deck g-sig" data-seed="23">
        <div class="panel">
          <div class="top"><span class="tagl" style="--tc:${mc === "crit" ? "var(--danger)" : mc === "low" ? "var(--warn)" : "var(--accent)"}">signal</span><i class="slashes" style="position:relative;display:inline-block;--sw:140px;margin-left:14px;margin-right:auto"></i><span class="lbl" style="font-size:12px;letter-spacing:.12em">DRAIN 2.4/s</span></div>
          <div class="sig" style="${mc === "crit" ? "--mc:var(--danger)" : mc === "low" ? "--mc:var(--warn)" : ""}">
            <span class="read">${signal}<small>%</small></span>
            <div class="sigbar" style="--p:${signal}%"><i></i></div>
            <div class="meter ${mc}">${Array.from({ length: 40 }, (_, i) => `<i class="${i < Math.round(signal / 2.5) ? "on" : ""}"></i>`).join("")}</div>
          </div>
          <span class="micro" style="right:26px;bottom:12px" data-tick="10728" data-pre="PKT ">PKT 0029E8</span>
          <span class="micro" style="left:20px;bottom:12px">CH 07  PROXY 7/7  0 = LINK LOSS</span>
        </div>
      </div>

      <div class="grp deck g-score" data-seed="5">
        <div class="panel">
          <span class="tagl" style="--tc:var(--accent2)">score</span>
          <div class="big num" data-score>0</div>
          <div class="rival"><div class="lbl" data-rival></div><div class="bar"><i data-rivalbar></i></div></div>
          <div class="barcode" style="left:30px;bottom:12px">${barcode(30, 7)}</div>
        </div>
        <i class="slashes" style="left:-42px;bottom:30px;--sc:var(--accent)"></i>
      </div>

      <div class="grp deck g-bl" data-seed="31">
        <div class="panel">
          <span class="lbl">position</span><span class="lbl">depth</span>
          <span class="v" data-pos></span><span class="v" data-depth></span>
          <span class="lbl" style="margin-top:8px">mine density</span><span class="lbl" style="margin-top:8px">time</span>
          <span class="v">18.4%</span><span class="v">06:12</span>
          <span class="micro" style="left:22px;bottom:11px">NAV // DEAD RECKONING</span>
        </div>
      </div>

      <div class="grp deck g-mm" data-seed="17">
        <div class="panel">
          <div class="corp"><span><span class="jp">鉄影</span> LATTICE MAP</span><span class="jp">監視中</span></div>
          <div class="frame"><canvas></canvas></div>
        </div>
        <i class="slashes" style="left:-44px;top:40px"></i>
      </div>

      <div class="grp deck g-hints" data-seed="41">
        <div class="panel"><span><span class="kbd">LMB</span> reveal</span><span><span class="kbd">RMB</span> flag</span><span><span class="kbd">LMB</span> on a number to chord</span><span><span class="kbd">WASD</span> pan</span><span><span class="kbd">wheel</span> zoom</span></div>
      </div>
      <svg class="cable" style="left:-22px;top:160px" width="60" height="740" viewBox="0 0 60 740">
        <path d="M48 0 V60 L30 78 V660 L48 678 V740"/><path d="M52 0 V58 L34 76 V658 L52 676 V740"/><path d="M56 0 V56 L38 74 V656 L56 674 V740"/>
        <rect x="46" y="-2" width="12" height="3"/><rect x="46" y="738" width="12" height="3"/>
      </svg>
      <svg class="cursor" viewBox="0 0 30 30" fill="none" stroke="currentColor" stroke-width="2"><path d="M2 9V2h7M21 2h7v7M28 21v7h-7M9 28H2v-7"/><path d="M15 11v8M11 15h8" stroke-width="1.5"/></svg>
      <div class="strainfx"></div>`;

    const st = CS.makeBoard({
      W: 150, H: 100, seed: 731, density: 0.17, start: [40, 62],
      blobs: [{ x: 40, y: 62, r: 12 }, { x: 56, y: 55, r: 13 }, { x: 72, y: 49, r: 12 }, { x: 86, y: 43, r: 11 }, { x: 95, y: 50, r: 8 }],
      noise: 0.75, flagRate: 0.92, frontierFlagRate: 0.45, hits: o.hit === false ? [] : [[97, 44]]
    });
    if (o.carve) { // demo only: clear mines in a hidden rectangle so a big cascade is available
      const [ax, ay, bx, by] = o.carve;
      const cx = (ax + bx) / 2, cy = (ay + by) / 2, rx = (bx - ax) / 2, ry = (by - ay) / 2;
      for (let y = ay; y <= by; y++) for (let x = ax; x <= bx; x++) { const i = y * st.W + x; const d = Math.hypot((x - cx) / rx, (y - cy) / ry) + (CS.hash2(x, y, 5) - .5) * .5; if (!st.rev[i] && d < 1) { st.mine[i] = 0; st.flag[i] = 0; } }
      for (let i = 0; i < st.W * st.H; i++) { const x = i % st.W, y = (i / st.W) | 0; let n = 0; for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { if (!dx && !dy) continue; const X = x + dx, Y = y + dy; if (X >= 0 && Y >= 0 && X < st.W && Y < st.H) n += st.mine[Y * st.W + X]; } st.num[i] = n; }
      st.stats = CS.stats(st);
    }
    const view = { x0: 79, y0: 30, cols: 47, rows: 27, px: -18, py: -10 };
    const vp = screen.querySelector(".board-viewport");
    const target = CS.frontierSafe(st, 101, 41);
    const r = CS.render(vp, st, view, { hover: target, lattice: true });
    const boardEl = vp.querySelector(".board");
    if (target) { const [px, py] = r.cellToPx(...target); const c = screen.querySelector(".cursor"); c.style.left = (px + 22) + "px"; c.style.top = (py + 24) + "px"; }
    const s = st.stats.score;
    screen.querySelector("[data-score]").textContent = CS.fmt(s);
    const rivals = [["script.kitty", 1890], ["mx_halcyon", 3590], ["NULL//SAINT", 7000]];
    const next = rivals.find((x) => x[1] > s) || rivals[2];
    screen.querySelector("[data-rival]").innerHTML = `next rival <b>${next[0]}</b> <span class="num">${CS.fmt(next[1])}</span>`;
    screen.querySelector("[data-rivalbar]").style.width = Math.min(100, s / next[1] * 100) + "%";
    const cx = view.x0 + view.cols / 2 - st.start[0], cy = view.y0 + view.rows / 2 - st.start[1];
    screen.querySelector("[data-pos]").textContent = `x ${Math.round(cx)}  y ${-Math.round(cy)}`;
    screen.querySelector("[data-depth]").textContent = Math.round(Math.hypot(cx, cy));
    { const cv = screen.querySelector(".g-mm canvas"); CS.minimap(cv, st, view, 2); const img = new Image(); img.src = cv.toDataURL(); img.style.cssText = "display:block;width:260px;image-rendering:pixelated"; cv.replaceWith(img); }
    CS.jagAll(screen);
    if (o.strain) FX.strain(screen, o.strain);

    let best = null, bestN = 0; const seen = new Set();
    for (let y = view.y0 + 4; y < view.y0 + view.rows - 5; y++) for (let x = view.x0 + 8; x < view.x0 + view.cols - 8; x++) {
      const i = y * st.W + x; if (st.rev[i] || st.mine[i] || st.num[i] || seen.has(i)) continue;
      const q = [i], comp = new Set([i]);
      while (q.length) { const j = q.pop(), jx = j % st.W, jy = (j / st.W) | 0; for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { const k = (jy + dy) * st.W + jx + dx; if (!comp.has(k) && !st.rev[k] && !st.mine[k] && st.num[k] === 0) { comp.add(k); q.push(k); } } }
      comp.forEach((k) => seen.add(k));
      if (comp.size > bestN) { bestN = comp.size; best = [x, y]; }
    }
    let mine = null, md = 1e9;
    for (let y = view.y0 + 3; y < view.y0 + view.rows - 4; y++) for (let x = view.x0 + 6; x < view.x0 + view.cols - 6; x++) {
      const i = y * st.W + x; if (!st.mine[i] || st.rev[i] || st.flag[i]) continue;
      let t = false; for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) if (st.rev[(y + dy) * st.W + x + dx] && !st.mine[(y + dy) * st.W + x + dx]) t = true;
      const d = Math.hypot(x - 100, y - 47); if (t && d < md) { md = d; mine = [x, y]; }
    }
    return { st, view, boardEl, vp, screen, cascadeAt: best, cascadeSize: bestN, mineAt: mine, pips: screen.querySelectorAll(".link") };
  };

  CS.buildTitle = function (screen) {
    screen.classList.add("screen", "fx-scanlines", "fx-vignette");
    screen.style.setProperty("--cell", "46px");
    screen.innerHTML = `
      <div class="board-viewport"></div>
      <div style="position:absolute;inset:0;z-index:6;background:linear-gradient(90deg, var(--void) 0%, color-mix(in srgb, var(--void) 92%, transparent) 34%, color-mix(in srgb, var(--void) 40%, transparent) 62%, transparent 85%)"></div>
      <div style="position:absolute;z-index:20;left:140px;top:170px">
        <div class="wordmark" style="font-size:148px;line-height:.9">CYBERSWEEPER</div>
        <p style="margin-top:30px;font-size:28px;font-weight:500;white-space:nowrap">Infinite Minesweeper. Three links. <span style="color:var(--ink-dim)">Never a coin flip.</span></p>
        <nav style="margin-top:74px;display:grid;gap:6px;width:440px;font-size:26px;font-weight:600">
          <div style="display:flex;justify-content:space-between;align-items:center;height:60px;padding:0 22px 0 26px;color:var(--void);background:var(--accent);clip-path:polygon(18px 0,calc(100% - 30px) 0,calc(100% - 25px) 5px,calc(100% - 10px) 5px,100% 15px,100% calc(100% - 6px),calc(100% - 6px) 100%,0 100%,0 18px)">Jack in <span class="kbd" style="font-size:13px">Enter</span></div>
          <div style="height:60px;padding:0 26px;display:flex;align-items:center;color:var(--ink-dim)">Palettes</div>
          <div style="height:60px;padding:0 26px;display:flex;align-items:center;color:var(--ink-dim)">Rivals</div>
          <div style="height:60px;padding:0 26px;display:flex;align-items:center;color:var(--ink-dim)">Settings</div>
        </nav>
      </div>
      <span class="micro" style="left:140px;bottom:60px;font-size:11px">CS-DECK 0.1.0  STREET BUILD  NOT FOR CORPORATE USE</span>
      <i class="slashes" style="left:140px;top:140px;--sw:120px"></i>
      <div class="strainfx"></div>`;
    const st = CS.makeBoard({ W: 60, H: 30, seed: 4242, density: 0.16, start: [44, 12], blobs: [{ x: 44, y: 12, r: 6.5 }, { x: 50, y: 17, r: 5 }], noise: 0.9, flagRate: 0.9, frontierFlagRate: 0.3 });
    CS.render(screen.querySelector(".board-viewport"), st, { x0: 8, y0: 0, cols: 42, rows: 24, px: -14, py: -22 }, { lattice: true });
  };

  CS.buildOver = function (screen) {
    screen.classList.add("screen", "fx-scanlines", "fx-vignette");
    const counts = [617, 395, 173, 60, 18, 5, 1, 0], subs = counts.map((c, i) => c * (i + 1)), max = Math.max(...subs);
    screen.innerHTML = `
      <div style="position:absolute;inset:0;background:radial-gradient(ellipse at 30% 40%, color-mix(in srgb, var(--danger) 12%, var(--void)), var(--void) 70%)"></div>
      <div class="grp deck" style="left:120px;top:110px" data-seed="3">
        <div class="panel" style="width:1000px;padding:56px 64px 60px">
          <span class="tagl" style="--tc:var(--danger);font-size:14px">link severed</span>
          <p style="margin-top:14px;font-size:20px;color:var(--ink-dim)">All three links lost at depth 212, eleven minutes in.</p>
          <div style="margin-top:26px;display:flex;align-items:baseline;gap:28px"><div class="num" style="font-weight:800;font-size:132px;line-height:1">2,293</div><div style="font-size:20px;font-weight:600;color:var(--accent2)">New best<span style="display:block;font-weight:400;color:var(--ink-dim);font-size:16px">up from 1,734</span></div></div>
          <div style="margin-top:40px;display:grid;grid-template-columns:repeat(8,1fr);gap:10px;align-items:end;height:200px">
            ${counts.map((c, i) => `<div style="display:grid;justify-items:center;gap:8px;--nc:var(--n${i + 1})"><span class="num" style="font-weight:800;font-size:28px;color:var(--nc)">${i + 1}</span><div style="width:60%;height:${Math.max(2, subs[i] / max * 110)}px;background:color-mix(in srgb, var(--nc) 75%, transparent)"></div><span class="num" style="font-size:15px">${CS.fmt(subs[i])}</span></div>`).join("")}
          </div>
          <span class="micro" style="left:64px;bottom:22px">SESSION LOG 7F3A-91C2  EXPORTED TO /dev/null</span>
        </div>
      </div>
      <div class="grp deck" style="right:120px;top:110px" data-seed="9">
        <div class="panel" style="width:600px;padding:40px">
          <span class="tagl">rivals</span>
          <div style="margin-top:20px;display:grid;gap:4px;font-size:20px">
            ${[["NULL//SAINT", "7,000"], ["mx_halcyon", "3,590"], ["You", "2,293"], ["script.kitty", "1,890"]].map(([n, s], i) => `<div style="display:flex;justify-content:space-between;height:56px;align-items:center;padding:0 18px;background:${i === 2 ? "color-mix(in srgb, var(--accent) 16%, var(--tile))" : "color-mix(in srgb, var(--tile) 70%, transparent)"};${i === 2 ? "box-shadow:inset 3px 0 0 var(--accent);color:var(--accent)" : ""}"><b style="font-weight:600">${n}</b><span class="num">${s}</span></div>`).join("")}
          </div>
          <p style="margin-top:22px;font-size:16px;color:var(--ink-dim);font-style:italic">"script.kitty has left the chat. She'll be back. She always comes back."</p>
        </div>
      </div>
      <div class="strainfx"></div>`;
    CS.jagAll(screen);
  };
})();
