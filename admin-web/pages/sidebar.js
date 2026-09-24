/* =====================================================
   InaAgapay Admin Web — Sidebar

   Lets the navigation collapse to an icon rail on desktop, so the tables that
   fill this portal — the stock matrix, the audit trail, the account list — get
   the 184px back.

   WHY IT LIVES HERE RATHER THAN IN EACH PAGE
   ------------------------------------------
   Thirteen pages carry the same <aside>, and portal-scope.js injects a
   fourteenth nav item into it at runtime. Anything written per page would have
   to be written thirteen times and would still miss the injected one.

   WHY THE LABELS ARE WRAPPED IN JS
   --------------------------------
   The markup is `<a href="..."><i class="..."></i> Dashboard</a>` — the label
   is a bare text node. CSS cannot hide a text node, so there is no selector
   that leaves the icon and removes the word. Rather than hand-edit fourteen
   sidebars, each label is wrapped in a <span class="nav-label"> on load. That
   also gives the tooltip something to read.

   WHY THE TOOLTIP IS APPENDED TO document.body
   --------------------------------------------
   .app-sidebar is `overflow-y: auto`, which makes it a scroll container: a
   tooltip drawn as a child would be clipped at the rail's edge no matter what
   z-index it carried. One fixed-position element outside the sidebar avoids
   that, and one element serves every item.

   The header button keeps its old job below 993px, where the sidebar is an
   overlay drawer and collapsing would save nothing.
   ===================================================== */

