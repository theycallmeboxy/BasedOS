#!/usr/bin/env python3
"""BasedOS's web docs: site/ from the user-facing docs, in BasedOS's own look.

  python tools/site/build.py        (standard library only; writes site/)

The pages are the docs themselves (docs/user-guide.md, recovery.md, spruce-on-gkd.md), so the site
never says something the docs don't; the home page is tools/site/home.html. The look is the boot
screen's (tools/boot-ui/basedos-splash.c): its black, its green wordmark and block cursor, amber
headings, its rule, and its font. That font is Terminus Font (bold 16x32), the bitmap the boot
screen draws from (tools/boot-ui/font.h): turned here into a TrueType font of square pixels,
"BasedOS Boot". Terminus is under the SIL Open Font License with "Terminus Font" as a Reserved
Font Name, so the derived font has its own name and ships with the licence (fonts/OFL.txt).
"""
import html
import os
import re
import shutil
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(REPO, "site")
GITHUB = "https://github.com/theycallmeboxy/BasedOS"
RELEASES = GITHUB + "/releases"

# (source, page, label in the page keys, description)
PAGES = [
    ("docs/user-guide.md", "guide.html", "Guide",
     "Setting up BasedOS on the GKD 350H Ultra, using it day to day, and getting back to stock."),
    ("docs/recovery.md", "recovery.html", "Recovery",
     "The recovery card, USB disk mode and maskrom: putting the 350H Ultra's built-in storage back."),
    ("docs/spruce-on-gkd.md", "spruce.html", "spruce",
     "What spruce does on the GKD 350H Ultra under BasedOS."),
]
PAGE_OF = {os.path.basename(src): page for src, page, _l, _d in PAGES}

# The boot screen's colours (basedos-splash.c).
GREEN, DIM_GREEN = "#39ff7a", "#1f7f3a"


# --- The font -------------------------------------------------------------------------------

def read_glyphs():
    """font.h's 96 glyphs (printable ASCII, then U+2588), each 32 rows of 16 pixels."""
    src = open(os.path.join(REPO, "tools/boot-ui/font.h"), encoding="utf-8").read()
    body = src[src.index("font_glyphs"):]
    glyphs = []
    for block in re.findall(r"\{([0-9a-fx,\s]+)\}", body):
        b = [int(v, 16) for v in block.replace("\n", "").split(",") if v.strip()]
        if len(b) == 64:
            glyphs.append([(b[2 * r] << 8) | b[2 * r + 1] for r in range(32)])
    assert len(glyphs) == 96, len(glyphs)
    return glyphs


def rects(rows, width=16):
    """A glyph's pixels as rectangles (x0, row0, x1, row1), runs merged down the rows."""
    done, open_ = [], {}
    for r, bits in enumerate(rows + [0]):
        runs, x = set(), 0
        while x < width:
            if bits & (1 << (width - 1 - x)):
                x0 = x
                while x < width and bits & (1 << (width - 1 - x)):
                    x += 1
                runs.add((x0, x))
            else:
                x += 1
        for run in list(open_):
            if run not in runs:
                done.append((run[0], open_.pop(run), run[1], r))
        for run in runs:
            open_.setdefault(run, r)
    return done


