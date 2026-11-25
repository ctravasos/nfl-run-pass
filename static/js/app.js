// NFL Run/Pass Tendencies — all aggregation runs here, from one compact JSON file per team.
// Logic mirrors the original R analysis (analysis/nfl_run_pass_decisions.rmd).
(() => {
  const META = JSON.parse(document.getElementById("meta").textContent);
  const CUR = META.current;
  const SEASONS = META.seasons;
  const HIST = `${SEASONS[0]}–${SEASONS[SEASONS.length - 1]}`;
  const TEAMS = Object.fromEntries(META.teams.map((t) => [t.abbr, t]));

  const DIST = ["Short (1-3)", "Medium (4-7)", "Standard (8-10)", "Long (10+)"];
  const ZONE = ["Own Territory (0-20)", "Own Half (21-50)", "Opponent Half (51-79)", "Red Zone (1-20)"];
  const SCORE = ["Down 21+", "Down 14-20", "Down 7-13", "Down 1-6", "Tied", "Up 1-6", "Up 7-13", "Up 14-20", "Up 21+"];
  const ORD = ["1st", "2nd", "3rd", "4th"];

  const distBin = (yt) => (yt < 0 ? -1 : yt <= 3 ? 0 : yt <= 7 ? 1 : yt <= 10 ? 2 : 3);
  const zoneBin = (yl) => (yl < 0 ? -1 : yl >= 80 ? 0 : yl >= 51 ? 1 : yl >= 21 ? 2 : 3);
  const scoreBin = (sd) =>
    sd === -999 ? -1 : sd <= -21 ? 0 : sd <= -14 ? 1 : sd <= -7 ? 2 : sd <= -1 ? 3 : sd === 0 ? 4 : sd <= 6 ? 5 : sd <= 13 ? 6 : sd <= 20 ? 7 : 8;
  const under2 = (b, i) => (b.q[i] === 2 || b.q[i] === 4) && b.qs[i] >= 0 && b.qs[i] <= 120;

  const round1 = (x) => Math.round(x * 10) / 10;
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

  // White or near-black text, whichever reads better on the team colour
  function textOn(hex) {
    const n = parseInt(hex.replace("#", ""), 16);
    const lin = (v) => ((v /= 255) <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
    const L = 0.2126 * lin((n >> 16) & 255) + 0.7152 * lin((n >> 8) & 255) + 0.0722 * lin(n & 255);
    return L > 0.4 ? "#111" : "#fff";
  }

  // ── Data ─────────────────────────────────────────────────────────────────────
  const cache = new Map();
  function loadTeam(abbr) {
    if (!cache.has(abbr)) {
      cache.set(abbr, fetch(`${META.base}/data/team/${abbr}.json`).then((r) => {
        if (!r.ok) throw new Error(`Could not load ${abbr}`);
        return r.json();
      }));
    }
    return cache.get(abbr);
  }

  // Pass share of the plays in idx (indexes into block b)
  function split(b, idx) {
    let pass = 0;
    for (const i of idx) pass += b.p[i];
    const n = idx.length;
    const p = n ? round1((pass / n) * 100) : 0;
    return { n, pass: p, rush: round1(100 - p) };
  }

  const allIdx = (b) => Array.from(b.s, (_, i) => i);

  // One row per group present in the current season: current split + five-season split
  function stacked(b, keyFn, keys, labelFn) {
    const curr = new Map(), hist = new Map();
    for (const k of keys) { curr.set(k, []); hist.set(k, []); }
    for (let i = 0; i < b.s.length; i++) {
      const k = keyFn(i);
      if (!hist.has(k)) continue;
      hist.get(k).push(i);
      if (b.s[i] === CUR) curr.get(k).push(i);
    }
    return keys
      .map((k) => ({ label: labelFn(k), c: split(b, curr.get(k)), h: split(b, hist.get(k)) }))
      .filter((r) => r.c.n > 0);
  }

  // ── Rendering ────────────────────────────────────────────────────────────────
  function barRow(label, team, c, h, n) {
    const fmt = (v, hv) => (hv == null ? `${v}%` : `${v}% (${hv}%)`);
    const rushT = fmt(c.rush, h && h.rush), passT = fmt(c.pass, h && h.pass);
    const seg = (pct, color, text, kind) =>
      pct > 0
        ? `<div class="seg" style="width:${pct}%;background:${color};color:${textOn(color)}" title="${kind}: ${esc(text)}">${pct >= 14 ? esc(text) : pct >= 6 ? `${pct}%` : ""}</div>`
        : "";
    return `<div class="bar-row"><div class="bar-label">${esc(label)}</div>
      <div class="bar">${seg(c.rush, team.color2, rushT, "Rush")}${seg(c.pass, team.color, passT, "Pass")}</div>
      <div class="bar-n">n=${n.toLocaleString()}</div></div>`;
  }

  function emptyRow(label) {
    return `<div class="bar-row"><div class="bar-label">${esc(label)}</div><div class="bar"><span class="bar-empty">No plays</span></div><div class="bar-n">n=0</div></div>`;
  }

  function chart(title, subtitle, body, note = "") {
    return `<div class="chart"><div class="chart-head"><h3>${esc(title)}</h3><span class="muted">${esc(subtitle)}</span></div>${body}${note}</div>`;
  }

  function facets(sides) {
    return sides
      .map(({ title, team, rows, noHist }) =>
        `<div class="facet"><div class="facet-title">${esc(title)}</div>${
          rows.length ? rows.map((r) => barRow(r.label, team, r.c, noHist ? null : r.h, r.c.n)).join("") : `<p class="muted">No ${CUR} plays yet.</p>`
        }</div>`)
      .join("");
  }

  // ── State ────────────────────────────────────────────────────────────────────
  const params = new URLSearchParams(location.hash.slice(1));
  const state = {
    off: TEAMS[params.get("off")] ? params.get("off") : META.defaults.off,
    def: TEAMS[params.get("def")] ? params.get("def") : META.defaults.def,
    tab: params.get("tab") === "custom" ? "custom" : "overview",
  };

  const FILTERS = [
    { key: "year", label: "Year", opts: SEASONS.map((s) => [s, String(s)]) },
    { key: "down", label: "Down", opts: ORD.map((o, i) => [i + 1, o]) },
    { key: "dist", label: "Distance", opts: DIST.map((d, i) => [i, d]) },
    { key: "zone", label: "Field Position", opts: ZONE.map((z, i) => [i, z]) },
    { key: "score", label: "Score Differential", opts: SCORE.map((s, i) => [i, s]) },
    { key: "qtr", label: "Quarter", opts: [[1, "Q1"], [2, "Q2"], [3, "Q3"], [4, "Q4"], [5, "OT"]] },
    { key: "sit", label: "Special Situations", opts: [["first", "First Play of Drive"], ["ato", "First Play After Timeout"], ["u2", "Under 2 Min in Half"], ["other", "All Other Plays"]] },
    { key: "ctx", label: "Previous Drive Ended With", opts: META.contexts.slice(0, -1).map((c, i) => [i, c]) },
  ];
  const sel = {};
  const resetFilters = () => FILTERS.forEach((f) => (sel[f.key] = new Set(f.opts.map((o) => o[0]))));
  resetFilters();
  // Only filter on a strict subset; nothing or everything selected means no filter
  const isSub = (f) => sel[f.key].size > 0 && sel[f.key].size < f.opts.length;
  const F = Object.fromEntries(FILTERS.map((f) => [f.key, f]));

  function applyFilters(b, skipYear) {
    const on = (k) => isSub(F[k]) && !(k === "year" && skipYear);
    const S = sel;
    const out = [];
    for (let i = 0; i < b.s.length; i++) {
      if (on("year") && !S.year.has(b.s[i])) continue;
      if (on("down") && !S.down.has(b.dn[i])) continue;
      if (on("dist") && !S.dist.has(distBin(b.yt[i]))) continue;
      if (on("zone") && !S.zone.has(zoneBin(b.yl[i]))) continue;
      if (on("score") && !S.score.has(scoreBin(b.sd[i]))) continue;
      if (on("qtr") && !S.qtr.has(b.q[i])) continue;
      if (on("sit")) {
        const first = b.f[i] === 1, ato = b.t[i] === 1, u2 = under2(b, i);
        const other = !first && !ato && !u2;
        if (!((S.sit.has("first") && first) || (S.sit.has("ato") && ato) || (S.sit.has("u2") && u2) || (S.sit.has("other") && other))) continue;
      }
      // Previous-drive filter looks only at the first play of each drive
      if (on("ctx") && !(b.f[i] === 1 && S.ctx.has(b.c[i]))) continue;
      out.push(i);
    }
    return out;
  }

  function filterLabel(includeYear) {
    const parts = FILTERS.filter((f) => isSub(f) && (includeYear || f.key !== "year")).map((f) => {
      const names = f.opts.filter((o) => sel[f.key].has(o[0])).map((o) => o[1]);
      return `${f.label}: ${names.join(" + ")}`;
    });
    return parts.length ? parts.join(" | ") : "No filters applied";
  }

  function histTitle() {
    const ys = [...sel.year].sort();
    if (ys.length === 0 || ys.length === SEASONS.length) return HIST;
    if (ys.length === 1) return `${ys[0]} Season`;
    return `${ys[0]}–${ys[ys.length - 1]}`;
  }

  // ── Views ────────────────────────────────────────────────────────────────────
  function renderOverview(O, D, ot, dt) {
    const sub = `${ot.nick} offense vs ${dt.nick} defense · ${CUR}% (${HIST} avg%)`;
    const oAll = allIdx(O), dAll = allIdx(D);
    const curOf = (b, idx) => idx.filter((i) => b.s[i] === CUR);
    const overall = [
      { label: `${ot.nick} offense`, team: ot, c: split(O, curOf(O, oAll)), h: split(O, oAll) },
      { label: `${dt.nick} defense`, team: dt, c: split(D, curOf(D, dAll)), h: split(D, dAll) },
    ];
    const sides = (keyFn, keys, labelFn) => [
      { title: `${ot.name} offense`, team: ot, rows: stacked(O, (i) => keyFn(O, i), keys, labelFn) },
      { title: `${dt.name} defense`, team: dt, rows: stacked(D, (i) => keyFn(D, i), keys, labelFn) },
    ];
    const idx = (n) => [...Array(n).keys()];
    const byYear = (b) => SEASONS.map((s) => {
      const ix = []; for (let i = 0; i < b.s.length; i++) if (b.s[i] === s) ix.push(i);
      return { label: String(s), c: split(b, ix) };
    }).filter((r) => r.c.n > 0);

    document.getElementById("overview").innerHTML = [
      chart("Overall", sub, `<div class="facet">${overall.map((r) => barRow(r.label, r.team, r.c, r.h, r.c.n)).join("")}</div>`),
      chart("By Down", sub, facets(sides((b, i) => b.dn[i], [1, 2, 3, 4], (k) => `${ORD[k - 1]} Down`))),
      chart("By Distance", sub, facets(sides((b, i) => distBin(b.yt[i]), idx(4), (k) => DIST[k]))),
      chart("By Field Position", sub, facets(sides((b, i) => zoneBin(b.yl[i]), idx(4), (k) => ZONE[k]))),
      chart("By Score Differential", sub, facets(sides((b, i) => scoreBin(b.sd[i]), idx(9), (k) => SCORE[k]))),
      chart("By Quarter", sub, facets(sides((b, i) => b.q[i], [1, 2, 3, 4], (k) => `${ORD[k - 1]} Quarter`))),
      chart("By Year", `${ot.nick} offense vs ${dt.nick} defense`, facets([
        { title: `${ot.name} offense`, team: ot, rows: byYear(O), noHist: true },
        { title: `${dt.name} defense`, team: dt, rows: byYear(D), noHist: true },
      ])),
    ].join("");
  }

  function renderFilters() {
    document.getElementById("filters").innerHTML = FILTERS.map((f) =>
      `<div class="filter-group"><div class="field-label"><span>${esc(f.label)}</span>${
        isSub(f) || sel[f.key].size === 0 ? `<span class="all-toggle" data-all="${f.key}">Select all</span>` : ""
      }</div><div class="pill-group">${f.opts.map(([v, l]) =>
        `<button class="pill ${sel[f.key].has(v) ? "active" : ""}" data-f="${f.key}" data-v="${esc(v)}">${esc(l)}</button>`).join("")}</div></div>`
    ).join("");
  }

  function renderCustom(O, D, ot, dt) {
    const oCur = applyFilters(O, true).filter((i) => O.s[i] === CUR);
    const dCur = applyFilters(D, true).filter((i) => D.s[i] === CUR);
    const oHist = applyFilters(O, false);
    const dHist = applyFilters(D, false);
    const rows = (pairs) => `<div class="facet">${pairs.map(([label, team, b, ix]) =>
      ix.length ? barRow(label, team, split(b, ix), null, ix.length) : emptyRow(label)).join("")}</div>`;

    const small = [];
    if (oCur.length < META.smallSample) small.push(`${ot.nick} offense: only ${oCur.length} plays`);
    if (dCur.length < META.smallSample) small.push(`${dt.nick} defense: only ${dCur.length} plays`);
    const note = small.length
      ? `<p class="note warn">Small sample: ${esc(small.join("; "))}</p>`
      : `<p class="note">${CUR}: ${ot.nick} offense ${oCur.length} plays · ${dt.nick} defense ${dCur.length} plays</p>`;

    document.getElementById("custom").innerHTML = [
      chart(`${CUR} Season`, filterLabel(false),
        rows([[`${ot.nick} offense`, ot, O, oCur], [`${dt.nick} defense`, dt, D, dCur]]), note),
      chart(histTitle(), filterLabel(true),
        rows([[`${ot.nick} offense`, ot, O, oHist], [`${dt.nick} defense`, dt, D, dHist]])),
    ].join("");
  }

  function renderChrome(ot, dt) {
    document.getElementById("legend").innerHTML = [[ot, "Offense"], [dt, "Defense"]].map(([t, role]) =>
      `<div><div class="legend-team">${esc(t.name)}<span class="muted">${role}</span></div>
        <div class="legend-bar"><div style="background:${t.color2};color:${textOn(t.color2)}">Rush</div><div style="background:${t.color};color:${textOn(t.color)}">Pass</div></div></div>`
    ).join("");
    const m = document.getElementById("matchup");
    m.style.setProperty("--off-c", ot.color);
    m.style.setProperty("--def-c", dt.color);
    m.innerHTML = `<div class="side"><img src="${ot.logo}" alt=""><div><div class="name">${esc(ot.name)}</div><div class="vs">Offense</div></div></div>
      <div class="side"><img src="${dt.logo}" alt=""><div><div class="name">${esc(dt.name)}</div><div class="vs">Defense</div></div></div>`;
    document.title = `${ot.nick} offense vs ${dt.nick} defense — NFL Run/Pass Tendencies`;
  }

  let data = null;
  function renderAll() {
    if (!data) return;
    const [O, D] = data;
    const ot = TEAMS[state.off], dt = TEAMS[state.def];
    renderOverview(O, D, ot, dt);
    renderFilters();
    renderCustom(O, D, ot, dt);
  }

  async function load() {
    const ot = TEAMS[state.off], dt = TEAMS[state.def];
    renderChrome(ot, dt);
    history.replaceState(null, "", `#off=${state.off}&def=${state.def}${state.tab === "custom" ? "&tab=custom" : ""}`);
    try {
      const [o, d] = await Promise.all([loadTeam(state.off), loadTeam(state.def)]);
      if (ot !== TEAMS[state.off] || dt !== TEAMS[state.def]) return; // selection changed while loading
      data = [o.o, d.d];
      renderAll();
    } catch (e) {
      document.getElementById("overview").innerHTML = `<p class="note warn">${esc(e.message)}</p>`;
    }
  }

  // ── Wiring ───────────────────────────────────────────────────────────────────
  for (const [id, key] of [["sel-off", "off"], ["sel-def", "def"]]) {
    const el = document.getElementById(id);
    el.innerHTML = META.teams.map((t) => `<option value="${t.abbr}">${esc(t.name)}</option>`).join("");
    el.value = state[key];
    el.addEventListener("change", () => { state[key] = el.value; load(); });
  }

  function showTab(tab) {
    state.tab = tab;
    document.querySelectorAll("[data-tab]").forEach((b) => b.classList.toggle("active", b.dataset.tab === tab));
    document.getElementById("tab-overview").hidden = tab !== "overview";
    document.getElementById("tab-custom").hidden = tab !== "custom";
    history.replaceState(null, "", `#off=${state.off}&def=${state.def}${tab === "custom" ? "&tab=custom" : ""}`);
  }
  document.querySelectorAll("[data-tab]").forEach((b) => b.addEventListener("click", () => showTab(b.dataset.tab)));

  document.getElementById("filters").addEventListener("click", (e) => {
    const pill = e.target.closest("[data-f]");
    const all = e.target.closest("[data-all]");
    if (pill) {
      const f = F[pill.dataset.f];
      const v = f.opts.find((o) => String(o[0]) === pill.dataset.v)[0];
      sel[f.key].has(v) ? sel[f.key].delete(v) : sel[f.key].add(v);
    } else if (all) {
      sel[all.dataset.all] = new Set(F[all.dataset.all].opts.map((o) => o[0]));
    } else return;
    renderAll();
  });
  document.getElementById("clear").addEventListener("click", () => { resetFilters(); renderAll(); });

  showTab(state.tab);
  load();
})();
