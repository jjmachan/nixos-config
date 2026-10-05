#!/usr/bin/env python3
"""KOReader highlight ingest: .sdr sidecars -> SQLite -> Markdown.

Scans a synced shelf for KOReader sidecar files (<Book>.sdr/metadata.<ext>.lua),
parses the annotations out of the Lua table, mirrors them into SQLite, and
renders one Markdown note per book into the output directory.

Stdlib only. Sidecars are pure `return { ... }` Lua literals, so a small
recursive-descent parser is enough — no Lua runtime, nothing is executed.

Formats handled:
  * unified `annotations` array (KOReader >= v2024.05) — preferred
  * legacy `highlight` + `bookmarks` tables — backfill for books not opened
    since the migration. When both exist, only `annotations` is read (the
    migration copies rather than moves, so reading both would duplicate).

Idempotency / change handling:
  * sidecars are skipped when (mtime, size) matches the last ingest
  * a book's highlights are fully replaced on each parse (edits + deletions
    on the device propagate); books whose sidecar disappears keep their rows
    (removing a book from the device shouldn't erase its notes)
  * markdown files are rewritten only when their bytes actually change
  * output is a pure function of the database — no wall-clock stamps
"""

import argparse
import hashlib
import re
import sqlite3
import sys
from pathlib import Path

# --------------------------------------------------------------------------
# Minimal Lua table-literal parser (SLPP-style)
# --------------------------------------------------------------------------


class LuaParseError(Exception):
    pass


class LuaParser:
    """Parses the `return { ... }` literal DocSettings serializes."""

    def __init__(self, text):
        self.s = text
        self.i = 0
        self.n = len(text)

    def parse(self):
        self._ws()
        if self.s.startswith("return", self.i):
            self.i += len("return")
        self._ws()
        val = self._value()
        self._ws()
        return val

    def _err(self, msg):
        line = self.s.count("\n", 0, self.i) + 1
        raise LuaParseError(f"{msg} at line {line}")

    def _ws(self):
        while self.i < self.n:
            c = self.s[self.i]
            if c in " \t\r\n":
                self.i += 1
            elif self.s.startswith("--", self.i):
                # long comment --[[ ... ]] or line comment
                if self.s.startswith("--[[", self.i):
                    end = self.s.find("]]", self.i + 4)
                    if end == -1:
                        self._err("unterminated long comment")
                    self.i = end + 2
                else:
                    nl = self.s.find("\n", self.i)
                    self.i = self.n if nl == -1 else nl + 1
            else:
                return

    def _value(self):
        self._ws()
        if self.i >= self.n:
            self._err("unexpected end of input")
        c = self.s[self.i]
        if c == "{":
            return self._table()
        if c in "\"'":
            return self._string(c)
        if c == "[" and self.s.startswith(("[[", "[="), self.i):
            return self._long_string()
        for word, val in (("true", True), ("false", False), ("nil", None)):
            if self.s.startswith(word, self.i):
                self.i += len(word)
                return val
        return self._number()

    def _string(self, quote):
        self.i += 1  # opening quote
        out = bytearray()  # \ddd escapes are raw bytes (often UTF-8 sequences)
        while self.i < self.n:
            c = self.s[self.i]
            if c == quote:
                self.i += 1
                return out.decode("utf-8", errors="replace")
            if c == "\\":
                self.i += 1
                e = self.s[self.i]
                mapped = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b",
                          "f": "\f", "v": "\v", "\\": "\\", '"': '"', "'": "'",
                          "\n": "\n"}
                if e in mapped:
                    out += mapped[e].encode()
                    self.i += 1
                elif e.isdigit():  # \ddd decimal escape (up to 3 digits)
                    j = self.i
                    while j < self.i + 3 and j < self.n and self.s[j].isdigit():
                        j += 1
                    out.append(int(self.s[self.i:j]) & 0xFF)
                    self.i = j
                else:
                    self._err(f"unknown escape \\{e}")
            else:
                out += c.encode("utf-8")
                self.i += 1
        self._err("unterminated string")

    def _long_string(self):
        m = re.match(r"\[(=*)\[", self.s[self.i:])
        if not m:
            self._err("malformed long string")
        close = "]" + m.group(1) + "]"
        start = self.i + m.end()
        end = self.s.find(close, start)
        if end == -1:
            self._err("unterminated long string")
        self.i = end + len(close)
        body = self.s[start:end]
        return body[1:] if body.startswith("\n") else body

    def _number(self):
        m = re.match(r"-?(0[xX][0-9a-fA-F]+|\d+\.?\d*([eE][+-]?\d+)?|\.\d+)",
                     self.s[self.i:])
        if not m:
            self._err(f"unexpected character {self.s[self.i]!r}")
        tok = m.group(0)
        self.i += len(tok)
        if tok.lower().startswith(("0x", "-0x")):
            return int(tok, 16)
        return float(tok) if any(c in tok for c in ".eE") else int(tok)

    def _table(self):
        self.i += 1  # {
        d = {}
        arr_index = 1
        while True:
            self._ws()
            if self.i >= self.n:
                self._err("unterminated table")
            c = self.s[self.i]
            if c == "}":
                self.i += 1
                break
            if c == "[":
                if self.s.startswith(("[[", "[="), self.i):
                    key = arr_index  # long string as array value
                    arr_index += 1
                    val = self._long_string()
                else:
                    self.i += 1
                    key = self._value()
                    self._ws()
                    if self.s[self.i] != "]":
                        self._err("expected ]")
                    self.i += 1
                    self._ws()
                    if self.s[self.i] != "=":
                        self._err("expected =")
                    self.i += 1
                    val = self._value()
            else:
                m = re.match(r"[A-Za-z_]\w*", self.s[self.i:])
                save = self.i
                if m:
                    self.i += m.end()
                    self._ws()
                    if self.i < self.n and self.s[self.i] == "=" and not \
                            self.s.startswith("==", self.i):
                        self.i += 1
                        key = m.group(0)
                        val = self._value()
                    else:  # bare word value (true/false/nil already handled)
                        self.i = save
                        key = arr_index
                        arr_index += 1
                        val = self._value()
                else:
                    key = arr_index
                    arr_index += 1
                    val = self._value()
            d[key] = val
            self._ws()
            if self.i < self.n and self.s[self.i] in ",;":
                self.i += 1
        return self._listify(d)

    @staticmethod
    def _listify(d):
        """A table whose keys are exactly 1..n becomes a Python list."""
        if d and all(isinstance(k, int) for k in d) and \
                sorted(d) == list(range(1, len(d) + 1)):
            return [d[k] for k in sorted(d)]
        return d