def checksum(data):
    data += b"\0" * (-len(data) % 4)
    return sum(struct.unpack(">%dI" % (len(data) // 4), data)) & 0xFFFFFFFF


def make_font(glyphs):
    """A TrueType font of the glyphs: 32 units a pixel, 1024 to the em (so crisp at 32 px)."""
    U, EM = 32, 1024
    h_rows = glyphs[ord("H") - 0x20]
    base = max(r for r in range(32) if h_rows[r]) + 1          # the row under the capitals
    ascent, descent = base * U, (32 - base) * U
    order = [None] + list(range(96))                          # .notdef, then font.h's
    glyf, loca, hmtx = b"", [], b""
    max_pts = max_cont = 0
    bbox = [0, 0, 0, 0]
    for gi in order:
        loca.append(len(glyf))
        rs = rects(glyphs[gi]) if gi is not None else []
        if not rs:
            hmtx += struct.pack(">Hh", 16 * U, 0)
            continue
        pts, ends = [], []
        for x0, r0, x1, r1 in rs:
            X0, X1, YT, YB = x0 * U, x1 * U, (base - r0) * U, (base - r1) * U
            pts += [(X0, YB), (X0, YT), (X1, YT), (X1, YB)]     # clockwise: an outer contour
            ends.append(len(pts) - 1)
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        xmin, ymin, xmax, ymax = min(xs), min(ys), max(xs), max(ys)
        bbox = [min(bbox[0], xmin), min(bbox[1], ymin), max(bbox[2], xmax), max(bbox[3], ymax)]
        g = struct.pack(">hhhhh", len(ends), xmin, ymin, xmax, ymax)
        g += struct.pack(">%dH" % len(ends), *ends) + struct.pack(">H", 0)
        g += bytes([1] * len(pts))                            # every point on the curve
        px = py = 0
        for x, _y in pts:
            g += struct.pack(">h", x - px); px = x
        for _x, y in pts:
            g += struct.pack(">h", y - py); py = y
        g += b"\0" * (-len(g) % 4)
        glyf += g
        hmtx += struct.pack(">Hh", 16 * U, xmin)
        max_pts, max_cont = max(max_pts, len(pts)), max(max_cont, len(ends))
    loca.append(len(glyf))
    n = len(order)

    head = struct.pack(">IIIIHHqqhhhhHHhhh", 0x00010000, 0x00010000, 0, 0x5F0F3CF5, 0x000B, EM,
                       0, 0, bbox[0], bbox[1], bbox[2], bbox[3], 0, 8, 2, 1, 0)
    hhea = struct.pack(">IhhhHhhhhhhhhhhhH", 0x00010000, ascent, -descent, 0, 16 * U, 0, 0,
                       bbox[2], 1, 0, 0, 0, 0, 0, 0, 0, n)
    maxp = struct.pack(">IHHHHHHHHHHHHHH", 0x00010000, n, max_pts, max_cont, 0, 0, 2, 0, 0, 0,
                       0, 0, 0, 0, 0)
    panose = bytes([2, 0, 0, 9, 0, 0, 0, 0, 0, 0])            # text, monospaced
    os2 = struct.pack(">HhHHHhhhhhhhhhhh", 4, 16 * U, 400, 5, 0, 10 * U, 12 * U, 0, 2 * U,
                      10 * U, 12 * U, 0, 10 * U, 2 * U, 8 * U, 0)
    os2 += panose + struct.pack(">IIII", 1, 0, 0, 0) + b"NONE"
    os2 += struct.pack(">HHHhhhHHIIhhHHH", 0x0040, 0x20, 0x2588, ascent, -descent, 0, ascent,
                       descent, 1, 0, 14 * U, 20 * U, 0, 0x20, 0)
    # cmap: format 4, printable ASCII and the full block.
    segs = [(0x20, 0x7E, 1 - 0x20), (0x2588, 0x2588, 96 - 0x2588), (0xFFFF, 0xFFFF, 1)]
    sc = len(segs)
    sr = 2 * 2 ** (sc.bit_length() - 1)
    sub = struct.pack(">HHHH", sc * 2, sr, sr.bit_length() - 2, sc * 2 - sr)
    sub += struct.pack(">%dH" % sc, *[e for _s, e, _d in segs]) + struct.pack(">H", 0)
    sub += struct.pack(">%dH" % sc, *[s for s, _e, _d in segs])
    sub += struct.pack(">%dh" % sc, *[d if d < 0x8000 else d - 0x10000 for _s, _e, d in segs])
    sub += struct.pack(">%dH" % sc, *[0] * sc)
    sub = struct.pack(">HHH", 4, 6 + len(sub), 0) + sub
    cmap = struct.pack(">HHHHIHHI", 0, 2, 0, 3, 20, 3, 1, 20) + sub
    names = {
        0: "Copyright (c) 2010 Dimitar Toshkov Zhekov (Terminus Font). BasedOS Boot: Terminus "
           "Font's bold 16x32 as square pixels, for BasedOS.",
        1: "BasedOS Boot", 2: "Regular", 3: "BasedOS Boot 1.0", 4: "BasedOS Boot",
        5: "Version 1.0", 6: "BasedOSBoot-Regular",
        13: "This Font Software is licensed under the SIL Open Font License, Version 1.1.",
        14: "https://openfontlicense.org",
    }
    recs, strs = b"", b""
    for nid in sorted(names):
        s = names[nid].encode("utf-16-be")
        recs += struct.pack(">HHHHHH", 3, 1, 0x409, nid, len(s), len(strs))
        strs += s
    name = struct.pack(">HHH", 0, len(names), 6 + len(recs)) + recs + strs
    post = struct.pack(">IIhhIIIII", 0x00030000, 0, -2 * U, 2 * U, 1, 0, 0, 0, 0)
    tables = {
        "OS/2": os2, "cmap": cmap, "glyf": glyf, "head": head, "hhea": hhea, "hmtx": hmtx,
        "loca": struct.pack(">%dI" % len(loca), *loca), "maxp": maxp, "name": name, "post": post,
    }
    tags = sorted(tables)
    nt = len(tags)
    sr = 16 * 2 ** (nt.bit_length() - 1)
    font = struct.pack(">IHHHH", 0x00010000, nt, sr, nt.bit_length() - 1, nt * 16 - sr)
    off = 12 + 16 * nt
    body = b""
    for t in tags:
        d = tables[t]
        font += struct.pack(">4sIII", t.encode(), checksum(d), off + len(body), len(d))
        body += d + b"\0" * (-len(d) % 4)
    font += body
    adj = (0xB1B0AFBA - checksum(font)) & 0xFFFFFFFF
    hpos = off + sum(len(tables[t]) + (-len(tables[t]) % 4) for t in tags[:tags.index("head")])
    return font[:hpos + 8] + struct.pack(">I", adj) + font[hpos + 12:]


def wordmark_svg(glyphs, label="BasedOS"):
    """The boot screen's wordmark, as basedos-splash.c draws it: "> BasedOS" (the chevron in the
    dimmer green) and the block cursor, one rect per run of pixels."""
    parts = []

    def text(cell, s, cls):
        for i, ch in enumerate(s):
            for x0, r0, x1, r1 in rects(glyphs[ord(ch) - 0x20]):
                parts.append('<rect class="%s" x="%d" y="%d" width="%d" height="%d"/>'
                             % (cls, (cell + i) * 16 + x0, r0, x1 - x0, r1 - r0))
    text(0, ">", "c")
    text(2, "BasedOS", "w")
    parts.append('<rect class="k" x="%d" y="4" width="14" height="26"/>' % (9 * 16 + 1))
    return ('<svg class="wordmark" viewBox="0 0 160 32" role="img" aria-label="%s">'
            '<title>%s</title>%s</svg>' % (label, label, "".join(parts)))


# --- Markdown (what the docs use) -----------------------------------------------------------

def slug(text, seen):
    s = re.sub(r"[^a-z0-9]+", "-", re.sub(r"<[^>]+>", "", text).lower()).strip("-") or "section"
    base, i = s, 2
    while s in seen:
        s = "%s-%d" % (base, i)
        i += 1
    seen.add(s)
    return s


def link_target(url):
    if re.match(r"^[a-z]+:", url) or url.startswith("#"):
        return url
    path, _, frag = url.partition("#")
    page = PAGE_OF.get(os.path.basename(path))
    if page:
        return page + ("#" + frag if frag else "")
    path = os.path.normpath(os.path.join("docs", path)).replace(os.sep, "/")
    kind = "tree" if path.endswith("/") or "." not in os.path.basename(path) else "blob"
    return "%s/%s/main/%s%s" % (GITHUB, kind, path, "#" + frag if frag else "")


def inline(text):
    """Code spans, links, bold, and bare doc names (x.md) as links; everything else escaped."""
    keep = []

    def stash(s):
        keep.append(s)
        return "\x00%d\x00" % (len(keep) - 1)

    text = re.sub(r"`([^`]+)`", lambda m: stash("<code>%s</code>" % html.escape(m.group(1))), text)
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)",
                  lambda m: stash('<a href="%s">%s</a>' % (html.escape(link_target(m.group(2))),
                                                          inline(m.group(1)))), text)
    text = re.sub(r"https?://[^\s)<>,]+[^\s)<>,.]",
                  lambda m: stash('<a href="%s">%s</a>' % (html.escape(m.group(0)), html.escape(m.group(0)))), text)
    text = re.sub(r"\b([a-z0-9][a-z0-9-]*\.md)\b",
                  lambda m: stash('<a href="%s">%s</a>' % (html.escape(link_target(m.group(1))), m.group(1))), text)
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    while "\x00" in text:
        text = re.sub(r"\x00(\d+)\x00", lambda m: keep[int(m.group(1))], text)
    return text


def table(rows):
    cells = [[c.strip() for c in r.strip().strip("|").split("|")] for r in rows]
    head, body = cells[0], cells[2:]
    out = ['<div class="table"><table><thead><tr>']
    out += ["<th>%s</th>" % inline(c) for c in head]
    out.append("</tr></thead><tbody>")
    for r in body:
        out.append("<tr>" + "".join("<td>%s</td>" % inline(c) for c in r) + "</tr>")
    out.append("</tbody></table></div>")
    return "".join(out)


def blocks(lines, toc, seen):
    """Markdown lines to HTML: headings, paragraphs, lists, tables, code, quotes."""
    out, i = [], 0
    indent = lambda s: len(s) - len(s.lstrip(" "))
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        if line.startswith("```"):
            j = i + 1
            while j < len(lines) and not lines[j].startswith("```"):
                j += 1
            out.append('<pre><code>%s</code></pre>' % html.escape("\n".join(lines[i + 1:j])))
            i = j + 1
            continue
        if indent(line) >= 4:
            j = i
            while j < len(lines) and (indent(lines[j]) >= 4 or not lines[j].strip()):
                j += 1
            code = "\n".join(l[4:] for l in lines[i:j]).rstrip("\n")
            out.append('<pre><code>%s</code></pre>' % html.escape(code))
            i = j
            continue
        m = re.match(r"^(#{1,4})\s+(.*)$", line)
        if m:
            lvl, text = len(m.group(1)), inline(m.group(2))
            hid = slug(text, seen)
            if lvl in (2, 3):
                toc.append((lvl, hid, re.sub(r"<[^>]+>", "", text)))
            out.append('<h%d id="%s"><a class="anchor" href="#%s" aria-hidden="true" tabindex="-1">#</a>%s</h%d>'
                       % (lvl, hid, hid, text, lvl))
            i += 1
            continue
        if line.lstrip().startswith("|") and i + 1 < len(lines) and re.match(r"^\s*\|[\s:|-]+\|\s*$", lines[i + 1]):
            j = i
            while j < len(lines) and lines[j].lstrip().startswith("|"):
                j += 1
            out.append(table(lines[i:j]))
            i = j
            continue
        if line.startswith(">"):
            j = i
            while j < len(lines) and lines[j].startswith(">"):
                j += 1
            inner = [l[1:].lstrip() if l.startswith("> ") or l == ">" else l[1:] for l in lines[i:j]]
            out.append('<aside class="note"><span class="bang" aria-hidden="true">!</span><div>%s</div></aside>'
                       % blocks(inner, [], seen))
            i = j
            continue
        m = re.match(r"^(\s*)([-*]|\d+\.)\s+", line)
        if m:
            base = len(m.group(1))
            ordered = m.group(2)[0].isdigit()
            items, j = [], i
            while j < len(lines):
                l = lines[j]
                mm = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)$", l)
                if mm and len(mm.group(1)) == base and (mm.group(2)[0].isdigit()) == ordered:
                    items.append([mm.group(3)])
                elif l.strip() and indent(l) > base and items:
                    items[-1].append(l[base + 2:] if indent(l) >= base + 2 else l.strip())
                elif not l.strip() and j + 1 < len(lines) and items and indent(lines[j + 1]) > base:
                    items[-1].append("")
                else:
                    break
                j += 1
            tag = "ol" if ordered else "ul"
            html_items = []
            for it in items:
                if len(it) == 1 or not any(re.match(r"^\s*([-*]|\d+\.)\s+", x) or not x.strip() for x in it[1:]):
                    html_items.append("<li>%s</li>" % inline(" ".join(x.strip() for x in it)))
                else:
                    # A paragraph, then whatever is nested under it.
                    k = 1
                    while k < len(it) and it[k].strip() and not re.match(r"^\s*([-*]|\d+\.)\s+", it[k]):
                        k += 1
                    html_items.append("<li>%s%s</li>" % (inline(" ".join(x.strip() for x in it[:k])),
                                                        blocks(it[k:], [], seen)))
            out.append("<%s>%s</%s>" % (tag, "".join(html_items), tag))
            i = j
            continue
        j = i
        while j < len(lines) and lines[j].strip() and not re.match(r"^(#{1,4}\s|```|>|\s*\|)", lines[j]) \
                and not (j > i and re.match(r"^\s*([-*]|\d+\.)\s+", lines[j])):
            j += 1
        out.append("<p>%s</p>" % inline(" ".join(l.strip() for l in lines[i:j])))
        i = j
    return "".join(out)


