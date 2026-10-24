(function () {
  if (window.__nimaCleanerInstalled) return;
  window.__nimaCleanerInstalled = true;
  window.__nimaMode = window.__nimaMode || "clean";
  window.__nimaSharedURL = window.__nimaSharedURL || null;
  window.__nimaSharedReelOpen = window.__nimaSharedReelOpen || false;
  let lastHealthKey = "";
  let lastSessionStatus = "";
  let authenticatedSessionChecks = 0;
  let lastBlockedLocation = "";
  let lastActivatedSearchLocation = "";
  let pendingSearchBlur = null;
  let bottomNavigation = null;
  let cleanQueued = false;
  let reelTouchStart = null;
  const reelPointerStarts = new Map();
  const reelSwipeThreshold = 12;

  const bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nimaInstagram;
  const send = (payload) => {
    try { bridge && bridge.postMessage(payload); } catch (_) {}
  };

  const pathOf = (value) => {
    try { return new URL(value, location.href).pathname.toLowerCase(); }
    catch (_) { return ""; }
  };

  const isReelsFeed = (href) => {
    const path = pathOf(href).replace(/\/$/, "");
    return path === "/reels" || path.startsWith("/reels/");
  };

  const isIndividualReel = (href) => pathOf(href).startsWith("/reel/");
  const reservedProfileSections = new Set([
    "about", "accounts", "api", "challenge", "developer", "direct", "emails",
    "explore", "legal", "oauth", "p", "privacy", "reel", "reels", "stories",
    "terms", "web"
  ]);
  const pathParts = (value) => pathOf(value).split("/").filter(Boolean);
  const isProfilePage = (value) => {
    const parts = pathParts(value);
    return parts.length > 0 && !reservedProfileSections.has(parts[0]);
  };
  const isAccountResult = (value) => {
    const parts = pathParts(value);
    return parts.length === 1 && !reservedProfileSections.has(parts[0]);
  };
  const isExploreSearchURL = (value) => {
    const path = pathOf(value).replace(/\/$/, "");
    return path === "/explore" || path.startsWith("/explore/search");
  };
  const isExploreSearch = () => isExploreSearchURL(location.href);
  const isExploreMediaDestination = (value) => {
    const path = pathOf(value);
    return path.startsWith("/p/")
      || path.startsWith("/reel/")
      || path.startsWith("/reels/")
      || path.startsWith("/tv/")
      || path.startsWith("/explore/search/keyword/")
      || path.startsWith("/explore/tags/")
      || path.startsWith("/explore/locations/");
  };
  const isDirect = () => location.pathname.toLowerCase().startsWith("/direct");
  const isDirectInbox = () => pathOf(location.href).replace(/\/$/, "") === "/direct/inbox";
  const isSharedReelOpen = () => window.__nimaSharedReelOpen
    || isIndividualReel(window.__nimaSharedURL || "");
  const shouldLockReelNavigation = () => isIndividualReel(location.href) || isSharedReelOpen();

  const visible = (node) => {
    if (!node || !node.getBoundingClientRect) return false;
    const rect = node.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0
      && rect.bottom > 0 && rect.top < innerHeight;
  };

  const isAuthenticationLocation = () => {
    const path = pathOf(location.href).replace(/\/$/, "");
    return path.startsWith("/accounts/login")
      || path.startsWith("/accounts/signup")
      || path.startsWith("/challenge")
      || path.startsWith("/two_factor")
      || path.startsWith("/login")
      || path.startsWith("/oauth")
      || path.startsWith("/dialog/oauth")
      || path === "/instagram/login_sync"
      || path.includes("checkpoint")
      || path.includes("accountscenter");
  };

  const hasVisibleLoginForm = () => Array.from(
    document.querySelectorAll("input[type='password'], form[action*='login']")
  ).some(visible);

  const hasAuthenticatedNavigation = () => {
    const visibleLinks = Array.from(document.querySelectorAll("a[href]")).filter(visible);
    const visibleLabels = Array.from(document.querySelectorAll("[aria-label]"))
      .filter(visible)
      .map((node) => (node.getAttribute("aria-label") || "").trim().toLowerCase());
    const hasDirect = visibleLinks.some((link) => pathOf(link.href).startsWith("/direct"))
      || visibleLabels.some((label) => label === "messages" || label === "messenger" || label === "direct");
    const hasHome = visibleLinks.some((link) => pathOf(link.href).replace(/\/$/, "") === "")
      || visibleLabels.includes("home");
    const hasAccountSurface = visibleLinks.some((link) => {
      const path = pathOf(link.href);
      return path.startsWith("/accounts/activity") || isProfilePage(link.href);
    }) || visibleLabels.includes("profile");
    return hasDirect && (hasHome || hasAccountSurface);
  };

  const reportSessionStatus = () => {
    if (window.top !== window) return;
    let status = "unknown";
    if (isAuthenticationLocation() || hasVisibleLoginForm()) {
      status = "signing_in";
    } else if (hasAuthenticatedNavigation()) {
      status = "authenticated";
    }
    if (status === "authenticated") {
      authenticatedSessionChecks += 1;
      if (authenticatedSessionChecks < 2) {
        setTimeout(reportSessionStatus, 200);
        return;
      }
    } else {
      authenticatedSessionChecks = 0;
    }
    if (status === lastSessionStatus) return;
    lastSessionStatus = status;
    send({ event: "sessionState", status });
  };

  const reelURLNear = (node) => {
    if (!node || !node.closest) return null;
    const directAnchor = node.closest("a[href]");
    if (directAnchor && isIndividualReel(directAnchor.href)) return directAnchor.href;
    let container = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
    for (let depth = 0; container && depth < 10; depth += 1) {
      const reelAnchor = container.querySelector && container.querySelector("a[href*='/reel/']");
      if (reelAnchor && isIndividualReel(reelAnchor.href)) return reelAnchor.href;
      if (container.matches && (container.matches("article") || container.matches("[role='dialog']"))) break;
      container = container.parentElement;
    }
    return null;
  };

  const detectOpenedSharedReel = () => {
    if (window.__nimaMode !== "dm_only" || !isDirect() || isSharedReelOpen()) return;
    const largeVisibleVideo = Array.from(document.querySelectorAll("video")).find((video) => {
      if (!visible(video)) return false;
      const rect = video.getBoundingClientRect();
      return rect.width >= Math.min(240, innerWidth * 0.6)
        && rect.height >= Math.min(360, innerHeight * 0.45);
    });
    if (!largeVisibleVideo) return;

    const reelURL = reelURLNear(largeVisibleVideo)
      || Array.from(document.querySelectorAll("a[href*='/reel/']"))
        .find((anchor) => visible(anchor))?.href
      || null;
    const surface = largeVisibleVideo.closest("[role='dialog']")
      || largeVisibleVideo.closest("main")
      || largeVisibleVideo.parentElement;
    const hasReelActions = surface && Array.from(surface.querySelectorAll("button, [role='button'], a"))
      .some((control) => /like|comment|share|send/.test(
        ((control.getAttribute("aria-label") || control.textContent || "")).toLowerCase()
      ));
    if (!reelURL && !hasReelActions) return;

    window.__nimaSharedReelOpen = true;
    send({ event: "sharedReelOpened", url: reelURL });
    clean();
  };

  const activeReelSurface = () => {
    const video = Array.from(document.querySelectorAll("video")).find((candidate) => {
      if (!visible(candidate)) return false;
      const rect = candidate.getBoundingClientRect();
      const centerY = rect.top + rect.height / 2;
      return centerY >= 0 && centerY <= innerHeight;
    });
    return video && (video.closest("[role='dialog']") || video.closest("article") || video.parentElement);
  };

  const updateReelGestureSurface = () => {
    const lockedSurface = shouldLockReelNavigation() ? activeReelSurface() : null;
    document.querySelectorAll("[data-nima-reel-gesture-lock='true']").forEach((surface) => {
      if (surface === lockedSurface) return;
      surface.style.removeProperty("touch-action");
      surface.style.removeProperty("overscroll-behavior");
      surface.removeAttribute("data-nima-reel-gesture-lock");
    });
    if (!lockedSurface) return;
    // Preserve taps and horizontal controls while preventing the vertical pan
    // gesture Instagram uses to advance its same-page Reel carousel.
    lockedSurface.style.setProperty("touch-action", "pan-x", "important");
    lockedSurface.style.setProperty("overscroll-behavior", "none", "important");
    lockedSurface.setAttribute("data-nima-reel-gesture-lock", "true");
  };

  const sameResource = (left, right) => {
    if (!left || !right) return false;
    try {
      const lhs = new URL(left, location.href);
      const rhs = new URL(right, location.href);
      return lhs.hostname.toLowerCase() === rhs.hostname.toLowerCase()
        && lhs.pathname.toLowerCase().replace(/\/$/, "") === rhs.pathname.toLowerCase().replace(/\/$/, "");
    } catch (_) { return false; }
  };

  const isAllowedDMClientURL = (value) => {
    const path = pathOf(value).replace(/\/$/, "");
    return path.startsWith("/direct")
      || path.startsWith("/accounts")
      || path.startsWith("/challenge")
      || path.startsWith("/two_factor")
      || path.startsWith("/login")
      || path.startsWith("/oauth")
      || path.startsWith("/dialog/oauth")
      || path === "/instagram/login_sync"
      || sameResource(value, window.__nimaSharedURL);
  };

  const isBackControl = (node) => {
    if (!node || !node.closest) return false;
    const control = node.closest("button, [role='button'], a, div");
    if (!control) return false;
    const labelledNode = control.matches("[aria-label]")
      ? control
      : control.querySelector("[aria-label]");
    const label = ((labelledNode && labelledNode.getAttribute("aria-label"))
      || control.getAttribute("title")
      || "").trim().toLowerCase();
    return label === "back" || label === "go back";
  };

  const hide = (node) => {
    if (!node || !node.style) return;
    if (node.getAttribute("data-nima-hidden") === "true" &&
        node.style.getPropertyValue("display") === "none") return;
    node.style.setProperty("display", "none", "important");
    if (node.getAttribute("data-nima-hidden") !== "true") {
      node.setAttribute("data-nima-hidden", "true");
    }
  };

  const hideAppInstallPrompts = () => {
    const promptLabels = new Set(["use the app", "open in app", "open in the app"]);
    document.querySelectorAll("a, button, [role='button'], div, span").forEach((node) => {
      const label = (node.textContent || "").trim().replace(/\s+/g, " ").toLowerCase();
      if (!promptLabels.has(label)) return;

      let candidate = node.closest("a, button, [role='button']") || node;
      let promptSurface = null;
      for (let depth = 0; candidate && depth < 8; depth += 1) {
        const rect = candidate.getBoundingClientRect();
        const style = getComputedStyle(candidate);
        const isBottomStrip = rect.width >= innerWidth * 0.65
          && rect.height > 0 && rect.height <= 160
          && rect.bottom >= innerHeight - 260;
        if (isBottomStrip) promptSurface = candidate;
        if (isBottomStrip && (style.position === "fixed" || style.position === "sticky")) break;
        if (rect.height > 200) break;
        candidate = candidate.parentElement;
      }
      hide(promptSurface || node.closest("a, button, [role='button']") || node);
    });
  };

  const hideExploreMediaAndNonAccountResults = () => {
    if (!isExploreSearch()) return;
    // Search results may be rendered in a portal beside <main>, so filter the
    // full document while the Search tab is active.
    const scope = document;
    if (!scope) return;

    scope.querySelectorAll("a[href]").forEach((anchor) => {
      const href = anchor.getAttribute("href") || "";
      if (isAccountResult(href)) return;
      if (!isExploreMediaDestination(href)) return;
      hide(anchor.closest("article") || anchor);
    });

    // Instagram sometimes renders discovery tiles before their link is attached.
    // Account avatars are preserved because their enclosing link points to a
    // one-segment profile URL.
    scope.querySelectorAll("video").forEach((video) => {
      const accountLink = video.closest("a[href]");
      if (!accountLink || !isAccountResult(accountLink.getAttribute("href") || "")) {
        hide(video.closest("article") || accountLink || video);
      }
    });
  };

  const bottomNavigationDestination = (value) => {
    const path = pathOf(value).replace(/\/$/, "");
    return path === ""
      || path === "/explore"
      || path.startsWith("/direct")
      || path.startsWith("/accounts/activity");
  };

  const findBottomNavigation = () => {
    const homeLinks = Array.from(document.querySelectorAll("a[href]"))
      .filter((anchor) => pathOf(anchor.getAttribute("href") || "").replace(/\/$/, "") === "")
      .filter((anchor) => {
        if (!visible(anchor)) return false;
        const rect = anchor.getBoundingClientRect();
        return rect.top > innerHeight - 180 && rect.bottom >= innerHeight - 80;
      });

    for (const homeLink of homeLinks) {
      let candidate = homeLink.parentElement;
      for (let depth = 0; candidate && depth < 10; depth += 1) {
        const rect = candidate.getBoundingClientRect();
        const destinationCount = Array.from(candidate.querySelectorAll("a[href]"))
          .filter((anchor) => bottomNavigationDestination(anchor.getAttribute("href") || ""))
          .length;
        if (destinationCount >= 3
            && rect.width >= innerWidth * 0.7
            && rect.height > 0 && rect.height <= 180
            && rect.bottom >= innerHeight - 30) {
          return candidate;
        }
        candidate = candidate.parentElement;
      }
    }
    return null;
  };

  const protectBottomNavigation = () => {
    if (!isExploreSearch()) {
      bottomNavigation = null;
      return;
    }

    const navigation = findBottomNavigation();
    if (!navigation) return;
    bottomNavigation = navigation;

    // Instagram's Recent-search overlay can be stacked above the persistent
    // bottom bar. Lift the compact bar containers above that overlay so both
    // their visuals and their hit targets remain unobstructed.
    let layer = navigation;
    for (let depth = 0; layer && depth < 4; depth += 1) {
      const rect = layer.getBoundingClientRect();
      if (rect.height <= 0 || rect.height > 190 || rect.bottom < innerHeight - 40) break;
      const position = getComputedStyle(layer).position;
      if (position === "static") layer.style.setProperty("position", "relative", "important");
      layer.style.setProperty("z-index", "2147483647", "important");
      layer.style.setProperty("pointer-events", "auto", "important");
      layer = layer.parentElement;
    }

    const navHeight = Math.max(56, Math.ceil(innerHeight - navigation.getBoundingClientRect().top));
    const accountLink = Array.from(document.querySelectorAll("a[href]"))
      .find((anchor) => isAccountResult(anchor.getAttribute("href") || "") && visible(anchor));
    let scrollSurface = accountLink && accountLink.parentElement;
    for (let depth = 0; scrollSurface && depth < 12; depth += 1) {
      const style = getComputedStyle(scrollSurface);
      const rect = scrollSurface.getBoundingClientRect();
      if ((style.overflowY === "auto" || style.overflowY === "scroll")
          && rect.height > 200 && rect.bottom > navigation.getBoundingClientRect().top) {
        scrollSurface.style.setProperty("scroll-padding-bottom", navHeight + "px", "important");
        break;
      }
      scrollSurface = scrollSurface.parentElement;
    }
  };

  const bottomNavigationLinkAt = (clientX, clientY) => {
    if (!isExploreSearch()) return null;
    if (!bottomNavigation || !document.contains(bottomNavigation)) {
      bottomNavigation = findBottomNavigation();
    }
    if (!bottomNavigation) return null;
    const barRect = bottomNavigation.getBoundingClientRect();
    if (clientY < barRect.top || clientY > barRect.bottom) return null;
    return Array.from(bottomNavigation.querySelectorAll("a[href]"))
      .filter((anchor) => visible(anchor))
      .find((anchor) => {
        const rect = anchor.getBoundingClientRect();
        return clientX >= rect.left && clientX <= rect.right;
      }) || null;
  };

  const openRecentSearches = () => {
    if (!isExploreSearch()) {
      lastActivatedSearchLocation = "";
      if (pendingSearchBlur !== null) clearTimeout(pendingSearchBlur);
      pendingSearchBlur = null;
      return;
    }

    const locationKey = location.pathname.toLowerCase() + location.search;
    if (lastActivatedSearchLocation === locationKey) return;

    const searchInput = document.querySelector(
      "input[placeholder='Search'], input[aria-label='Search input'], input[aria-label='Search']"
    );
    if (!searchInput) return;

    // Focusing Instagram's own search control switches the Explore shell to its
    // Recent view. Mark it first so the resulting DOM mutations do not refocus
    // the field while the user is typing.
    lastActivatedSearchLocation = locationKey;
    try { searchInput.click(); } catch (_) {}
    try { searchInput.focus({ preventScroll: true }); } catch (_) { searchInput.focus(); }

    const keepUserFocus = () => {
      if (pendingSearchBlur !== null) clearTimeout(pendingSearchBlur);
      pendingSearchBlur = null;
    };
    searchInput.addEventListener("pointerdown", keepUserFocus, { once: true, capture: true });
    pendingSearchBlur = setTimeout(() => {
      pendingSearchBlur = null;
      // Instagram keeps the Recent list mounted after blur. This presents the
      // list without an active cursor or keyboard; a later user tap focuses it.
      if (!searchInput.value && document.activeElement === searchInput) {
        searchInput.blur();
        // Instagram's visual focus state also listens for an outside pointer
        // event. Targeting the inert document body removes its Cancel affordance
        // without activating a recent account.
        const outsideTarget = document.body || document.documentElement;
        try {
          outsideTarget.dispatchEvent(new PointerEvent("pointerdown", {
            bubbles: true,
            cancelable: true,
            pointerType: "mouse"
          }));
          outsideTarget.dispatchEvent(new MouseEvent("mousedown", { bubbles: true, cancelable: true }));
          outsideTarget.dispatchEvent(new MouseEvent("mouseup", { bubbles: true, cancelable: true }));
          outsideTarget.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
        } catch (_) {}
      }
    }, 250);
  };

  const clean = () => {
    try {
      if (window.__nimaMode === "dm_only" && !isAllowedDMClientURL(location.href)) {
        if (lastBlockedLocation !== location.href) {
          lastBlockedLocation = location.href;
          send({ event: "blockedClientNavigation", url: location.href });
        }
        return;
      }
      lastBlockedLocation = "";

      hideAppInstallPrompts();

      document.querySelectorAll("a[href], [role='link']").forEach((node) => {
        const href = node.getAttribute("href") || "";
        const label = (node.getAttribute("aria-label") || node.textContent || "").trim().toLowerCase();
        const isProfileReelsTab = isProfilePage(location.href) && isProfilePage(href);
        if (isReelsFeed(href) || (label === "reels" && !isProfileReelsTab)) {
          hide(node.closest("a, [role='link']") || node);
        }
        if (!shouldLockReelNavigation()
            && !isDirect()
            && !isProfilePage(location.href)
            && isIndividualReel(href)
            && !sameResource(href, window.__nimaSharedURL)) {
          const card = node.closest("article") || node.closest("a") || node;
          hide(card);
        }
      });

      hideExploreMediaAndNonAccountResults();
      openRecentSearches();
      protectBottomNavigation();

      if (window.__nimaMode === "dm_only") {
        if (isDirectInbox()) {
          document.querySelectorAll("[aria-label]").forEach((node) => {
            const label = (node.getAttribute("aria-label") || "").trim().toLowerCase();
            if (label !== "back" && label !== "go back") return;
            hide(node.closest("button, a, [role='button']") || node.parentElement || node);
          });
        }

        document.querySelectorAll("nav a[href], header a[href]").forEach((node) => {
          const path = pathOf(node.getAttribute("href") || "");
          if (!path.startsWith("/direct") && !path.startsWith("/accounts")) hide(node);
        });

        if (shouldLockReelNavigation()) {
          const videos = Array.from(document.querySelectorAll("video"));
          const primaryVideo = videos.find((video) => {
            const rect = video.getBoundingClientRect();
            const centerY = rect.top + rect.height / 2;
            return rect.width > 0 && rect.height > 0 && centerY >= 0 && centerY <= innerHeight;
          });
          document.querySelectorAll("video").forEach((video) => {
            video.autoplay = false;
            video.loop = false;
            if (primaryVideo && video !== primaryVideo) video.pause();
            if (video.dataset.nimaCompletionInstalled !== "true") {
              video.dataset.nimaCompletionInstalled = "true";
              video.addEventListener("ended", () => send({ event: "reelFinished" }), { once: true });
            }
          });
        }
      }

      if (shouldLockReelNavigation()) {
        document.documentElement.style.setProperty("overscroll-behavior", "none", "important");
        document.body && document.body.style.setProperty("overscroll-behavior", "none", "important");
      }
      updateReelGestureSurface();

      const healthKey = window.__nimaMode + "|" + location.href;
      if (healthKey !== lastHealthKey) {
        lastHealthKey = healthKey;
        send({ event: "health", url: location.href });
      }
      reportSessionStatus();
    } catch (_) {
      // A missing health event makes native code fail closed to DM-only.
    }
  };

  document.addEventListener("click", (event) => {
    const intendedBottomLink = event.isTrusted
      ? bottomNavigationLinkAt(event.clientX, event.clientY)
      : null;
    if (intendedBottomLink && !intendedBottomLink.contains(event.target)) {
      event.preventDefault();
      event.stopImmediatePropagation();
      intendedBottomLink.click();
      return;
    }
    if (window.__nimaMode === "dm_only" && isDirect() && isBackControl(event.target)) {
      event.preventDefault();
      event.stopImmediatePropagation();
      send({ event: "dmBack" });
      return;
    }
    const anchor = event.target && event.target.closest && event.target.closest("a[href]");
    if (anchor) {
      const absolute = new URL(anchor.href, location.href).href;
      if (isExploreSearchURL(absolute)) {
        lastActivatedSearchLocation = "";
        [0, 80, 250].forEach((delay) => setTimeout(openRecentSearches, delay));
      }
      send({ event: "linkActivated", url: absolute });
      if (window.__nimaMode === "clean"
          && isProfilePage(location.href)
          && isIndividualReel(absolute)) {
        window.__nimaSharedURL = absolute;
        window.__nimaSharedReelOpen = true;
        send({ event: "sharedReelOpened", url: absolute });
        clean();
      }
      if (isReelsFeed(absolute)) {
        event.preventDefault();
        event.stopImmediatePropagation();
      }
    }
    if (window.__nimaMode === "dm_only" && isDirect()) {
      const clickedReelURL = reelURLNear(event.target);
      if (clickedReelURL) {
        window.__nimaSharedURL = clickedReelURL;
        window.__nimaSharedReelOpen = true;
        send({ event: "sharedReelOpened", url: clickedReelURL });
      }
      [0, 80, 250, 600].forEach((delay) => setTimeout(detectOpenedSharedReel, delay));
    }
  }, true);

  const armReelGestureLock = () => {
    if (!shouldLockReelNavigation() && window.__nimaMode === "dm_only" && isDirect()) {
      detectOpenedSharedReel();
    }
    return shouldLockReelNavigation();
  };
  const gestureTravelled = (start, clientX, clientY) => Boolean(start)
    && (Math.abs(clientX - start.x) >= reelSwipeThreshold
      || Math.abs(clientY - start.y) >= reelSwipeThreshold);
  const stopReelAdvance = (event) => {
    if (!armReelGestureLock()) return false;
    event.preventDefault();
    event.stopImmediatePropagation();
    return true;
  };
  window.addEventListener("touchstart", (event) => {
    if (!armReelGestureLock() || event.touches.length !== 1) {
      reelTouchStart = null;
      return;
    }
    const touch = event.touches[0];
    reelTouchStart = { x: touch.clientX, y: touch.clientY };
  }, { capture: true, passive: true });
  window.addEventListener("touchmove", stopReelAdvance, { capture: true, passive: false });
  window.addEventListener("touchend", (event) => {
    const touch = event.changedTouches && event.changedTouches[0];
    const isSwipe = touch && gestureTravelled(reelTouchStart, touch.clientX, touch.clientY);
    reelTouchStart = null;
    if (isSwipe) stopReelAdvance(event);
  }, { capture: true, passive: false });
  window.addEventListener("touchcancel", () => { reelTouchStart = null; }, true);
  window.addEventListener("pointerdown", (event) => {
    if (event.pointerType !== "touch" || !armReelGestureLock()) return;
    reelPointerStarts.set(event.pointerId, { x: event.clientX, y: event.clientY });
  }, { capture: true, passive: true });
  window.addEventListener("pointermove", (event) => {
    if (event.pointerType === "touch") stopReelAdvance(event);
  }, { capture: true, passive: false });
  window.addEventListener("pointerup", (event) => {
    if (event.pointerType !== "touch") return;
    const start = reelPointerStarts.get(event.pointerId);
    reelPointerStarts.delete(event.pointerId);
    if (gestureTravelled(start, event.clientX, event.clientY)) stopReelAdvance(event);
  }, { capture: true, passive: false });
  window.addEventListener("pointercancel", (event) => {
    reelPointerStarts.delete(event.pointerId);
  }, true);
  window.addEventListener("wheel", stopReelAdvance, { capture: true, passive: false });
  window.addEventListener("keydown", (event) => {
    if (shouldLockReelNavigation()
        && ["ArrowUp", "ArrowDown", "PageUp", "PageDown", " "].includes(event.key)) {
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  }, true);

  const notifyLocation = () => {
    send({ event: "locationChanged", url: location.href });
    clean();
  };
  ["pushState", "replaceState"].forEach((method) => {
    const original = history[method];
    history[method] = function () {
      let requestedURL = location.href;
      try {
        if (arguments.length > 2 && arguments[2]) {
          requestedURL = new URL(arguments[2], location.href).href;
        }
      } catch (_) {
        send({ event: "blockedClientNavigation" });
        return;
      }
      if (window.__nimaMode === "dm_only" && !isAllowedDMClientURL(requestedURL)) {
        send({ event: "blockedClientNavigation", url: requestedURL });
        return;
      }
      const result = original.apply(this, arguments);
      setTimeout(notifyLocation, 0);
      return result;
    };
  });
  addEventListener("popstate", notifyLocation);

  window.__nimaConfigure = (configuration) => {
    const config = configuration || {};
    window.__nimaMode = config.mode === "dm_only" ? "dm_only" : "clean";
    window.__nimaSharedURL = typeof config.sharedURL === "string" ? config.sharedURL : null;
    window.__nimaSharedReelOpen = config.sharedReelOpen === true;
    clean();
  };

  window.__nimaSetMode = (mode) => window.__nimaConfigure({
    mode,
    sharedURL: window.__nimaSharedURL,
    sharedReelOpen: window.__nimaSharedReelOpen
  });

  const queueClean = () => {
    if (cleanQueued) return;
    cleanQueued = true;
    requestAnimationFrame(() => {
      cleanQueued = false;
      clean();
    });
  };
  const observer = new MutationObserver(() => {
    // Run this synchronously in the mutation microtask so Instagram's app
    // install banner is hidden before the browser gets another paint.
    hideAppInstallPrompts();
    queueClean();
  });
  const install = () => {
    if (document.documentElement) {
      observer.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ["href", "aria-label", "role"]
      });
      clean();
      detectOpenedSharedReel();
    } else {
      setTimeout(install, 20);
    }
  };
  install();
  setInterval(() => {
    if (window.__nimaMode === "dm_only") {
      detectOpenedSharedReel();
      clean();
    }
  }, 500);
})();
