// tty: Herdr drawn like a terminal. One mod, many pieces: props().role picks
// topline, spaces, agents, keys or statusline. With no role it is a pane
// frame's header (Herdr passes props().pane); variant "rule" (tty-zen) drops
// the index chip's background. variant "zen" is tty-zen's top and status line.

import { View, div } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import {
  spaces, panes, agents, terminals, focused, machines, window, theme, shared, setShared,
  props, run, exec, openOverlay, closeOverlay, setAgentOrder, nextCommand, home,
} from "herdr";

const SPIN = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
const SHAPE = { blocked: "◉", done: "●", idle: "○" };
// Agents list order: needs you, then working, done, idle.
const RANK = { blocked: 0, working: 1, done: 2, idle: 3 };
const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

const tilde = (path) => {
  if (!path) return "";
  const h = home();
  return path === h ? "~" : path.startsWith(h + "/") ? "~" + path.slice(h.length) : path;
};
const trim = (path) => path.replace(/\/+$/, "");
const base = (path) => trim(path).split("/").pop();
const parent = (path) => trim(path).split("/").slice(0, -1).join("/") || "/";
const pad2 = (n) => String(n).padStart(2, "0");

// Where a space is now: its first terminal's live folder, else where it was made.
function place(s, ps) {
  const tabs = new Set(s.tabs.map((c) => c.id));
  return ps.find((p) => tabs.has(p.tab) && p.cwd)?.cwd || s.folder || "";
}
const where = (s, ps) => JSON.stringify([s.machine ?? null, place(s, ps)]);

function glyph(t, status) {
  if (!status) return div().flex_none();
  return div().flex_none().text_color(t[status] ?? t.dim)
    .when(status === "working", (el) => el.frames(SPIN, 90))
    .child(status === "working" ? SPIN[0] : SHAPE[status] ?? "·");
}

function minutes(since) {
  const m = Math.max(0, Math.floor((Date.now() - since) / 60000));
  return m < 60 ? `${m}m` : `${Math.floor(m / 60)}h${pad2(m % 60)}m`;
}

// When the tab holding this agent started working, or null.
function workingSince(tabId) {
  for (const s of spaces()) for (const c of s.tabs) if (c.id === tabId) return c.working_since;
  return null;
}

function sortedAgents() {
  return agents()
    .map((a, i) => ({ a, i }))
    .sort((x, y) => (RANK[x.a.status] ?? 9) - (RANK[y.a.status] ?? 9) || x.i - y.i)
    .map((x) => x.a);
}

// Non-zero agent counts: ◉n, spinner n, ●n, ○n.
function counts(t, list, gap) {
  const n = (st) => list.filter((a) => a.status === st).length;
  return h_flex().flex_none().gap(gap).items_center()
    .children(["blocked", "working", "done", "idle"].filter((st) => n(st) > 0).map((st) =>
      h_flex().gap(st === "working" ? 4 : 0).items_center().text_color(t[st] ?? t.dim)
        .child(glyph(t, st)).child(String(n(st)))));
}

// The focused pane, whether it's a model pane or a layout block showing a terminal.
function focusedPane() {
  const f = focused();
  if (!f) return null;
  const ps = panes();
  return ps.find((p) => p.pane === f.pane) ?? ps.find((p) => f.terminal && p.terminal === f.terminal) ?? null;
}

// LazyVim-style mode, from the first rule that matches.
function mode(t) {
  if (shared("tty.goto")) return ["COMMAND", t.ansi3];
  const p = focusedPane();
  if (p?.status === "blocked") return ["REPLACE", t.ansi1];
  if (p?.status === "working") return ["INSERT", t.ansi2];
  if (p?.zoomed) return ["VISUAL", t.ansi5];
  if (!p || !p.status) return ["TERMINAL", t.ansi6];
  return ["NORMAL", t.ansi4];
}