# --- Pages ----------------------------------------------------------------------------------

def page(template, mark, title, desc, current, main, toc):
    keys = []
    for _src, pg, label, _d in [("", "index.html", "Home", "")] + PAGES:
        cur = ' aria-current="page"' if pg == current else ""
        keys.append('<a href="%s"%s><span class="label">%s</span><span class="btn" aria-hidden="true"></span></a>'
                    % (pg, cur, label))
    keys.append('<a href="%s"><span class="label">GitHub</span><span class="btn" aria-hidden="true"></span></a>' % GITHUB)
    menu = ""
    if toc:
        entries = "".join('<li class="l%d"><a href="#%s">%s</a></li>' % (lvl, hid, html.escape(text))
                          for lvl, hid, text in toc)
        menu = ('<nav class="menu" aria-label="On this page"><details open><summary>On this page</summary>'
                '<ol>%s</ol></details></nav>' % entries)
    # The page's own parts first: the home page uses {{wordmark}} too.
    return (template.replace("{{menu}}", menu)
            .replace("{{main}}", main)
            .replace("{{title}}", html.escape(title))
            .replace("{{description}}", html.escape(desc))
            .replace("{{wordmark}}", mark)
            .replace("{{keys}}", "".join(keys))
            .replace("{{kind}}", "home" if current == "index.html" else "doc"))