def parse_lua_file(path):
    return LuaParser(path.read_text(encoding="utf-8", errors="replace")).parse()


# --------------------------------------------------------------------------
# Sidecar -> normalized highlights
# --------------------------------------------------------------------------

# Legacy bookmarks auto-generate their `text` as "Page N <snippet> @ <datetime>";
# anything else in that field is a user-written note.
_AUTOGEN_NOTE = re.compile(r"^Page \d+ .* @ \d{4}-\d{2}-\d{2}", re.DOTALL)


def _as_list(v):
    if isinstance(v, list):
        return v
    if isinstance(v, dict):
        return list(v.values())
    return []


def extract(sidecar):
    """Returns (book_meta, [highlight dicts]) from a parsed sidecar table."""
    if not isinstance(sidecar, dict):
        raise LuaParseError("sidecar root is not a table")

    props = sidecar.get("doc_props") or {}
    meta = {
        "title": (props.get("title") or "").strip(),
        "authors": (props.get("authors") or "").strip(),
        "md5": sidecar.get("partial_md5_checksum") or "",
    }

    entries = []
    annotations = sidecar.get("annotations")
    if annotations is not None:
        for ord_, a in enumerate(_as_list(annotations)):
            if not isinstance(a, dict):
                continue
            text = (a.get("text") or "").strip()
            # entries without pos0 are dogear bookmarks, not highlights
            if not text or a.get("pos0") is None:
                continue
            page = a.get("pageno", a.get("page"))
            entries.append({
                "datetime": a.get("datetime") or "",
                "ord": ord_,
                "page": page if isinstance(page, (int, float)) else None,
                "chapter": (a.get("chapter") or "").strip(),
                "text": text,
                "note": (a.get("note") or "").strip(),
                "color": a.get("color") or "",
                "drawer": a.get("drawer") or "",
            })
        return meta, entries

    # Legacy: highlight[pageno] = [ {datetime,text,pos0,...}, ... ] with user
    # notes living in the parallel bookmarks table, matched by datetime.
    notes_by_dt = {}
    chapter_by_dt = {}
    for b in _as_list(sidecar.get("bookmarks")):
        if not isinstance(b, dict) or not b.get("datetime"):
            continue
        chapter_by_dt[b["datetime"]] = (b.get("chapter") or "").strip()
        note = (b.get("text") or "").strip()
        if note and not _AUTOGEN_NOTE.match(note):
            notes_by_dt[b["datetime"]] = note

    entries = []
    highlight = sidecar.get("highlight")
    pages = highlight.items() if isinstance(highlight, dict) else \
        enumerate(highlight or [], start=1)
    for pageno, page_entries in sorted(pages, key=lambda kv: str(kv[0])):
        for h in _as_list(page_entries):
            if not isinstance(h, dict):
                continue
            text = (h.get("text") or "").strip()
            if not text:
                continue
            dt = h.get("datetime") or ""
            entries.append({
                "datetime": dt,
                "ord": None,
                "page": pageno if isinstance(pageno, (int, float)) else None,
                "chapter": (h.get("chapter") or "").strip() or
                           chapter_by_dt.get(dt, ""),
                "text": text,
                "note": notes_by_dt.get(dt, ""),
                "color": "",
                "drawer": h.get("drawer") or "",
            })
    entries.sort(key=lambda e: (e["page"] or 0, e["datetime"]))
    for ord_, e in enumerate(entries):
        e["ord"] = ord_
    return meta, entries


