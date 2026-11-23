// BasedOS's web docs: the status line ("Reading: N %", as setup shows how far it has got), the
// menu's "> " on the section being read, J/K between sections and T to the top, and the home
// page's boot screen going through the boot's own messages.
(() => {
  const root = document.documentElement;
  const read = document.querySelector(".status .read b");
  const heads = [...document.querySelectorAll("main h2[id]")];
  const items = new Map([...document.querySelectorAll(".menu a")]
    .map(a => [decodeURIComponent(a.getAttribute("href").slice(1)), a.parentElement]));
  let current = null;
  // On a phone the menu starts closed (it'd push the text a screen down).
  const menu = document.querySelector(".menu details");
  if (menu && matchMedia("(max-width: 820px)").matches) menu.open = false;

  function update() {
    const max = root.scrollHeight - root.clientHeight;
    if (read) read.textContent = max > 0 ? Math.min(100, Math.round(root.scrollTop * 100 / max)) : 100;
    let cur = null;
    for (const h of heads) {
      if (h.getBoundingClientRect().top < innerHeight * 0.3) cur = h; else break;
    }
    if (cur !== current) {
      if (current && items.get(current.id)) items.get(current.id).classList.remove("on");
      if (cur && items.get(cur.id)) items.get(cur.id).classList.add("on");
      current = cur;
    }
  }
  addEventListener("scroll", update, { passive: true });
  addEventListener("resize", update);
  update();

  addEventListener("keydown", e => {
    if (e.metaKey || e.ctrlKey || e.altKey || e.target.closest("input, textarea, select, [contenteditable]")) return;
    const k = e.key.toLowerCase();
    if (k === "t") { scrollTo({ top: 0 }); return; }
    if ((k !== "j" && k !== "k") || !heads.length) return;
    const tops = heads.map(h => h.getBoundingClientRect().top);
    const next = k === "j" ? tops.findIndex(t => t > 40) : tops.map(t => t < 16).lastIndexOf(true);
    if (next >= 0) heads[next].scrollIntoView();
    else if (k === "k") scrollTo({ top: 0 });
  });

  // The home page's screen: the messages a boot shows, in turn.
  const status = document.querySelector(".g-status[data-cycle]");
  if (status && !matchMedia("(prefers-reduced-motion: reduce)").matches) {
    const lines = status.dataset.cycle.split("|");
    let i = 0;
    setInterval(() => { i = (i + 1) % lines.length; status.textContent = lines[i]; }, 1600);
  }
})();