(function () {
  "use strict";

  const STORAGE_KEY = "inaagapay_sidebar_collapsed";
  const DESKTOP = "(min-width: 993px)";
  const TIP_DELAY_MS = 90;

  const layout = document.querySelector(".app-layout");
  const sidebar = document.querySelector(".app-sidebar");
  if (!layout || !sidebar) return;

  const desktop = () => window.matchMedia(DESKTOP).matches;

  /* ── Stored state ──────────────────────────────────────────────────── */

  function readStored() {
    try {
      return localStorage.getItem(STORAGE_KEY) === "1";
    } catch (e) {
      // Private browsing, or storage disabled. Expanded is the safe default:
      // a reader who cannot persist a preference should not be handed a rail
      // of unlabelled icons on every page.
      return false;
    }
  }

  function writeStored(collapsed) {
    try {
      localStorage.setItem(STORAGE_KEY, collapsed ? "1" : "0");
    } catch (e) { /* nothing to do, and nothing worth saying */ }
  }

  /* ── Labels ────────────────────────────────────────────────────────────
     Wraps the bare text beside each icon. Runs again after portal-scope.js
     injects the Facility Management item, and is written to be idempotent so
     re-running it costs nothing.
  */

  function wrapLabels() {
    const items = sidebar.querySelectorAll(".sidebar-nav a, .sidebar-logout");

    items.forEach((el) => {
      if (el.querySelector(".nav-label")) return;

      // Only the loose text nodes move; the icon and any counter badge stay
      // where they are, which is what keeps the badge positionable.
      const loose = [];
      el.childNodes.forEach((node) => {
        if (node.nodeType === Node.TEXT_NODE && node.textContent.trim() !== "") {
          loose.push(node);
        }
      });
      if (loose.length === 0) return;

      const text = loose.map((n) => n.textContent).join(" ").replace(/\s+/g, " ").trim();
      const span = document.createElement("span");
      span.className = "nav-label";
      span.textContent = text;

      loose[0].parentNode.replaceChild(span, loose[0]);
      loose.slice(1).forEach((n) => n.remove());

      el.dataset.navLabel = text;
    });
  }

  /* ── Tooltip ───────────────────────────────────────────────────────── */

  let tip = null;
  let tipTimer = null;

  function tipElement() {
    if (tip) return tip;
    tip = document.createElement("div");
    tip.className = "sidebar-tip";
    tip.setAttribute("role", "tooltip");
    tip.setAttribute("aria-hidden", "true");
    document.body.appendChild(tip);
    return tip;
  }

  function showTip(target) {
    if (!layout.classList.contains("sidebar-collapsed") || !desktop()) return;
    const label = target.dataset.navLabel;
    if (!label) return;

    const el = tipElement();

    // A count that has been reduced to a dot on the rail is still readable
    // here, which is the whole reason the dot is acceptable.
    const badge = target.querySelector(".nav-counter-badge");
    const count = badge && badge.style.display !== "none" ? badge.textContent.trim() : "";
    el.textContent = label;
    if (count) {
      const chip = document.createElement("span");
      chip.className = "sidebar-tip-count";
      chip.textContent = count;
      el.appendChild(chip);
    }

    const rect = target.getBoundingClientRect();
    el.style.left = rect.right + 12 + "px";

    // Centred by arithmetic rather than by translateY(-50%). An inline
    // transform here would win over the stylesheet's, which is what draws the
    // slide-in — so the tooltip would appear centred but never animate, and
    // any later change to the animation would silently do nothing.
    el.style.top = "0px";
    const height = el.offsetHeight;
    let top = rect.top + rect.height / 2 - height / 2;

    // Clamped so a tooltip beside the last item on a short viewport still sits
    // on screen.
    top = Math.max(8, Math.min(top, window.innerHeight - height - 8));
    el.style.top = top + "px";

    // The element is created and positioned in the same frame, so without a
    // forced style read the browser has no "before" to animate from and the
    // tooltip simply appears.
    void el.offsetWidth;

    el.classList.add("is-visible");
    el.setAttribute("aria-hidden", "false");
  }

  function hideTip() {
    window.clearTimeout(tipTimer);
    if (!tip) return;
    tip.classList.remove("is-visible");
    tip.setAttribute("aria-hidden", "true");
  }

  function bindTips() {
    sidebar.addEventListener("mouseover", (e) => {
      const target = e.target.closest(".sidebar-nav a, .sidebar-logout");
      if (!target) return;
      window.clearTimeout(tipTimer);
      tipTimer = window.setTimeout(() => showTip(target), TIP_DELAY_MS);
    });

    sidebar.addEventListener("mouseout", (e) => {
      if (e.target.closest(".sidebar-nav a, .sidebar-logout")) hideTip();
    });

    // Keyboard users tab through the rail and need the same labels.
    sidebar.addEventListener("focusin", (e) => {
      const target = e.target.closest(".sidebar-nav a, .sidebar-logout");
      if (target) showTip(target);
    });
    sidebar.addEventListener("focusout", hideTip);

    window.addEventListener("scroll", hideTip, { passive: true });
    sidebar.addEventListener("scroll", hideTip, { passive: true });
    window.addEventListener("resize", hideTip);
  }

  /* ── Collapse ──────────────────────────────────────────────────────── */

  function toggleButton() {
    return document.getElementById("sidebar-toggle");
  }

  function syncToggleButton() {
    const btn = toggleButton();
    if (!btn) return;
    const collapsed = layout.classList.contains("sidebar-collapsed");

    if (!desktop()) {
      // Drawer duty. The icon means "open the menu" and the state it reports
      // is whether the drawer is showing, not whether the rail is collapsed.
      btn.setAttribute("aria-label", "Open navigation menu");
      btn.setAttribute("aria-expanded", String(sidebar.classList.contains("open")));
      btn.title = "";
      const icon = btn.querySelector("i");
      if (icon) icon.className = "fa-solid fa-bars";
      return;
    }

    btn.setAttribute("aria-controls", sidebar.id || "app-sidebar");
    btn.setAttribute("aria-expanded", String(!collapsed));
    btn.setAttribute("aria-label", collapsed ? "Expand navigation" : "Collapse navigation");
    btn.title = (collapsed ? "Expand navigation" : "Collapse navigation") + "  [";

    const icon = btn.querySelector("i");
    if (icon) {
      // Chevrons point the way the panel will move, which reads more clearly
      // than a hamburger that never changes.
      icon.className = collapsed
        ? "fa-solid fa-angles-right"
        : "fa-solid fa-angles-left";
    }
  }

  function setCollapsed(collapsed, opts) {
    layout.classList.toggle("sidebar-collapsed", collapsed);
    if (!opts || opts.persist !== false) writeStored(collapsed);
    if (collapsed) hideTip();
    syncToggleButton();

    notifyLayoutChanged();
  }

  /**
   * Tell the page its content column just changed width.
   *
   * Chart.js writes an explicit pixel width onto each canvas and re-measures
   * from its own ResizeObserver, not from window resize — so without this the
   * charts on Dashboard and Reports keep the width they were drawn at and
   * overflow their cards once the column narrows again. Asking each instance
   * to resize is four lines here against a listener on every page that draws
   * a chart.
   *
   * The window resize event stays for everything else that measures itself,
   * and the custom event gives any page a cleaner hook than guessing.
   */
  function notifyLayoutChanged() {
    window.requestAnimationFrame(() => {
      window.dispatchEvent(new Event("resize"));
      document.dispatchEvent(new CustomEvent("inaagapay:layout-changed", {
        detail: { sidebarCollapsed: layout.classList.contains("sidebar-collapsed") },
      }));

      if (!window.Chart) return;
      try {
        // Chart.js 3 and 4 both expose the live registry here.
        const registry = window.Chart.instances || {};
        Object.keys(registry).forEach((key) => {
          const chart = registry[key];
          if (chart && typeof chart.resize === "function") chart.resize();
        });
      } catch (e) {
        console.warn("Could not resize charts after sidebar toggle:", e);
      }
    });
  }

  function toggle() {
    if (!desktop()) return;
    setCollapsed(!layout.classList.contains("sidebar-collapsed"));
  }

  /* ── Wiring ────────────────────────────────────────────────────────── */

  if (!sidebar.id) sidebar.id = "app-sidebar";

  wrapLabels();

  // portal-scope.js adds the Facility Management item after this file runs on
  // some pages and before it on others, so the new item is caught whenever it
  // arrives rather than depending on which won the race.
  if (typeof MutationObserver === "function") {
    const observer = new MutationObserver(() => wrapLabels());
    observer.observe(sidebar, { childList: true, subtree: true });
  }

  // The width change is not animated (see the note in main.css), so restoring
  // the stored state is simply setting it.
  setCollapsed(readStored() && desktop(), { persist: false });

  const btn = toggleButton();
  if (btn) {
    btn.addEventListener("click", () => {
      // Below 993px the page's own handler opens the drawer; this stays out of
      // the way and only updates what the button reports to a screen reader.
      if (desktop()) toggle();
      else window.setTimeout(syncToggleButton, 0);
    });
  }

  // The shortcut every editor uses for the same thing.
  document.addEventListener("keydown", (e) => {
    if (e.key !== "[" || e.metaKey || e.ctrlKey || e.altKey) return;
    const el = document.activeElement;
    if (el && (el.isContentEditable ||
               /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName))) return;
    e.preventDefault();
    toggle();
  });

  // Crossing the breakpoint changes what "collapsed" means. Coming up into
  // desktop restores the stored preference; going down drops the class so the
  // drawer is full width when it opens.
  const query = window.matchMedia(DESKTOP);
  const onBreakpoint = () => {
    hideTip();
    setCollapsed(desktop() && readStored(), { persist: false });
  };
  if (typeof query.addEventListener === "function") {
    query.addEventListener("change", onBreakpoint);
  } else if (typeof query.addListener === "function") {
    query.addListener(onBreakpoint);
  }

  bindTips();

  window.AdminSidebar = {
    toggle,
    collapse: () => setCollapsed(true),
    expand: () => setCollapsed(false),
    get collapsed() { return layout.classList.contains("sidebar-collapsed"); },
    refreshLabels: wrapLabels,
  };
})();
