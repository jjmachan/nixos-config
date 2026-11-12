// tty's Go to (⌘p) and inbox (⌘⇧i): one fzf-style list in a dialog. Go to
// lists agents (most urgent first), then spaces, then tabs; the inbox lists
// agents only. No live preview: a terminal shown in a second place takes over
// its size (herdr-core: the last active viewer sets it), which squeezes the
// agent's own pane.
// Role "open" is how tty's status line asks for it: it closes its own carrier
// overlay and opens the list.

import { View, div } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { agents, spaces, panes, hc, run, theme, props, openOverlay, closeOverlay, shared, setShared, nextCommand } from "herdr";

const SPIN = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
const SHAPE = { blocked: "◉", done: "●", idle: "○" };
const RANK = { blocked: 0, working: 1, done: 2, idle: 3 };
const ROW = 26;
// A fixed size, so it doesn't stretch across a big screen.
const WIDTH = 640;
const HEIGHT = 440;

function glyph(t, status) {
  if (!status) return div().w(20).flex_none().text_color(t.dim).child("▸");
  return div().w(20).flex_none().text_color(t[status] ?? t.dim)
    .when(status === "working", (el) => el.frames(SPIN, 90))
    .child(status === "working" ? SPIN[0] : SHAPE[status] ?? "·");
}

// Everything the list can land on. `fields` are what a query is matched
// against, in order of weight; the first is drawn with its matched letters.
function items(source) {
  const sp = spaces(), ps = panes();
  const out = agents()
    .map((a, i) => ({ a, i }))
    .sort((x, y) => (RANK[x.a.status] ?? 9) - (RANK[y.a.status] ?? 9) || x.i - y.i)
    .map(({ a }) => {
      const branch = ps.find((p) => p.pane === a.pane)?.branch ?? "";
      return { key: `a:${a.address}`, kind: "agent", a, status: a.status, fields: [a.title || a.program?.name || "", branch, a.tab_name, a.space_name] };
    });
  if (source === "inbox") return out;
  for (const s of sp) out.push({ key: `s:${s.id}`, kind: "space", s, status: null, fields: [s.name, s.branch ?? "", "", ""] });
  for (const s of sp) for (const c of s.tabs) {
    if (c.settled) continue;
    out.push({ key: `t:${c.id}`, kind: "tab", s, c, status: null, fields: [c.name, s.branch ?? "", c.name, s.name] });
  }
  return out;
}

// Letters of q in order inside text: a score (runs, word starts and early hits
// count) and where they hit, or null.
function fuzzy(q, text) {
  const t = text.toLowerCase();
  let from = 0, last = -2, score = 0;
  const hits = [];
  for (const ch of q.toLowerCase()) {
    if (ch === " ") continue;
    const i = t.indexOf(ch, from);
    if (i < 0) return null;
    score += (i === last + 1 ? 6 : 1) + (i === 0 || /[\s/\-_.›:]/.test(t[i - 1]) ? 4 : 0);
    hits.push(i);
    last = i;
    from = i + 1;
  }
  return { score: score - t.length * 0.02 - (hits[0] ?? 0) * 0.05, hits };
}

function ranked(source, query) {
  const all = items(source);
  if (!query.trim()) return all.map((it) => ({ ...it, hits: [] }));
  const weights = [1, 0.8, 0.6, 0.5];
  const out = [];
  for (const it of all) {
    let best = null;
    it.fields.forEach((f, n) => {
      const m = f ? fuzzy(query, f) : null;
      if (m && (!best || m.score * weights[n] > best.score)) best = { score: m.score * weights[n], hits: n === 0 ? m.hits : [] };
    });
    if (best) out.push({ ...it, score: best.score, hits: best.hits });
  }
  return out.sort((x, y) => y.score - x.score);
}

// Text with its matched letters bold in accent.
function marked(t, text, hits, color, bold) {
  const set = new Set(hits);
  const runs = [];
  for (let i = 0; i < text.length; i++) {
    const on = set.has(i);
    if (runs.length && runs[runs.length - 1].on === on) runs[runs.length - 1].s += text[i];
    else runs.push({ on, s: text[i] });
  }
  return h_flex().min_w(0).overflow_hidden().whitespace_nowrap().children(runs.map((r) =>
    div().flex_none().text_color(r.on ? t.accent : color).when(r.on || bold, (el) => el.font_bold()).child(r.s)));
}

function show(source) {
  openOverlay({
    kind: "dialog", frame: "none", width: WIDTH, height: HEIGHT,
    layout: { type: "block", border: { width: 1, color: "accent" }, background: "background",
      content: { mod: "tty-goto", props: { role: "list", source } } },
  });
}

export default class Goto extends View {
  init(_props, cx) {
    const p = props() ?? {};
    this.role = p.role ?? "open";
    if (this.role === "open") {
      if (p.overlay) closeOverlay(p.overlay);
      show(p.source ?? "goto");
      return;
    }
    this.source = p.source ?? "goto";
    this.query = "";
    this.sel = this.list()[0]?.key ?? null;
    if (p.overlay) setShared("tty.goto", p.overlay);
    this.handle = cx.focus_handle();
    this.handle.focus();
    cx.timer.after(150, () => this.handle.focus());
    // A popup over it closing gives the keyboard back.
    cx.spawn(async () => {
      for (;;) if ((await nextCommand()) === "focus") this.handle.focus();
    });
  }

  // However it goes (Esc, a click beside it, ⌘p again), it's no longer open.
  async close() {
    if (this.role === "list" && shared("tty.goto") === props()?.overlay) setShared("tty.goto", null);
  }