function clock(long) {
  const d = new Date();
  const hm = `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
  return long ? `${DAYS[d.getDay()]} ${d.getDate()} ${MONTHS[d.getMonth()]} ${hm}` : hm;
}

// What a pane's program is called in headers: agents by key, shells by name.
function programLabel(p) {
  const prog = p.program;
  if (!prog) return "shell";
  if (prog.shell) return prog.name;
  return prog.key === "program" ? (prog.name || "program") : prog.key;
}

// The keys the person actually has, written the way this platform does.
function keyHints() {
  const mac = window()?.platform === "macos";
  return mac
    ? [["⌘p", "go to"], ["⌘⇧i", "inbox"], ["⌘b", "sidebar"]]
    : [["^⇧o", "go to"], ["^⇧i", "inbox"], ["^⇧b", "sidebar"]];
}

export default class Tty extends View {
  init(_props, cx) {
    const role = props()?.role ?? "header";
    this.role = role;
    this.common = {}; // where() -> git common dir, null: not a repo
    this.asked = new Set(); // where()s being asked
    this.ids = "";
    this.git = null; // shown space's { key, ahead, modified, untracked, branch }
    try { this.folds = new Set(JSON.parse(localStorage.getItem("tty.folds") ?? "[]")); } catch { this.folds = new Set(); }
    try { this.last = JSON.parse(localStorage.getItem("tty.last") ?? "{}"); } catch { this.last = {}; }

    if (role === "spaces" || role === "topline") {
      this.lookForRepos(cx);
      cx.timer.every(1000, (cx) => this.lookForRepos(cx));
    }
    if (role === "spaces") {
      this.refreshCounts(cx);
      cx.timer.every(5000, (cx) => this.refreshCounts(cx));
    }
    // Clock and working minutes. Minutes only: a redraw is a whole-window redraw.
    if (role !== "keys" && role !== "spaces") cx.timer.every(15000, (cx) => cx.notify());
    if (role === "statusline") {
      cx.spawn(async (cx) => {
        for (;;) {
          const c = await nextCommand();
          if (c === "goto" || c === "inbox") this.toggleGoto(c);
          else if (c === "tab-left") this.moveTab(-1);
          else if (c === "tab-right") this.moveTab(1);
          cx.notify();
        }
      });
    }
  }

  // ---- git -------------------------------------------------------------

  // Ask git for each space's common dir once per place; start over when the
  // spaces themselves change. Spaces sharing one are worktrees of one repo.
  lookForRepos(cx) {
    const sp = spaces(), ps = panes();
    const ids = sp.map((s) => s.id).join(",");
    if (ids !== this.ids) { this.ids = ids; this.common = {}; }
    const want = this.role === "topline" ? sp.filter((s) => s.active) : sp;
    for (const s of want) {
      const key = where(s, ps);
      const [on, cwd] = JSON.parse(key);
      if (!cwd || key in this.common || this.asked.has(key)) continue;
      this.asked.add(key);
      cx.spawn(async (cx) => {
        try {
          const r = await exec("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, on });
          this.common[key] = r.code === 0 ? trim(r.stdout.trim()) : null;
        } catch {
          // The machine is away: show the space without git, ask again later.
        }
        this.asked.delete(key);
        cx.notify();
      });
    }
  }

  // Branch and ⇡ ! ? for the shown space, on its machine.
  refreshCounts(cx) {
    const s = spaces().find((s) => s.active);
    if (!s) return;
    const key = where(s, panes());
    const [on, cwd] = JSON.parse(key);
    if (!cwd) return;
    cx.spawn(async (cx) => {
      try {
        const r = await exec("git", ["status", "--porcelain=v2", "--branch"], { cwd, on });
        if (r.code !== 0) { this.git = null; cx.notify(); return; }
        const g = { key, ahead: 0, modified: 0, untracked: 0, branch: null };
        for (const line of r.stdout.split("\n")) {
          if (line.startsWith("# branch.head ")) g.branch = line.slice(14);
          else if (line.startsWith("# branch.ab ")) g.ahead = Number(line.split(" ")[2]?.replace("+", "")) || 0;
          else if (line.startsWith("1 ") || line.startsWith("2 ")) g.modified++;
          else if (line.startsWith("? ")) g.untracked++;
        }
        this.git = g;
      } catch {
        this.git = null;
      }
      cx.notify();
    });
  }

  repoFolder(common) {
    return common.endsWith("/.git") ? common.slice(0, -5) : common.replace(/\.git$/, "");
  }

  // ---- boxes -----------------------------------------------------------

  // A 1px box with its title cut into the top rule, TUI style. A border would
  // paint over anything laid on it, so the top rule is drawn as line segments
  // with the labels between them, and the box keeps only its other three sides.
  box(t, id, title, right, body) {
    const line = (el) => el.h(1).bg(t.border);
    return div().id(id).relative().size_full().bg(t.canvas).text_size(12.5)
      .child(div().absolute().top(22).left(10).right(10).bottom(4)
        .border_l(1).border_r(1).border_b(1).border_color(t.border)
        .child(v_flex().id(`${id}-list`).size_full().pt(8).pb(4).overflow_y_scrollbar().children(body)))
      .child(h_flex().absolute().top(13).left(10).right(10).h(18).items_center()
        .child(line(div().w(10).flex_none()))
        .child(h_flex().flex_none().px(6).font_bold().text_color(t.accent).child(title))
        .child(line(div().flex_1()))
        .when(Boolean(right), (el) => el.child(h_flex().flex_none().px(6).gap(6).items_center().child(right)))
        .child(line(div().w(10).flex_none())));
  }

  // ---- spaces box ------------------------------------------------------

  spaceRows() {
    const sp = spaces(), ps = panes();
    const info = sp.map((s) => {
      const common = this.common[where(s, ps)] ?? null;
      return { s, common, group: common ? JSON.stringify([s.machine ?? null, common]) : null };
    });
    const size = {};
    for (const i of info) if (i.group) size[i.group] = (size[i.group] ?? 0) + 1;
    const rows = [], seen = new Set();
    for (const i of info) {
      if (!i.group || size[i.group] < 2) { rows.push({ kind: "space", s: i.s, guide: null }); continue; }
      if (seen.has(i.group)) continue;
      seen.add(i.group);
      const members = info.filter((m) => m.group === i.group);
      rows.push({ kind: "repo", group: i.group, folder: this.repoFolder(i.common), machine: i.s.machine });
      if (!this.folds.has(i.group)) {
        members.forEach((m, n) => rows.push({ kind: "space", s: m.s, guide: n === members.length - 1 ? "└─" : "├─" }));
      }
    }
    return rows;
  }

  repoRow(t, r) {
    const folded = this.folds.has(r.group);
    return h_flex().id(`repo-${r.group}`).h(22).flex_none().px(8).gap(6).items_center().cursor_pointer()
      .on_click((_e, cx) => {
        folded ? this.folds.delete(r.group) : this.folds.add(r.group);
        try { localStorage.setItem("tty.folds", JSON.stringify([...this.folds])); } catch {}
        cx.notify();
      })
      .child(div().flex_none().text_color(t.dim).child(folded ? "▸" : "▾"))
      .child(div().flex_none().font_bold().text_color(t.accent).child(base(r.folder)))
      .when(Boolean(r.machine), (el) => el.child(div().flex_none().text_color(t.ansi6).child(`@${r.machine}`)))
      .child(div().flex_1().min_w(0).truncate().text_right().text_color(t.dim).child(r.machine ? parent(r.folder) : tilde(parent(r.folder))));
  }

  spaceRow(t, r) {
    const s = r.s;
    const on = s.active;
    const g = on && this.git && this.git.key === where(s, panes()) ? this.git : null;
    const branch = g?.branch ?? s.branch;
    const head = h_flex().h(22).gap(0).items_center()
      .child(div().flex_none().text_color(t.dim).child(r.guide ? `${r.guide} ` : "▸ "))
      .child(div().flex_shrink(1).min_w(0).truncate()
        .text_color(on ? t.foreground : t.muted).when(on, (el) => el.font_bold()).child(s.name))
      .when(Boolean(s.machine), (el) => el.child(div().flex_none().pl(6).text_color(t.ansi6).child(`@${s.machine}`)))
      .child(div().flex_1())
      .child(glyph(t, s.status));
    const detail = on && branch ? h_flex().h(18).gap(6).items_center().text_size(11.5)
      .child(div().flex_none().text_color(t.dim).child(r.guide === "├─" ? "│  │" : r.guide ? "   │" : "│"))
      .child(div().flex_shrink(1).min_w(0).truncate().text_color(t.ansi5).child(branch))
      .when(g?.ahead > 0, (el) => el.child(div().flex_none().text_color(t.ansi2).child(`⇡${g.ahead}`)))
      .when(g?.modified > 0, (el) => el.child(div().flex_none().text_color(t.ansi3).child(`!${g.modified}`)))
      .when(g?.untracked > 0, (el) => el.child(div().flex_none().text_color(t.ansi6).child(`?${g.untracked}`))) : null;
    return v_flex().id(`space-${s.id}`).flex_none().px(8).cursor_pointer()
      .when(on, (el) => el.bg(t.hover))
      .on_click(() => run("space.select", { id: s.id }))
      .on_mouse_down("right", () => openOverlay({ mod: "menu", kind: "popup", width: 200, height: 260, props: { tab: "space", target: { id: s.id } } }))
      .child(head)
      .when(Boolean(detail), (el) => el.child(detail));
  }

  renderSpaces(t) {
    const sp = spaces();
    const right = h_flex().gap(6).items_center().text_color(t.dim)
      .child(String(sp.length))
      .child(div().id("tty-space-new").cursor_pointer().hover((s) => s.text_color(t.foreground))
        .on_click(() => openOverlay({ mod: "new-menu", kind: "popup", width: 250, height: 512 }))
        .child("+"));
    const rows = this.spaceRows().map((r) => (r.kind === "repo" ? this.repoRow(t, r) : this.spaceRow(t, r)));
    return this.box(t, "tty-spaces", "spaces", right, rows);
  }

  // ---- agents box ------------------------------------------------------

  agentRows(t, list) {
    const sp = spaces();
    const live = terminals().filter((x) => x.parent && x.state === "live");
    const rows = [];
    for (const a of list) {
      const machine = sp.find((s) => s.id === a.space)?.machine ?? null;
      const since = a.status === "working" ? workingSince(a.tab) : null;
      const state = a.status === "blocked" ? ["needs you", t.blocked]
        : a.status === "working" ? [since ? minutes(since) : "", t.muted]
        : a.status === "done" ? ["done", t.done] : ["idle", t.dim];
      rows.push(v_flex().id(`agent-${a.address}`).flex_none().px(8).py(3).cursor_pointer()
        .when(a.focused, (el) => el.bg(t.hover))
        .on_click(() => run("agent.focus", { terminal: a.address }))
        .child(h_flex().h(18).items_center()
          .child(h_flex().w(18).flex_none().child(glyph(t, a.status)))
          .child(div().flex_none().text_color(t.muted).child(a.program?.key ?? "agent"))
          .child(div().flex_none().text_color(t.dim).child(" › "))
          .child(div().flex_1().min_w(0).truncate().text_color(t.foreground).when(a.focused, (el) => el.font_bold()).child(a.title || a.program?.name || ""))
          .child(div().flex_none().pl(6).text_color(state[1]).child(state[0])))
        .child(div().pl(18).h(16).text_size(11.5).text_color(t.dim).truncate()
          .child(machine ? `${a.space_name} @${machine}` : `${a.space_name} · tab ${a.tab_index}`)));
      for (const k of live.filter((x) => x.parent === a.address)) {
        const st = k.status === "error" ? "blocked" : RANK[k.status] !== undefined ? k.status : null;
        rows.push(h_flex().id(`sub-${k.address}`).h(20).flex_none().px(8).pl(26).items_center().cursor_pointer()
          .on_click(() => run("terminal.peek", { terminal: k.address }))
          .child(div().flex_none().text_color(t.dim).child("└ "))
          .child(h_flex().w(16).flex_none().child(glyph(t, st)))
          .child(div().flex_1().min_w(0).truncate()
            .child(h_flex().child(div().text_color(t.muted).child(k.program?.key ?? "program"))
              .child(div().text_color(t.dim).child(" › "))
              .child(div().text_color(t.foreground).child(k.name || k.argv?.[0] || ""))))
          .child(div().flex_none().pl(6).text_color(t.muted).child(`${k.address} ${k.status ?? k.state}`)));
      }
    }
    return rows;
  }

  renderAgents(t) {
    const list = sortedAgents();
    setAgentOrder(list.map((a) => a.address));
    return this.box(t, "tty-agents", "agents", list.length ? counts(t, list, 6) : null, this.agentRows(t, list));
  }

  renderKeys(t) {
    return h_flex().size_full().px(14).gap(14).items_center().bg(t.canvas).text_size(11.5).text_color(t.dim)
      .children(keyHints().map(([k, what]) => h_flex().gap(5).child(div().text_color(t.ansi6).child(k)).child(what)));
  }

  // ---- top line --------------------------------------------------------

  machinesList(t) {
    return h_flex().flex_none().gap(12).items_center().children(machines().map((m) => {
      const mark = m.layout === "ready" ? glyph(t, "done")
        : m.layout === "loading" ? glyph(t, "working")
        : div().flex_none().text_color(t.dim).child("○");
      return h_flex().gap(5).items_center().child(mark).child(div().text_color(t.muted).child(m.name ?? "local"));
    }));
  }

  attention(t, zen) {
    const blocked = agents().filter((a) => a.status === "blocked");
    if (!blocked.length) return div().flex_none();
    const go = () => blocked.length === 1 ? run("agent.focus", { terminal: blocked[0].address }) : run("tty.inbox");
    if (zen) {
      return div().id("tty-attention").flex_none().cursor_pointer().text_color(t.blocked).on_click(go)
        .child(`◉ ${blocked.length} needs you`);
    }
    const mac = window()?.platform === "macos";
    return h_flex().id("tty-attention").flex_none().h(22).px(8).gap(8).items_center().cursor_pointer()
      .border_1().border_color(t.blocked).bg(t.blocked + "1f")
      .on_click(go)
      .child(div().text_color(t.blocked).child(blocked.length === 1 ? `◉ ${blocked[0].title || blocked[0].program?.key} needs you` : `◉ ${blocked.length} need you`))
      .child(div().text_color(t.muted).child(mac ? "⌘⇧I" : "^⇧I"));
  }

  renderTopline(t, zen) {
    const s = spaces().find((s) => s.active);
    const mac = window()?.platform === "macos";
    const maximize = (e) => { if (e.click_count === 2) run("window.maximize"); };
    if (zen) {
      return h_flex().size_full().relative().bg(t.chrome).text_size(13).items_center().justify_center()
        .on_mouse_down("left", maximize)
        .child(h_flex().gap(8).items_center().text_color(t.dim)
          .child(s?.name ?? "")
          .when(Boolean(s?.branch), (el) => el.child(div().text_color(t.raised).child("—")).child(div().text_color(t.ansi5).child(s.branch))))
        .child(h_flex().absolute().right(14).top(0).bottom(0).items_center().child(this.attention(t, true)));
    }
    const common = s ? this.common[where(s, panes())] : null;
    const repo = common ? base(this.repoFolder(common)) : null;
    const bar = () => div().flex_none().text_color(t.raised).child("│");
    return h_flex().size_full().bg(t.chrome).text_size(13).items_center().gap(10)
      .pl(mac ? 80 : 14).pr(14)
      .on_mouse_down("left", maximize)
      .child(h_flex().flex_none().child(div().font_bold().text_color(t.accent).child("herdr")).child(div().text_color(t.dim).child("/tty")))
      .child(bar())
      .when(Boolean(s), (el) => el.child(h_flex().flex_1().min_w(0).items_center().overflow_hidden()
        .when(Boolean(repo) && repo !== s.name, (el) => el.child(div().flex_none().text_color(t.muted).child(repo)).child(div().flex_none().text_color(t.dim).child(" / ")))
        .child(div().flex_none().font_bold().text_color(t.foreground).child(s.name))
        .when(Boolean(s.machine), (el) => el.child(div().flex_none().text_color(t.ansi6).child(`@${s.machine}`)))
        .when(Boolean(s.branch), (el) => el.child(div().flex_none().text_color(t.dim).child(" on ")).child(div().min_w(0).truncate().text_color(t.ansi5).child(s.branch)))))
      .when(!s, (el) => el.child(div().flex_1()))
      .child(this.attention(t, false))
      .child(bar())
      .child(this.machinesList(t));
  }

  // ---- status line -----------------------------------------------------

  // The previously shown tab of each space, for tmux's `-` mark.
  trackLast(s) {
    const tab = s.tabs.find((c) => c.active);
    if (!tab) return null;
    const rec = this.last[s.id] ?? { cur: null, prev: null };
    if (rec.cur !== tab.id) {
      this.last[s.id] = { cur: tab.id, prev: rec.cur };
      try { localStorage.setItem("tty.last", JSON.stringify(this.last)); } catch {}
    }
    return this.last[s.id].prev;
  }

  tabList(t, s) {
    if (!s) return div();
    const prev = this.trackLast(s);
    return h_flex().id("tty-tabs").flex_none().gap(16).px(12).items_center()
      .on_scroll_wheel((e) => {
        const dy = e.delta_lines?.y ?? e.delta.y;
        if (dy > 0) run("tab.prev"); else if (dy < 0) run("tab.next");
      })
      .children(s.tabs.filter((c) => !c.settled).map((c) => {
        const mark = c.active ? "*" : c.id === prev ? "-" : "";
        const color = c.active ? t.accent : c.id === prev ? t.dim : t.muted;
        const alert = !c.active && (c.status === "blocked" || c.status === "done") ? c.status : null;
        return h_flex().id(`tty-tab-${c.id}`).cursor_pointer().items_center()
          .on_click(() => run("tab.select", { id: c.id }))
          .child(div().text_color(color).when(c.active, (el) => el.font_bold()).child(`${c.index}:${c.name}${mark}`))
          .when(Boolean(alert), (el) => el.child(div().text_color(t[alert]).child(` ${SHAPE[alert]}`)));
      }));
  }

  modeBlock(t) {
    const [name, color] = mode(t);
    return h_flex().id("tty-mode").h_full().flex_none().px(12).items_center().cursor_pointer()
      .bg(color).font_bold().text_color(t.accent_foreground)
      .on_click(() => run("tty.goto"))
      .child(name);
  }

  renderStatus(t, zen) {
    const sp = spaces();
    const s = sp.find((s) => s.active);
    const root = h_flex().size_full().bg(t.chrome).text_size(12.5).items_center().child(this.modeBlock(t));
    if (zen) {
      return root
        .child(h_flex().h_full().flex_none().items_center().children(sp.map((w) =>
          h_flex().id(`tty-zen-space-${w.id}`).h_full().px(12).gap(6).items_center().cursor_pointer()
            .when(w.active, (el) => el.bg(t.accent).font_bold().text_color(t.accent_foreground))
            .when(!w.active, (el) => el.bg(t.chrome).text_color(t.muted))
            .on_click(() => run("space.select", { id: w.id }))
            .child(w.name)
            .child(glyph(t, w.status)))))
        .child(div().id("tty-zen-new").flex_none().px(10).cursor_pointer().text_color(t.dim)
          .on_click(() => openOverlay({ mod: "new-menu", kind: "popup", width: 250, height: 512 }))
          .child("+"))
        .child(div().flex_1())
        .child(this.tabList(t, s))
        .child(h_flex().h_full().flex_none().px(12).items_center().bg(t.hover).text_color(t.muted).child(clock(false)));
    }
    const fp = focusedPane();
    const inTab = fp ? panes().filter((p) => p.tab === fp.tab) : [];
    const at = fp ? inTab.findIndex((p) => p.pane === fp.pane) + 1 : 0;
    return root
      .when(Boolean(s), (el) => el.child(h_flex().h_full().flex_none().px(12).items_center().bg(t.hover).font_bold().text_color(t.foreground).child(s.name)))
      .child(this.tabList(t, s))
      .child(div().flex_1())
      .child(h_flex().flex_none().px(12).child(counts(t, agents(), 12)))
      .when(at > 0, (el) => el.child(h_flex().h_full().flex_none().px(10).items_center().bg(t.hover).text_color(t.muted).child(`pane ${at}/${inTab.length}`)))
      .child(h_flex().h_full().flex_none().px(12).items_center().bg(t.accent).font_bold().text_color(t.accent_foreground).child(clock(true)));
  }

  // Move the shown tab one place left or right, wrapping at the ends.
  // tab.move wants an id and a position, so a key can't say "left" alone.
  moveTab(by) {
    const s = spaces().find((s) => s.active);
    if (!s || s.tabs.length < 2) return;
    const i = s.tabs.findIndex((c) => c.active);
    if (i < 0) return;
    const to = (i + by + s.tabs.length) % s.tabs.length;
    run("tab.move", { id: s.tabs[i].id, index: to + 1 });
  }

  // ---- go to / inbox ---------------------------------------------------

  // Opens the dialog, or closes it when one is open. tty-goto builds and draws
  // it (role "open" swaps this carrier for the real dialog) and records its
  // overlay in shared("tty.goto").
  toggleGoto(source) {
    const open = shared("tty.goto");
    if (open) { setShared("tty.goto", null); closeOverlay(open); return; }
    openOverlay({ mod: "tty-goto", kind: "popup", width: 1, height: 1, props: { role: "open", source } });
  }

  // ---- pane header -----------------------------------------------------

  renderHeader(t) {
    const p = panes().find((x) => x.pane === props()?.pane);
    if (!p) return div();
    const rule = props()?.variant === "rule";
    const inTab = panes().filter((x) => x.tab === p.tab);
    const index = inTab.findIndex((x) => x.pane === p.pane) + 1;
    const label = programLabel(p);
    const folder = tilde(p.cwd);
    // A shell titled after its folder says nothing new.
    const title = p.program?.shell && p.cwd && (p.title.includes(base(p.cwd)) || p.title.includes(folder)) ? "" : p.title;
    const since = p.status === "working" ? workingSince(p.tab) : null;
    const status = p.status === "working" ? [`${SPIN[0]} working${since ? ` · ${minutes(since)}` : ""}`, t.working]
      : p.status === "blocked" ? ["◉ needs you", t.blocked]
      : p.status === "done" ? ["● done", t.done]
      : p.status === "idle" ? ["○ idle", t.dim] : null;
    const chip = div().flex_none().px(6)
      .when(rule, (el) => el.px(0).when(p.focused, (c) => c.font_bold().text_color(t.accent)).when(!p.focused, (c) => c.text_color(t.muted)))
      .when(!rule && p.focused, (el) => el.bg(t.accent).font_bold().text_color(t.accent_foreground))
      .when(!rule && !p.focused, (el) => el.bg(t.hover).text_color(t.muted))
      .child(String(index));
    return h_flex().id(`tty-head-${p.pane}`).size_full().gap(8).items_center().bg(t.background).text_size(12)
      .pl(rule ? 14 : 0).pr(rule ? 14 : 8)
      .on_mouse_down("left", (e) => { if (e.click_count === 2) run("pane.zoom", { pane: p.pane }); else run("pane.focus", { pane: p.pane }); })
      .child(h_flex().h_full().items_center().child(chip))
      .child(div().flex_none().font_bold().text_color(t.foreground).child(label))
      .when(Boolean(title), (el) => el.child(div().flex_shrink(1).min_w(0).max_w(280).truncate().text_color(t.muted).child(title)))
      .when(Boolean(folder), (el) => el.child(div().flex_shrink(1).min_w(0).max_w(260).truncate().text_color(t.dim).child(folder)))
      .child(div().flex_1().min_w(16).h(1).bg(p.focused ? t.accent : t.border))
      .when(Boolean(status), (el) => el.child(div().flex_none().text_color(status[1])
        .when(p.status === "working", (d) => d.child(h_flex().child(div().frames(SPIN, 90).child(SPIN[0])).child(status[0].slice(1))))
        .when(p.status !== "working", (d) => d.child(status[0]))))
      .when(p.zoomed, (el) => el.child(div().flex_none().text_color(t.ansi5).child("[zoom]")));
  }

  render() {
    const t = theme();
    const zen = props()?.variant === "zen";
    switch (this.role) {
      case "topline": return this.renderTopline(t, zen);
      case "spaces": return this.renderSpaces(t);
      case "agents": return this.renderAgents(t);
      case "keys": return this.renderKeys(t);
      case "statusline": return this.renderStatus(t, zen);
      default: return this.renderHeader(t);
    }
  }
}
