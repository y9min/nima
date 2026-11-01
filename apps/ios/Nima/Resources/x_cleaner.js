(function () {
  "use strict";

  try {
    if (window.top !== window) return;
  } catch (_) {
    return;
  }
  if (window.__nimaXInstalled) return;
  window.__nimaXInstalled = true;

  const documentToken = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  const send = (payload) => {
    try {
      window.webkit.messageHandlers.nimaX.postMessage(
        Object.assign({ documentToken, url: location.href }, payload)
      );
    } catch (_) {}
  };

  const textOf = (node) =>
    (node?.innerText || node?.textContent || "").replace(/\s+/g, " ").trim().toLowerCase();
  const pathOf = (value) => {
    try {
      return new URL(value || location.href, location.origin).pathname.toLowerCase().replace(/\/+$/, "") || "/";
    } catch (_) {
      return "/";
    }
  };
  const visible = (node) => {
    if (!node || !node.getBoundingClientRect) return false;
    const rect = node.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  };
  const isAuthPath = (path) =>
    path.startsWith("/i/flow/login")
    || path.startsWith("/i/flow/signup")
    || path.startsWith("/i/flow/consent")
    || path.startsWith("/i/jf/onboarding")
    || path.startsWith("/i/jf/web")
    || path.startsWith("/i/oauth2")
    || path.startsWith("/oauth/")
    || path.startsWith("/account/")
    || path.startsWith("/login")
    || path.includes("challenge")
    || path.includes("captcha");
  const exactText = (label) =>
    [...document.querySelectorAll("a, button, [role='tab'], [role='link'], [role='button']")]
      .find((node) => visible(node) && textOf(node) === label.toLowerCase());

  let lastLocation = "";
  let lastHealth = "";
  let lastHealthSentAt = 0;
  let checkingFollowing = false;
  let messagesReadyReported = false;
  let config = {
    mode: "clean",
    grantedPostURL: null,
    grantedProfileURL: null,
  };

  const style = document.createElement("style");
  style.id = "nima-x-cleaner";
  style.textContent = `
    a[href="/explore"],
    a[href^="/explore/"],
    a[href="/i/trending"],
    a[href^="/i/trending/"],
    a[href="/i/explore"],
    a[href^="/i/explore/"],
    a[href="/following"],
    a[href^="/following/"],
    [data-pinned-timeline="for-you"],
    a[href="/i/flow/login"] [data-testid="app-download"],
    [data-nima-x-hidden="true"] {
      display: none !important;
    }
    html[data-nima-x-mode="dm_only"] [data-nima-x-dm-hide="true"] {
      display: none !important;
    }
  `;
  (document.head || document.documentElement).appendChild(style);

  const hide = (node) => {
    if (!node) return;
    node.setAttribute("data-nima-x-hidden", "true");
  };

  const hideDiscovery = () => {
    for (const node of document.querySelectorAll("a, button, [role='tab'], [role='link']")) {
      const label = textOf(node);
      const href = pathOf(node.getAttribute("href") || "");
      if (
        label === "explore"
        || label === "for you"
        || label === "trending"
        || href === "/explore"
        || href.startsWith("/explore/")
        || href.startsWith("/i/trending")
        || href.startsWith("/i/explore")
      ) {
        hide(node);
      }
    }

    for (const heading of document.querySelectorAll("h1, h2, h3, span, div")) {
      const label = textOf(heading);
      if (
        label === "trends for you"
        || label === "what's happening"
        || label === "what’s happening"
        || label === "who to follow"
      ) {
        const surface = heading.closest("aside, section, [data-testid='sidebarColumn']");
        if (surface) {
          surface.setAttribute("data-nima-x-dm-hide", "true");
          hide(surface);
        }
      }
    }
  };

  const selected = (node) =>
    node?.getAttribute("aria-selected") === "true"
    || node?.getAttribute("aria-current") === "page"
    || node?.getAttribute("data-state") === "active"
    || node?.closest("[aria-selected='true'], [aria-current='page']");

  const findHomeTab = (label) => {
    const pinnedValue = label === "Following" ? "following" : "for-you";
    const pinned = document.querySelector(`[data-pinned-timeline="${pinnedValue}"]`);
    if (pinned && visible(pinned)) return pinned;
    return [...document.querySelectorAll("[role='tab'], button, a")].find((node) => {
      if (!visible(node) || textOf(node) !== label.toLowerCase()) return false;
      const href = pathOf(node.getAttribute("href") || "");
      if (href === "/following" || href.startsWith("/following/")) return false;
      return node.closest("[role='tablist']") !== null;
    }) || null;
  };

  const reportHealth = (value, observation) => {
    const now = Date.now();
    if (lastHealth === value && now - lastHealthSentAt < 1500) return;
    lastHealth = value;
    lastHealthSentAt = now;
    send(Object.assign({ event: "filterHealth", status: value }, observation));
  };

  const enforceFollowing = () => {
    const path = pathOf();
    if (isAuthPath(path)) {
      checkingFollowing = false;
      return;
    }
    if (path !== "/" && path !== "/home") {
      return;
    }

    const following = findHomeTab("Following");
    const forYou = findHomeTab("For you");
    const homeSurface = document.querySelector(
      "main, [role='main'], [data-testid='primaryColumn']"
    );
    const timelineTabs = document.querySelector("[role='tablist']");
    const bodyText = (document.body?.innerText || "").slice(0, 12000);
    const loading = Boolean(
      document.querySelector("[role='progressbar'], [aria-busy='true']")
    );
    const loadError = Boolean(
      document.querySelector("[data-testid='error-detail']")
    ) || /something went wrong|try reloading|too many requests|rate limit/i.test(bodyText);
    const observation = {
      path,
      documentReady: document.readyState !== "loading",
      homeSurfacePresent: Boolean(homeSurface),
      timelineTabsPresent: Boolean(timelineTabs),
      followingPresent: Boolean(following),
      followingSelected: Boolean(following && selected(following)),
      forYouPresent: Boolean(forYou),
      loading,
      loadError,
    };

    if (!following) {
      checkingFollowing = false;
      reportHealth("checking", observation);
      return;
    }

    if (selected(following)) {
      reportHealth("healthy", observation);
      checkingFollowing = false;
      return;
    }

    reportHealth("checking", observation);
    if (forYou && selected(forYou)) {
      following.click();
    } else if (!checkingFollowing) {
      following.click();
    }
    if (!checkingFollowing) {
      checkingFollowing = true;
      setTimeout(() => {
        checkingFollowing = false;
        enforceFollowing();
      }, 450);
    }
  };

  const reportLocation = () => {
    const current = location.href;
    if (current === lastLocation) return;
    lastLocation = current;
    if (!pathOf().startsWith("/i/chat")) messagesReadyReported = false;
    send({ event: "locationChanged", url: current });
  };

  const reportMessagesReadyIfPossible = () => {
    const path = pathOf();
    if (!path.startsWith("/i/chat")) return;
    if (messagesReadyReported) return;
    const surface = document.querySelector("main, [role='main']");
    if (!surface) return;
    const interactive = surface.querySelector(
      "button, input, textarea, [contenteditable='true'], [role='button']"
    );
    if (!interactive) return;
    messagesReadyReported = true;
    send({ event: "messagesReady", url: location.href });
  };

  const enforce = () => {
    document.documentElement.setAttribute("data-nima-x-mode", config.mode);
    reportLocation();
    const path = pathOf();
    if (path === "/" || path === "/home") {
      hideDiscovery();
      enforceFollowing();
    } else {
      reportMessagesReadyIfPossible();
    }
  };

  let enforceScheduled = false;
  const scheduleEnforce = () => {
    if (enforceScheduled) return;
    enforceScheduled = true;
    requestAnimationFrame(() => {
      enforceScheduled = false;
      enforce();
    });
  };

  const observer = new MutationObserver(() => {
    const path = pathOf();
    if (path === "/" || path === "/home") {
      scheduleEnforce();
    } else if (path.startsWith("/i/chat")) {
      reportMessagesReadyIfPossible();
    }
  });
  observer.observe(document.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["aria-selected", "aria-current", "href"],
  });
  setInterval(enforce, 1000);

  window.addEventListener("popstate", enforce);
  window.addEventListener("hashchange", enforce);
  window.addEventListener("error", (event) => {
    if (!event.message || window !== window.top) return;
    send({
      event: "pageError",
      message: String(event.message),
      source: event.filename || "",
    });
  }, true);
  window.addEventListener("unhandledrejection", (event) => {
    if (window !== window.top) return;
    const reason = event.reason;
    send({
      event: "pageError",
      message: reason?.message || String(reason || "Unhandled promise rejection"),
    });
  });

  document.addEventListener("click", (event) => {
    const anchor = event.target?.closest?.("a[href]");
    if (!anchor) return;
    const href = anchor.href;
    if (!href) return;
    setTimeout(() => {
      reportLocation();
      send({ event: "clickedLink", url: href });
    }, 0);
  }, true);

  window.__nimaXConfigure = (next) => {
    config = Object.assign({}, config, next || {});
    enforce();
    return true;
  };

  window.__nimaXOpenNativeSurface = (surface) => {
    if (surface === "following") {
      const following = findHomeTab("Following");
      if (!following) return false;
      following.click();
      setTimeout(enforceFollowing, 120);
      return true;
    }
    const labels = {
      search: ["search", "explore"],
      notifications: ["notifications"],
      messages: ["messages"],
      profile: ["profile"],
    }[surface] || [surface];
    const target = labels
      .map(exactText)
      .find(Boolean)
      || (surface === "profile"
        ? document.querySelector("[data-testid='AppTabBar_Profile_Link']")
        : null);
    if (!target) return false;
    target.click();
    if (surface === "following") {
      setTimeout(enforceFollowing, 120);
    }
    return true;
  };

  window.__nimaXHealthPing = () => {
    enforce();
    return lastHealth === "healthy";
  };

  window.__nimaXHomeHealth = () => {
    enforce();
    return lastHealth === "healthy";
  };

  reportLocation();
  enforce();
})();