  dismiss() {
    setShared("tty.goto", null);
    closeOverlay(props().overlay);
  }

  list() {
    return ranked(this.source, this.query);
  }

  move(by) {
    const list = this.list();
    if (!list.length) return;
    const i = Math.max(0, list.findIndex((x) => x.key === this.sel));
    this.sel = list[(i + by + list.length) % list.length].key;
  }

  go(it) {
    if (!it) return;
    this.dismiss();
    if (it.kind === "agent") run("agent.focus", { terminal: it.a.address });
    else if (it.kind === "space") run("space.select", { id: it.s.id });
    else { run("space.select", { id: it.s.id }); run("tab.select", { id: it.c.id }); }
  }

  // A blocked agent's choice, pressed without leaving the list.
  press(it, d, cx) {
    cx.spawn(async () => { await hc(["keys", it.a.address, d]).catch(() => null); });
  }

  key(e, cx) {
    cx.stop_propagation();
    const m = e.modifiers ?? {};
    const k = e.key_char ?? e.key;
    const list = this.list();
    const it = list.find((x) => x.key === this.sel) ?? list[0] ?? null;
    if (e.key === "escape") return this.dismiss();
    if (e.key === "enter" || e.key === "right") return this.go(it);
    if (e.key === "down" || (m.control && e.key === "n") || (e.key === "tab" && !m.shift)) { this.move(1); return cx.notify(); }
    if (e.key === "up" || (m.control && e.key === "p") || (e.key === "tab" && m.shift)) { this.move(-1); return cx.notify(); }
    if (/^[1-9]$/.test(k ?? "") && it?.status === "blocked" && !m.control && !m.platform) return this.press(it, k, cx);
    if (e.key === "backspace") {
      this.query = m.alt || m.control ? "" : this.query.slice(0, -1);
    } else if (k && k.length === 1 && !m.control && !m.platform && !m.alt) {
      this.query += k;
    } else return;
    this.sel = this.list()[0]?.key ?? null;
    cx.notify();
  }

  row(t, it, on) {
    const label = it.kind === "agent"
      ? h_flex().flex_1().min_w(0)
        .child(div().flex_none().text_color(t.muted).child(it.a.program?.key ?? "agent"))
        .child(div().flex_none().text_color(t.dim).child(" › "))
        .child(marked(t, it.fields[0], it.hits, t.foreground, on))
      : it.kind === "space"
        ? h_flex().flex_1().min_w(0).child(div().flex_none().w(48).text_color(t.dim).child("space"))
          .child(marked(t, it.s.name, it.hits, t.foreground, on))
        : h_flex().flex_1().min_w(0).child(div().flex_none().w(48).text_color(t.dim).child("tab"))
          .child(div().flex_none().text_color(t.muted).child(`${it.s.name} › `))
          .child(marked(t, it.c.name, it.hits, t.foreground, on));
    const right = it.kind === "agent"
      ? div().flex_none().text_color(it.status === "blocked" ? t.blocked : t.dim)
        .child(it.status === "blocked" ? "needs you" : `${it.a.space_name} · ${it.a.tab_name}`)
      : div().flex_none().text_color(t.ansi5).child(it.s.branch ?? "");
    return h_flex().id(`tg-${it.key}`).h(ROW).flex_none().pr(10).items_center().cursor_pointer()
      .when(on, (el) => el.bg(t.hover))
      .on_click(() => this.go(it))
      .child(div().w(12).flex_none().text_color(t.accent).child(on ? "▍" : ""))
      .child(glyph(t, it.status))
      .child(label)
      .child(div().w(12).flex_none())
      .child(right);
  }

  render() {
    const t = theme();
    if (this.role !== "list") return div();
    const list = this.list();
    const total = items(this.source).length;
    const blocked = agents().filter((a) => a.status === "blocked").length;
    const keys = [["enter", "go to"], ["1-9", "answer"], ["^n/^p", "move"], ["esc", "close"]];
    return v_flex().id("tty-goto").size_full().text_size(12.5).font_family("JetBrains Mono")
      .track_focus(this.handle)
      .on_mouse_down("left", () => this.handle.focus())
      .on_key_down((e, cx) => this.key(e, cx))
      .child(h_flex().h(26).flex_none().px(10).gap(8).items_center().border_b(1).border_color(t.border)
        .child(div().flex_none().font_bold().text_color(t.accent).child(this.source === "inbox" ? "inbox" : "go to"))
        .child(div().flex_1())
        .when(blocked > 0, (el) => el.child(div().flex_none().text_color(t.blocked).child(`◉ ${blocked} needs you`)))
        .child(div().flex_none().text_color(t.dim).child(`${list.length}/${total}`)))
      .child(h_flex().h(32).flex_none().px(10).gap(8).items_center().border_b(1).border_color(t.accent)
        .child(div().flex_none().font_bold().text_color(t.accent).child("❯"))
        .child(div().flex_1().min_w(0).truncate().text_color(t.foreground).child(this.query + "▏")))
      .child(v_flex().id("tg-list").flex_1().min_h(0).py(4).overflow_y_scrollbar()
        .when(!list.length, (el) => el.child(div().px(12).py(6).text_color(t.dim).child(total ? "No match." : "No agents running.")))
        .children(list.map((it) => this.row(t, it, it.key === this.sel))))
      .child(h_flex().h(24).flex_none().px(10).gap(14).items_center().border_t(1).border_color(t.border).text_size(11.5)
        .children(keys.map(([k, what]) => h_flex().flex_none().gap(5).child(div().text_color(t.accent).child(k)).child(div().text_color(t.dim).child(what)))));
  }
}