# --------------------------------------------------------------------------
# SQLite mirror
# --------------------------------------------------------------------------

SCHEMA = """
CREATE TABLE IF NOT EXISTS books(
  id      INTEGER PRIMARY KEY,
  key     TEXT UNIQUE NOT NULL,   -- partial_md5_checksum, else sdr path
  title   TEXT NOT NULL,
  authors TEXT NOT NULL,
  sdr_path TEXT NOT NULL,
  md5     TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS highlights(
  id       INTEGER PRIMARY KEY,
  book_id  INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  datetime TEXT NOT NULL,
  ord      INTEGER NOT NULL,
  page     INTEGER,
  chapter  TEXT NOT NULL DEFAULT '',
  text     TEXT NOT NULL,
  note     TEXT NOT NULL DEFAULT '',
  color    TEXT NOT NULL DEFAULT '',
  drawer   TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS files(  -- seen-markers for unchanged-sidecar skip
  path  TEXT PRIMARY KEY,
  mtime REAL NOT NULL,
  size  INTEGER NOT NULL
);
"""


def ingest_sidecar(con, lua_path, shelf):
    rel = str(lua_path.relative_to(shelf))
    st = lua_path.stat()
    row = con.execute("SELECT mtime, size FROM files WHERE path=?",
                      (rel,)).fetchone()
    if row and tuple(row) == (st.st_mtime, st.st_size):
        return False  # unchanged since last ingest

    meta, entries = extract(parse_lua_file(lua_path))
    sdr_rel = str(lua_path.parent.relative_to(shelf))
    title = meta["title"] or lua_path.parent.name.removesuffix(".sdr")
    key = meta["md5"] or sdr_rel

    cur = con.execute(
        """INSERT INTO books(key, title, authors, sdr_path, md5)
           VALUES(?,?,?,?,?)
           ON CONFLICT(key) DO UPDATE SET
             title=excluded.title, authors=excluded.authors,
             sdr_path=excluded.sdr_path, md5=excluded.md5
           RETURNING id""",
        (key, title, meta["authors"], sdr_rel, meta["md5"]))
    book_id = cur.fetchone()[0]

    # Full replace per book: device-side edits and deletions both propagate.
    con.execute("DELETE FROM highlights WHERE book_id=?", (book_id,))
    con.executemany(
        """INSERT INTO highlights
             (book_id, datetime, ord, page, chapter, text, note, color, drawer)
           VALUES(?,?,?,?,?,?,?,?,?)""",
        [(book_id, e["datetime"], e["ord"], e["page"], e["chapter"],
          e["text"], e["note"], e["color"], e["drawer"]) for e in entries])
    con.execute(
        "INSERT OR REPLACE INTO files(path, mtime, size) VALUES(?,?,?)",
        (rel, st.st_mtime, st.st_size))
    return True