def main():
    glyphs = read_glyphs()
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(os.path.join(OUT, "fonts"))
    open(os.path.join(OUT, "fonts", "BasedOS-Boot.ttf"), "wb").write(make_font(glyphs))
    shutil.copy(os.path.join(REPO, "tools/boot-ui/OFL-Terminus.txt"), os.path.join(OUT, "fonts", "OFL.txt"))
    for f in ("basedos.css", "basedos.js"):
        shutil.copy(os.path.join(HERE, f), os.path.join(OUT, f))
    open(os.path.join(OUT, ".nojekyll"), "w").close()
    mark = wordmark_svg(glyphs)
    open(os.path.join(OUT, "favicon.svg"), "w", encoding="utf-8", newline="\n").write(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><rect width="32" height="32" fill="#000"/>'
        '<rect x="9" y="4" width="14" height="24" fill="%s"/></svg>' % GREEN)
    template = open(os.path.join(HERE, "template.html"), encoding="utf-8").read()

    home = open(os.path.join(HERE, "home.html"), encoding="utf-8").read().replace("{{releases}}", RELEASES)
    open(os.path.join(OUT, "index.html"), "w", encoding="utf-8", newline="\n").write(
        page(template, mark, "BasedOS for the GKD 350H Ultra",
             "A small base OS on the GKD 350H Ultra's built-in storage that boots spruce from your SD card in about 4 seconds.",
             "index.html", home, []))
    for src, pg, label, desc in PAGES:
        lines = open(os.path.join(REPO, src), encoding="utf-8").read().splitlines()
        toc, seen = [], set()
        title = re.sub(r"^#\s+", "", lines[0]) if lines and lines[0].startswith("# ") else label
        body = blocks(lines, toc, seen)
        body += ('<p class="source">This page is <a href="%s/blob/main/%s">%s</a> in the repository.</p>'
                 % (GITHUB, src, src))
        open(os.path.join(OUT, pg), "w", encoding="utf-8", newline="\n").write(
            page(template, mark, title, desc, pg, body, [t for t in toc if t[0] == 2]))
    print("site/: index.html " + " ".join(p for _s, p, _l, _d in PAGES))


if __name__ == "__main__":
    main()
