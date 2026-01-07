(function() {
  // Luna loader v4 - minimal dispatcher
  const d = document;
  const S = {};
  const loaded = new Set();

  // Clean up OAuth fragment (e.g., #_=_ from Fitbit/Facebook)
  if (window.location.hash === '#_=_') {
    history.replaceState(null, '', window.location.pathname + window.location.search);
  }

  const parseState = async (el) => {
    const a = el.getAttribute("luna:state");
    if (!a) return;
    if (a[0] === "#") return JSON.parse(d.getElementById(a.slice(1))?.textContent ?? "null");
    try {
      return JSON.parse(a);
    } catch {}
  };

  const setupTrigger = (el, trigger, hydrate) => {
    if (trigger === "load") {
      document.readyState === "loading"
        ? document.addEventListener("DOMContentLoaded", () => hydrate(), { once: true })
        : hydrate();
    } else if (trigger === "idle") {
      requestIdleCallback(() => hydrate());
    } else if (trigger[0] === "v") {
      new IntersectionObserver((entries, obs) => {
        if (entries.some((e) => e.isIntersecting)) {
          obs.disconnect();
          hydrate();
        }
      }, { rootMargin: "50px" }).observe(el);
    } else if (trigger[0] === "m") {
      const mq = matchMedia(trigger.slice(6));
      const handler = () => {
        if (mq.matches) {
          mq.removeEventListener("change", handler);
          hydrate();
        }
      };
      mq.matches ? hydrate() : mq.addEventListener("change", handler);
    }
  };

  const hydrate = async (el) => {
    const id = el.getAttribute("luna:id") ?? el.tagName.toLowerCase();
    if (loaded.has(id)) return;
    loaded.add(id);
    S[id] = await parseState(el);
    const url = el.getAttribute("luna:url");
    if (!url) return;
    try {
      const mod = await import(url);
      const ex = el.getAttribute("luna:export");
      (ex ? mod[ex] : mod.hydrate ?? mod.default)?.(el, S[id], id);
    } catch (e) {
      console.warn(`[luna] Failed to load ${url}:`, e);
    }
  };

  const setup = (el) => {
    setupTrigger(el, el.getAttribute("luna:trigger") ?? "load", () => hydrate(el));
  };

  const scan = () => {
    d.querySelectorAll("[luna\\:url]").forEach(setup);
  };

  // Parse inline state scripts
  d.querySelectorAll("script[type=\"luna/json\"]").forEach((s) => {
    if (s.id) S[s.id] = JSON.parse(s.textContent ?? "{}");
  });

  // Watch for dynamically added elements
  const observeAdditions = (match, setupFn) => {
    new MutationObserver((mutations) => mutations.forEach((m) => m.addedNodes.forEach((n) => {
      if (n.nodeType === 1 && match(n)) setupFn(n);
    }))).observe(document.body ?? document.documentElement, {
      childList: true,
      subtree: true
    });
  };

  // Initialize
  const onReady = (fn) => {
    document.readyState === "loading"
      ? document.addEventListener("DOMContentLoaded", fn, { once: true })
      : fn();
  };

  onReady(scan);
  observeAdditions((el) => el.hasAttribute("luna:url"), setup);

  // Expose globals
  const w = window;
  w.__LUNA_STATE__ = S;
  w.__LUNA_HYDRATE__ = hydrate;
  w.__LUNA_SCAN__ = scan;
  w.__LUNA_UNLOAD__ = (id) => loaded.delete(id);
  w.__LUNA_CLEAR_LOADED__ = () => loaded.clear();
})();