# --------------------------------------------------------------------------
# Markdown rendering
# --------------------------------------------------------------------------


def _yaml_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _sanitize_filename(name):
    name = re.sub(r'[/\\:*?"<>|\x00-\x1f]', " ", name)
    name = re.sub(r"\s+", " ", name).strip().strip(".")
    return name[:120] or "Untitled"


def render_book(book, highlights):
    title, authors = book["title"], book["authors"]
    author_list = [a.strip() for a in re.split(r"[\n;]", authors) if a.strip()]
    last = max((h["datetime"] for h in highlights if h["datetime"]), default="")

    lines = ["---"]
    lines.append(f"title: {_yaml_str(title)}")
    if author_list:
        lines.append("authors:")
        lines += [f"  - {_yaml_str(a)}" for a in author_list]
    lines.append(f"highlights: {len(highlights)}")
    if last:
        lines.append(f"last_highlight: {_yaml_str(last)}")
    lines.append("tags: [kobo-highlights]")
    lines.append("---")
    lines.append("")
    lines.append(f"# {title}")
    if author_list:
        lines.append("")
        lines.append("*" + ", ".join(author_list) + "*")

    chapter = object()  # sentinel != any real value
    for h in sorted(highlights, key=lambda h: (h["ord"], h["datetime"])):
        if h["chapter"] != chapter:
            chapter = h["chapter"]
            lines.append("")
            lines.append(f"## {chapter or 'Highlights'}")
        lines.append("")
        for text_line in h["text"].splitlines() or [""]:
            lines.append(f"> {text_line}".rstrip())
        if h["note"]:
            lines.append(">")
            note_lines = h["note"].splitlines() or [""]
            lines.append(f"> **Note:** {note_lines[0]}".rstrip())
            lines += [f"> {l}".rstrip() for l in note_lines[1:]]
        meta_bits = []
        if h["page"] is not None:
            meta_bits.append(f"p. {int(h['page'])}")
        if h["datetime"]:
            meta_bits.append(h["datetime"])
        if meta_bits:
            lines.append("")
            lines.append("— *" + " · ".join(meta_bits) + "*")
    lines.append("")
    return "\n".join(lines)


def render_all(con, out_dir):
    books = [dict(r) for r in con.execute(
        "SELECT * FROM books ORDER BY title, id")]
    # Stable filenames; disambiguate title collisions with a short key hash.
    names = {}
    for b in books:
        base = b["title"] + (" - " + b["authors"].splitlines()[0]
                             if b["authors"] else "")
        names.setdefault(_sanitize_filename(base), []).append(b)

    written = 0
    for base, group in names.items():
        for b in group:
            highlights = [dict(r) for r in con.execute(
                "SELECT * FROM highlights WHERE book_id=? ORDER BY ord, datetime",
                (b["id"],))]
            if not highlights:
                continue
            name = base if len(group) == 1 else \
                f"{base} ({hashlib.md5(b['key'].encode()).hexdigest()[:6]})"
            path = out_dir / f"{name}.md"
            content = render_book(b, highlights).encode()
            if not path.exists() or path.read_bytes() != content:
                path.write_bytes(content)
                written += 1
    return written


# --------------------------------------------------------------------------


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--shelf", required=True, type=Path,
                    help="synced Kobo shelf (contains books + .sdr sidecars)")
    ap.add_argument("--db", required=True, type=Path,
                    help="SQLite database path")
    ap.add_argument("--out", required=True, type=Path,
                    help="Markdown output directory")
    args = ap.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(args.db)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys=ON")
    con.executescript(SCHEMA)

    sidecars = sorted(args.shelf.rglob("*.sdr/metadata.*.lua"))
    parsed = errors = 0
    for lua_path in sidecars:
        try:
            with con:
                if ingest_sidecar(con, lua_path, args.shelf):
                    parsed += 1
        except (LuaParseError, OSError, UnicodeError) as e:
            errors += 1
            print(f"ERROR {lua_path}: {e}", file=sys.stderr)

    written = render_all(con, args.out)
    con.close()
    print(f"sidecars: {len(sidecars)} scanned, {parsed} (re)parsed, "
          f"{errors} errors; markdown: {written} written")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
