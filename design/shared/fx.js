/* CyberSweeper motion prototypes. Mockup code: shows WHAT moves and WHEN.
   Every timing lives in FX.T and is mirrored in design/MOTION.md.
   Rule of thumb: the BOARD (corp software) only ever moves cleanly and precisely.
   All grime, glitch and jitter happens to the HUD (the player's deck) and screen edges. */
(function () {
  const FX = {};
  const T = FX.T = {
    frame: 16,
    boot: { line: 42, holdEnd: 160, msPerPct: 9, denied: 260, loaderHold: 180, offChance: 1 / 10000, odds: { clean: .40, one: .40, double: .05 } },
    card: { flash: 33, slam: 90, hold: 300, slice: 60, total: 420, fullHold: 900 },
    cascade: { ring: 22, ghostLife: 360, echoes: [0, 40, 80], drift: 11, minCells: 12 },
    hit: { slam: 120, shake: 250, shakePx: 8, flash: 60, march: 1200, tear: 33 },
    shatter: { life: 320, dist: 22 },
    strain: { corruptEvery: [3000, 800], corruptFor: [90, 140], tearEvery: 1500 },
    mosh: { breakOut: 180, total: 380, bands: 7 },
  };
  // ?slow=N plays every effect N times slower (used to record the slow-motion reference videos)
  const SLOW = +(new URLSearchParams(location.search).get("slow") || 1);
  if (SLOW > 1) {
    const timeKeys = ["line", "holdEnd", "loaderHold", "total", "flash", "slam", "hold", "slice", "fullHold", "ring", "ghostLife", "echoes", "shake", "march", "tear", "life", "corruptFor", "corruptEvery", "tearEvery", "breakOut"];
    const scale = (o) => { for (const k in o) { const v = o[k]; if (typeof v === "object" && !Array.isArray(v)) scale(v); else if (timeKeys.includes(k)) o[k] = Array.isArray(v) ? v.map((x) => x * SLOW) : v * SLOW; } };
    scale(T);
  }
  const reduced = () => document.documentElement.classList.contains("reduce-motion") || matchMedia("(prefers-reduced-motion: reduce)").matches;
  const rnd = (a, b) => a + Math.random() * (b - a);
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  const css = (v, el = document.documentElement) => getComputedStyle(el).getPropertyValue(v).trim();

  /* ---------------- 1. JACK-IN BOOT ---------------- */
  FX.BOOT_LINES = [
    ["00.000", "cs-deck // street build 0.1.0", "hi"],
    ["00.038", "cold boot ................................ ", "ok:ok"],
    ["00.081", "mounting cipher toolkit .................. ", "ok:ok"],
    ["00.119", "proxy chain: 7 hops ...................... ", "ok:ok"],
    ["00.164", "spoofing corp handshake .................. ", "ok:ok"],
    ["00.203", "target: TETSUKAGE DATAWORKS // SECURE LATTICE  ", "jp:鉄影"],
    ["00.247", "lattice size ............................. ", "warn:unbounded"],
    ["00.288", "ice signatures ........................... ", "warn:black, many"],
    ["00.330", "scanning for 50/50 traps ................. ", "ok:none found"],
    ["00.371", "links .................................... ", "ok:3/3"],
    ["00.409", "signal ................................... ", "ok:100%"],
    ["00.452", "jacking in  ", "jp:接続"],
  ];
  FX.boot = async function (screen) {
    const b = document.createElement("div"); b.className = "boot";
    b.innerHTML = `<div class="log"></div><div class="skip">any key to skip</div><div class="bar"><i></i></div>`;
    screen.appendChild(b);
    const log = b.querySelector(".log"), bar = b.querySelector(".bar i");
    for (let i = 0; i < FX.BOOT_LINES.length; i++) {
      const [ts, txt, tail] = FX.BOOT_LINES[i];
      const [kind, val] = tail.includes(":") ? tail.split(":") : [tail, ""];
      const right = kind === "ok" ? `<span class="ok">${val}</span>` : kind === "warn" ? `<span class="warn">${val}</span>` : kind === "jp" ? `<span class="hi jp">${val}</span>` : "";
      log.insertAdjacentHTML("beforeend", `<div class="ln"><span class="ts">[${ts}]</span><span class="${kind === "hi" ? "hi" : ""}">${txt}</span>${right}</div>`);
      log.querySelectorAll(".cur").forEach((c) => c.remove());
      log.lastElementChild.insertAdjacentHTML("beforeend", `<span class="cur"></span>`);
      bar.style.width = ((i + 1) / FX.BOOT_LINES.length * 100) + "%";
      await wait(reduced() ? 0 : T.boot.line);
    }
    log.insertAdjacentHTML("beforeend", `<div class="ln" style="margin-top:14px"><span class="ts">[00.611]</span><span class="ok" style="font-weight:800">LINK ESTABLISHED</span></div>`);
    await wait(T.boot.holdEnd);
    await FX.bootLoader(b);
    // easter egg: 1 boot in 10,000 the card has a typo. Never explained, never acknowledged.
    const off = Math.random() < T.boot.offChance || /[?&]jackedoff/.test(location.search);
    await FX.card(screen, { text: off ? "JACKED OFF" : "JACKED IN", jp: "接続完了", sub: "TETSUKAGE // SECURE LATTICE", color: "--accent" });
    return b; // caller datamoshes it away
  };

  // The "I'm in" beat between the log and the card (hacker-movie trope, played straight):
  // a mini board solves itself in a diagonal sweep, a session key cracks character by character,
  // hex-dump windows pop up around it. Whether it hits ACCESS DENIED, where, and how hard is
  // rolled from the boot seed (see FX.breachPlan), so every launch plays a little differently.
  const mulberry = (a) => () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
  FX.breachPlan = function (seed, force) {
    const r = mulberry(seed), roll = r();
    const kind = force || (roll < T.boot.odds.clean ? "clean" : roll < T.boot.odds.clean + T.boot.odds.one ? "one" : roll < 1 - T.boot.odds.double ? "99" : "double");
    let stalls = [];
    if (kind === "one") stalls = [{ at: 25 + r() * 65, drop: 8 + r() * 14 }];
    if (kind === "99") stalls = [{ at: 99, drop: 10 + r() * 12 }];
    if (kind === "double") { const a = 20 + r() * 30; stalls = [{ at: a, drop: 6 + r() * 10 }, { at: a + 25 + r() * 25, drop: 8 + r() * 12 }]; }
    stalls = stalls.map((x) => ({ at: Math.round(x.at), drop: Math.round(x.drop), proxy: 2 + (r() * 8 | 0) }));
    const segs = []; let t = 0, p = 0;
    for (const x of stalls) {
      segs.push({ t0: t, t1: t += (x.at - p) * T.boot.msPerPct, p0: p, p1: x.at });
      segs.push({ t0: t, t1: t += T.boot.denied, p0: x.at, p1: x.at - x.drop, denied: x });
      p = x.at - x.drop;
    }
    segs.push({ t0: t, t1: t += (100 - p) * T.boot.msPerPct, p0: p, p1: 100 });
    const key = Array.from({ length: 4 }, () => (r() * 0x10000 | 0).toString(16).toUpperCase().padStart(4, "0")).join("-");
    return { seed, kind, stalls, segs, total: t, key };
  };
  FX.bootLoader = async function (boot) {
    const W = 9, H = 5, mines = new Set([11, 24, 30, 42]);
    const num = (i) => { const x = i % W, y = (i / W) | 0; let n = 0; for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { const X = x + dx, Y = y + dy; if ((dx || dy) && X >= 0 && Y >= 0 && X < W && Y < H && mines.has(Y * W + X)) n++; } return n; };
    const HEX = "0123456789ABCDEF", hx = () => HEX[Math.random() * 16 | 0], hex = () => hx() + hx();
    const q = new URLSearchParams(location.search);
    const seed = q.has("bootseed") ? +q.get("bootseed") : (Math.random() * 2 ** 31) | 0;
    const plan = FX.lastPlan = FX.breachPlan(seed, q.get("breach"));
    const KEY = plan.key;
    boot.querySelector(".log").animate([{ opacity: 1 }, { opacity: .25 }], { duration: 200, fill: "forwards" });
    const el = document.createElement("div"); el.className = "bootload";
    el.innerHTML = `<div class="cap hdr">BREACHING ICE  <span class="jp">鉄影</span>  SECURE LATTICE</div>
      <div class="lg">${Array.from({ length: W * H }, () => `<i class="lt">${hex()}</i>`).join("")}</div>
      <div class="key">${[...KEY].map((c) => `<b class="${c === "-" ? "dash" : ""}">${c === "-" ? "-" : hx()}</b>`).join("")}</div>
      <div class="row"><span class="cap st">CRACKING SESSION KEY</span><span class="pc">0%</span></div>
      <div class="denied">ACCESS DENIED</div>`;
    boot.appendChild(el);
    const wins = [[-560, -150], [330, -190], [-500, 120], [360, 110]].map(([x, y], k) => {
      const w = document.createElement("div"); w.className = "dumpwin"; w.style.left = `calc(50% + ${x}px)`; w.style.top = `calc(50% + ${y}px)`; w.style.visibility = "hidden";
      w.innerHTML = `<div class="tt">${["proc/ice_daemon", "net/handshake", "mem/0x" + KEY.slice(0, 4), "lattice/chunk_map"][k]}</div><div class="dump"></div>`; boot.appendChild(w); return w;
    });
    const tiles = [...el.querySelectorAll(".lt")], keyEls = [...el.querySelectorAll(".key b:not(.dash)")], pc = el.querySelector(".pc"), st = el.querySelector(".st"), den = el.querySelector(".denied");
    const keyChars = KEY.replace(/-/g, ""), maxD = (W - 1) + (H - 1), SL = SLOW;
    // progress at time ms: climbs linearly; during a denial it holds for 40% of the beat, then shows the drop
    const at = (ms) => { for (const g of plan.segs) if (ms < g.t1 * SL) { const f = (ms - g.t0 * SL) / ((g.t1 - g.t0) * SL); return { p: g.denied ? (f < .4 ? g.p0 : g.p1) : g.p0 + (g.p1 - g.p0) * f, seg: g }; } return { p: 100, seg: null }; };
    let inDenial = null; const start = performance.now(), total = plan.total * SL;
    if (reduced()) { pc.textContent = "100%"; } else await new Promise((done) => {
      const tick = () => {
        const ms = performance.now() - start, { p: P, seg } = at(ms), p = P / 100, t = Math.min(1, ms / total);
        tiles.forEach((tl, i) => {
          if (tl.dataset.done) return;
          const d = (i % W + ((i / W) | 0)) / maxD;
          if (p >= d * 0.9 + 0.08) {
            tl.dataset.done = 1;
            if (mines.has(i)) { tl.className = "lt fl"; tl.innerHTML = CS.svg("g-flag"); }
            else { const n = num(i); tl.className = "lt on"; tl.textContent = n || ""; if (n) tl.style.setProperty("--nc", `var(--n${n})`); }
          } else if (Math.random() < .5) tl.textContent = hex();
        });
        const locked = Math.floor(p * keyEls.length);
        keyEls.forEach((k, i) => { if (i < locked) { if (!k.classList.contains("ok")) { k.classList.add("ok"); k.textContent = keyChars[i]; } } else { k.classList.remove("ok"); k.textContent = hx(); } });
        wins.forEach((w, k) => {
          if (t > .06 + k * .1 && w.style.visibility === "hidden") { w.style.visibility = "visible"; w.animate([{ scale: "1 0.05", opacity: 0 }, { scale: "1 1", opacity: 1 }], { duration: 90, easing: "steps(4)" }); }
          if (w.style.visibility === "visible") { const d = w.querySelector(".dump"); d.insertAdjacentHTML("beforeend", `<div>${(Math.random() * 0xffff | 0).toString(16).toUpperCase().padStart(4, "0")}  ${Array.from({ length: 8 }, hex).join(" ")}</div>`); while (d.children.length > 7) d.firstChild.remove(); }
        });
        const den0 = seg && seg.denied;
        if (den0 && inDenial !== den0) {
          inDenial = den0; den.style.visibility = "visible"; st.textContent = "RETRYING VIA PROXY " + den0.proxy; st.style.color = css("--danger");
          den.animate([{ scale: 1.25, opacity: 0 }, { scale: 1, opacity: 1, offset: .25 }, { scale: 1, opacity: 1, offset: .8 }, { scale: 1, opacity: 0 }], { duration: T.boot.denied * SL, fill: "forwards" });
          el.querySelector(".lg").animate([{ filter: "hue-rotate(140deg) saturate(3)", translate: "6px 0" }, { filter: "none", translate: "0 0" }], { duration: 160 * SL });
        }
        if (!den0 && inDenial) { inDenial = null; st.textContent = "CRACKING SESSION KEY"; st.style.color = ""; den.style.visibility = "hidden"; }
        pc.textContent = Math.round(P) + "%";
        if (ms < total) requestAnimationFrame(tick); else done();
      };
      requestAnimationFrame(tick);
    });
    pc.textContent = "100%"; keyEls.forEach((k, i) => { k.classList.add("ok"); k.textContent = keyChars[i]; });
    el.querySelector(".lg").animate([{ filter: "brightness(2.2)" }, { filter: "brightness(1)" }], { duration: 160 });
    st.textContent = "KEY ACCEPTED"; st.style.color = css("--accent"); den.style.visibility = "hidden";
    await wait(T.boot.loaderHold);
  };

  /* ---------------- 2. SMASH-CUT TITLE CARDS ---------------- */
  FX.card = async function (screen, o) {
    const c = document.createElement("div"); c.className = "smash";
    c.style.setProperty("--cc", `var(${o.color || "--accent"})`);
    c.style.setProperty("--cd", `var(${o.outline || "--ink"})`);
    let speed = ""; for (let i = 0; i < 14; i++) speed += `<i class="speed" style="top:${rnd(4, 96)}%;left:${rnd(-20, 80)}%;width:${rnd(80, 420)}px;opacity:${rnd(.3, .9)}"></i>`;
    c.innerHTML = `<div class="flash"></div><div class="band">${speed}</div><div class="txt ghost">${o.text}</div><div class="txt">${o.text}</div>` +
      (o.sub || o.jp ? `<div class="sub">${o.jp ? `<span class="jp">${o.jp}</span>` : ""}<span>${o.sub || ""}</span></div>` : "");
    screen.appendChild(c);
    const flash = c.querySelector(".flash"), band = c.querySelector(".band"), txts = c.querySelectorAll(".txt"), sub = c.querySelector(".sub");
    [band, ...txts, sub].forEach((e) => e && (e.style.visibility = "hidden"));
    if (reduced()) flash.remove(); else await wait(T.card.flash);
    flash.remove();
    [band, ...txts, sub].forEach((e) => e && (e.style.visibility = "visible"));
    if (!reduced()) {
      band.animate([{ transform: "translateY(-50%) rotate(-6deg) scaleX(1.18) scaleY(.6)" }, { transform: "translateY(-50%) rotate(-6deg) scaleX(1) scaleY(1)" }], { duration: T.card.slam, easing: "cubic-bezier(.2,1.4,.4,1)" });
      txts.forEach((t, i) => t.animate([{ translate: `${120 + i * 40}px 0`, opacity: 0 }, { translate: "0 0", opacity: 1 }], { duration: T.card.slam, easing: "cubic-bezier(.1,.9,.3,1)" }));
      c.querySelectorAll(".speed").forEach((s) => s.animate([{ translate: "300px 0" }, { translate: "-300px 0" }], { duration: T.card.hold + T.card.slam, easing: "linear" }));
    }
    await wait(T.card.slam + (o.full ? T.card.fullHold : T.card.hold));
    if (!reduced()) { c.classList.add("slice"); band.style.translate = "18px 0"; txts.forEach((t) => (t.style.translate = "-26px 0")); await wait(T.card.slice); }
    if (!o.keep) c.remove();
    return c;
  };

  /* ---------------- 3. SANDEVISTAN CASCADE ---------------- */
  FX.cascade = async function (boardEl, st, x0, y0) {
    const W = st.W, idx = (x, y) => y * W + x;
    const ring = new Map(); const q = [[x0, y0, 0]]; ring.set(idx(x0, y0), 0);
    while (q.length) {
      const [x, y, d] = q.shift();
      if (st.num[idx(x, y)] !== 0) continue;
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        const X = x + dx, Y = y + dy; if (X < 0 || Y < 0 || X >= W || Y >= st.H) continue;
        const j = idx(X, Y); if (ring.has(j) || st.rev[j] || st.mine[j] || st.flag[j]) continue;
        ring.set(j, d + 1); q.push([X, Y, d + 1]);
      }
    }
    // ripple rings by straight-line distance so the wave is round, not square
    const rings = []; for (const [j] of ring) { const d = Math.round(Math.hypot(j % W - x0, ((j / W) | 0) - y0)); (rings[d] ||= []).push(j); }
    const cyc = ["--accent2", "--accent", "--warn"].map((v) => css(v));
    const host = boardEl.parentElement, pitch = boardEl._pitch, v = boardEl._view;
    const cellSize = pitch - parseFloat(getComputedStyle(boardEl).gap || 3);
    const big = ring.size >= T.cascade.minCells && !reduced();
    let total = 0;
    for (let d = 0; d < rings.length; d++) {
      for (const j of rings[d] || []) {
        const x = j % W, y = (j / W) | 0; st.rev[j] = 1; total += st.num[j];
        const el = CS.cellEl(boardEl, x, y); if (!el) continue;
        el.className = "c r"; el.removeAttribute("style"); el.removeAttribute("data-b");
        if (st.num[j]) { el.dataset.n = st.num[j]; el.textContent = st.num[j]; }
        el.animate([{ background: `color-mix(in srgb, ${css("--floor")} 55%, ${cyc[1]})` }, { background: css("--floor") }], { duration: 260 });
        if (!big) continue;
        const px = v.px + (x - v.x0) * pitch, py = v.py + (y - v.y0) * pitch;
        const len = Math.hypot(x - x0, y - y0) || 1, ux = (x - x0) / len, uy = (y - y0) / len;
        T.cascade.echoes.forEach((delay, k) => {
          const g = document.createElement("div"); g.className = "ghostcell";
          g.style.cssText = `left:${px}px;top:${py}px;width:${cellSize}px;height:${cellSize}px;--gc:${cyc[k % cyc.length]}`;
          host.appendChild(g);
          g.animate([{ opacity: .95 - k * .2, translate: "0 0", scale: 1 },
                     { opacity: 0, translate: `${ux * T.cascade.drift * (k + 1)}px ${uy * T.cascade.drift * (k + 1)}px`, scale: 1.12 }],
                    { duration: T.cascade.ghostLife, delay, easing: "cubic-bezier(.2,.7,.3,1)", fill: "both" }).onfinish = () => g.remove();
        });
      }
      await wait(reduced() ? 0 : T.cascade.ring);
    }
    return { cells: ring.size, score: total, rings: rings.length };
  };

  /* ---------------- 6. MINE HIT (hazard) ---------------- */
  FX.mineHit = async function (screen, boardEl, st, x, y, hudPip) {
    const el = CS.cellEl(boardEl, x, y); const v = boardEl._view, pitch = boardEl._pitch;
    st.hit[y * st.W + x] = 1; st.rev[y * st.W + x] = 1;
    el.className = "c m hit march"; el.removeAttribute("data-b"); el.removeAttribute("style"); el.innerHTML = CS.svg("g-mine");
    if (!reduced()) {
      el.animate([{ scale: 1.35, filter: "brightness(3)" }, { scale: 1, filter: "brightness(1)" }], { duration: T.hit.slam, easing: "cubic-bezier(.2,1.5,.4,1)" });
      const fl = document.createElement("div"); fl.style.cssText = `position:absolute;inset:0;z-index:60;background:${css("--danger")};opacity:.22;pointer-events:none`;
      screen.appendChild(fl); setTimeout(() => fl.remove(), T.hit.flash);
      for (let i = 0; i < 3; i++) { const t = document.createElement("div"); t.className = "tear"; t.style.top = rnd(5, 90) + "%"; t.style.height = rnd(6, 40) + "px"; screen.appendChild(t); setTimeout(() => t.remove(), T.hit.tear * 2); }
      const kf = []; for (let i = 0; i <= 8; i++) { const a = T.hit.shakePx * (1 - i / 8); kf.push({ translate: `${rnd(-a, a)}px ${rnd(-a, a)}px` }); }
      screen.animate(kf, { duration: T.hit.shake, easing: "linear" });
    }
    if (hudPip) FX.shatter(hudPip);
  };

  FX.shatter = function (pip) {
    const r = pip.getBoundingClientRect(), host = pip.offsetParent || document.body, hr = host.getBoundingClientRect();
    const col = css("--accent");
    if (!reduced()) for (let i = 0; i < 5; i++) {
      const s = document.createElement("i");
      s.style.cssText = `position:absolute;left:${r.left - hr.left + r.width / 2 - 6}px;top:${r.top - hr.top + r.height / 2 - 6}px;width:12px;height:12px;background:${col};z-index:40;pointer-events:none;clip-path:polygon(${rnd(0, 40)}% 0,100% ${rnd(10, 60)}%,${rnd(20, 80)}% 100%)`;
      host.appendChild(s); const a = (i / 5) * Math.PI * 2 + rnd(-.4, .4);
      s.animate([{ translate: "0 0", rotate: "0deg", opacity: 1 }, { translate: `${Math.cos(a) * T.shatter.dist}px ${Math.sin(a) * T.shatter.dist}px`, rotate: `${rnd(-200, 200)}deg`, opacity: 0 }],
        { duration: T.shatter.life, easing: "cubic-bezier(.2,.8,.3,1)" }).onfinish = () => s.remove();
    }
    pip.classList.add("lost");
  };

  /* ---------------- 4. STRAIN (cyberpsychosis) ---------------- */
  const GLYPHS = "▓▒░█▚▞#%&$@!?¥ΞΣ0123456789";
  FX.strain = function (screen, level) {
    clearInterval(screen._strainC); clearInterval(screen._strainT);
    screen.classList.remove("strain-1", "strain-2");
    if (!screen.querySelector(".strainfx")) screen.insertAdjacentHTML("beforeend", `<div class="strainfx"></div>`);
    if (!level) return;
    screen.classList.add("strain-" + level);
    if (reduced()) return;
    const L = level - 1;
    screen._strainC = setInterval(() => {
      const pool = screen.querySelectorAll(".deck .lbl, .deck .tagl, .deck .micro");
      if (!pool.length) return;
      const el = pool[Math.floor(Math.random() * pool.length)]; if (el._busy) return;
      el._busy = true; const orig = el.textContent;
      el.textContent = [...orig].map((ch) => ch === " " || Math.random() < .35 ? ch : GLYPHS[Math.floor(Math.random() * GLYPHS.length)]).join("");
      el.classList.add("corrupt");
      setTimeout(() => { el.textContent = orig; el.classList.remove("corrupt"); el._busy = false; }, T.strain.corruptFor[L]);
    }, T.strain.corruptEvery[L]);
    if (level === 2) screen._strainT = setInterval(() => {
      const t = document.createElement("div"); t.className = "tear"; t.style.top = rnd(2, 95) + "%"; t.style.height = rnd(4, 26) + "px"; screen.appendChild(t); setTimeout(() => t.remove(), 60);
    }, T.strain.tearEvery);
  };

  /* ---------------- 7. DATAMOSH TRANSITION ---------------- */
  // Mockup implementation slices DOM clones into bands. In-game this is one full-screen shader pass
  // over the old and new frame (see MOTION.md), so there is no setup cost there.
  FX.moshPrep = function (stage, toEl) {
    const N = T.mosh.bands, H = stage.clientHeight, cuts = [0];
    for (let i = 1; i < N; i++) cuts.push(Math.round(H * (i / N) + rnd(-H / N / 3, H / N / 3))); cuts.push(H);
    const layer = document.createElement("div");
    layer.style.cssText = "position:absolute;inset:0;z-index:95;overflow:hidden;pointer-events:none;opacity:.001";
    stage.appendChild(layer);
    const mk = (src, i) => { const c = src.cloneNode(true); c.removeAttribute("id"); c.classList.remove("hidden"); c.style.visibility = "visible"; c.style.position = "absolute"; c.style.inset = "0"; c.style.willChange = "transform, filter, opacity"; c.style.clipPath = `inset(${cuts[i]}px 0 ${H - cuts[i + 1]}px 0)`; c.style.opacity = "0"; layer.appendChild(c); return c; };
    const to = []; for (let i = 0; i < N; i++) to.push(mk(toEl, i));
    return { layer, cuts, to, mk, N, H };
  };
  FX.datamosh = async function (stage, fromEl, toEl, prep) {
    if (reduced()) { fromEl.style.visibility = "hidden"; toEl.style.visibility = "visible"; return; }
    const P = prep || FX.moshPrep(stage, toEl);
    const { layer, cuts, N } = P;
    const from = []; for (let i = 0; i < N; i++) { const c = P.mk(fromEl, i); c.style.opacity = "1"; from.push(c); }
    layer.style.opacity = "1"; layer.style.background = css("--void");
    fromEl.style.visibility = "hidden";
    const hueA = ["0deg", "90deg", "160deg", "220deg", "300deg"];
    from.forEach((b, i) => {
      const dx = rnd(-140, 140) * (Math.random() < .5 ? 1 : .3), smear = Math.random() < .3;
      b.animate([{ translate: "0 0", filter: "none", transform: "none" },
                 { translate: `${dx}px 0`, filter: `hue-rotate(${hueA[i % 5]}) saturate(2.2) contrast(1.3)`, transform: smear ? `scaleY(${rnd(1.6, 3)})` : "none", transformOrigin: `50% ${cuts[i]}px` }],
                { duration: T.mosh.breakOut, easing: "cubic-bezier(.6,0,.9,.5)", fill: "forwards" });
    });
    await wait(T.mosh.breakOut);
    P.to.forEach((b, i) => {
      b.animate([{ translate: `${rnd(-120, 120)}px 0`, filter: `hue-rotate(${hueA[(i + 2) % 5]}) saturate(2)`, opacity: .6 }, { translate: "0 0", filter: "none", opacity: 1 }],
                { duration: T.mosh.total - T.mosh.breakOut, delay: rnd(0, 60), easing: "cubic-bezier(.1,.9,.2,1)", fill: "both" });
    });
    from.forEach((b) => b.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 70, fill: "forwards" }));
    await wait(T.mosh.total - T.mosh.breakOut + 70);
    toEl.classList.remove("hidden"); toEl.style.visibility = "visible"; layer.remove();
  };

  /* ---------------- 5. MICRO-TEXT (ticking counters) ---------------- */
  FX.tickers = function (root) {
    root.querySelectorAll("[data-tick]").forEach((el) => {
      let n = parseInt(el.dataset.tick, 10) || 0; const pre = el.dataset.pre || "";
      setInterval(() => { n += Math.floor(rnd(1, 37)); el.textContent = pre + n.toString(16).toUpperCase().padStart(6, "0"); }, 180);
    });
  };

  FX.wait = wait;
  window.FX = FX;
})();
