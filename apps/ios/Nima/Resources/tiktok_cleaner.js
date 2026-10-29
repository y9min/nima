(function () {
  if (window.__nimaTikTokCleanerInstalled) return;
  window.__nimaTikTokCleanerInstalled = true;

  window.__nimaTikTokGrantedVideoURL = null;
  window.__nimaTikTokVideoOverlayOpen = false;
  window.__nimaTikTokMode = "clean";
  var lastLocation = location.href;
  var lastHealth = "";
  var nativeNavigationInProgress = false;
  var directMessagePanelOrigin = null;
  var directMessageSelectionRequested = false;
  var pendingDirectMessageIdentity = null;
  var lastDirectMessageIdentity = "";
  var feedScrollingEnabled = false;
  var touchStartY = null;
  var lastDirectMessageClickItem = null;
  var lastDirectMessageClickAt = 0;
  var inboxReadyReported = false;
  var lastNotificationTapSource = null;
  var lastNotificationTapAt = 0;
  const feedCardWidth = "calc(100vw - 60px)";
  const feedActionRailWidth = "34px";

  const bridge = window.webkit && window.webkit.messageHandlers
    && window.webkit.messageHandlers.nimaTikTok;
  const send = (payload) => {
    try { bridge && bridge.postMessage(payload); } catch (_) {}
  };
  const pathOf = (value) => {
    try { return new URL(value, location.href).pathname.toLowerCase().replace(/\/$/, "") || "/"; }
    catch (_) { return ""; }
  };
  feedScrollingEnabled = ["/following", "/friends"].some(
    (path) => pathOf(location.href).startsWith(path)
  );
  const isVideoURL = (value) => /^\/@[^/]+\/video\/[^/]+/.test(pathOf(value));
  const isForYou = (value) => ["/", "/foryou"].includes(pathOf(value));
  const visible = (node) => {
    if (!node || !node.getBoundingClientRect) return false;
    const rect = node.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0 && rect.bottom > 0 && rect.top < innerHeight;
  };
  const textOf = (node) => ((node && (node.getAttribute("aria-label")
    || node.getAttribute("title") || node.textContent)) || "")
    .trim().replace(/\s+/g, " ").toLowerCase();
  const rawTextOf = (node) => ((node && (node.getAttribute("aria-label")
    || node.getAttribute("title") || node.textContent)) || "")
    .trim().replace(/\s+/g, " ");
  const hide = (node) => {
    if (!node || !node.style) return;
    if (node.getAttribute("data-nima-hidden") === "true"
        && node.style.getPropertyValue("display") === "none") return;
    node.style.setProperty("display", "none", "important");
    node.setAttribute("data-nima-hidden", "true");
  };
  const currentSurfaceAllowsVideo = () => {
    if (feedScrollingEnabled) return false;
    const path = pathOf(location.href);
    if (window.__nimaTikTokMode === "dm_only") {
      return path.startsWith("/messages")
        && document.documentElement.hasAttribute("data-nima-dm-active");
    }
    return path.startsWith("/search") || path.startsWith("/messages")
      || path.startsWith("/inbox") || path.startsWith("/@");
  };
  const locked = () => !feedScrollingEnabled && (
    window.__nimaTikTokVideoOverlayOpen
      || isVideoURL(location.href)
      || isVideoURL(window.__nimaTikTokGrantedVideoURL || "")
  );

  const updateSurfaceMode = (value) => {
    const previous = feedScrollingEnabled;
    const path = pathOf(value);
    if (path.startsWith("/following") || path.startsWith("/friends")) {
      feedScrollingEnabled = true;
    } else if (path.startsWith("/search") || path.startsWith("/messages")
        || path.startsWith("/inbox") || path.startsWith("/profile")) {
      feedScrollingEnabled = false;
    }
    // A feed may update its URL to /@user/video/id while swiping. Preserve
    // the existing feed mode for video URLs so that this does not lock it.
    if (previous !== feedScrollingEnabled) broadcastFeedScrollingState();
  };

  const broadcastFeedScrollingState = () => {
    if (window !== window.top) {
      window.parent.postMessage({ nimaTikTokFeedStateRequest: true }, "*");
      return;
    }
    document.querySelectorAll("iframe").forEach((frame) => {
      try {
        frame.contentWindow?.postMessage({
          nimaTikTokFeedScrolling: feedScrollingEnabled
        }, "*");
      } catch (_) {}
    });
  };

  const removeForYou = () => {
    document.querySelectorAll("a[href], button, [role='tab'], [role='button']").forEach((node) => {
      const label = textOf(node);
      const fypLabel = label === "for you" || label === "for you feed";
      if (!fypLabel) return;
      let candidate = node.closest("li, [role='tab'], a, button") || node;
      hide(candidate);
    });
  };

  const removeAppPrompts = () => {
    const appButtonLabels = [
      "open app",
      "open in tiktok",
      "open tiktok",
      "continue in app",
      "continue in tiktok",
      "download tiktok"
    ];
    const roots = [document];
    document.querySelectorAll("*").forEach((node) => {
      if (node.shadowRoot) roots.push(node.shadowRoot);
    });
    roots.forEach((root) => {
      const fullAppLabels = [
        "get the full app experience",
        "get the full tiktok experience",
        "enjoy more videos and great features on the app"
      ];
      const matchingPromptNodes = Array.from(root.querySelectorAll("*"))
        .filter((node) => fullAppLabels.includes(textOf(node)));
      matchingPromptNodes.forEach((node) => {
        const hasMatchingChild = Array.from(node.children || [])
          .some((child) => fullAppLabels.includes(textOf(child)));
        if (hasMatchingChild) return;
        // Hide the whole card, including its logo and dismissal control, before
        // TikTok's own click handler has a chance to remove the modal.
        let card = node;
        let promptDismiss = null;
        for (let parent = node.parentElement, depth = 0;
            parent && depth < 6; parent = parent.parentElement, depth += 1) {
          if (parent === document.body || parent === document.documentElement) break;
          const dismissControl = Array.from(parent.querySelectorAll(
            "button, a, [role='button'], div, span"
          )).find((control) => textOf(control) === "not now");
          if (dismissControl) {
            card = parent;
            promptDismiss = dismissControl;
            break;
          }
        }
        if (card.getAttribute("data-nima-app-prompt-dismissed") === "true") return;
        hide(card);
        card.setAttribute("data-nima-app-prompt-dismissed", "true");
        promptDismiss?.click();
      });
      const dismiss = Array.from(root.querySelectorAll("button, a, [role='button']"))
        .find((node) => visible(node) && textOf(node) === "not now");
      if (dismiss) {
        dismiss.click();
        return;
      }
      root.querySelectorAll("button, a, [role='button']").forEach((node) => {
        if (appButtonLabels.includes(textOf(node))) hide(node);
      });
    });
  };

  const hideNativeNavigation = () => {
    // TikTok can change a feed's URL to a video URL while the feed stays open.
    const challengeFrames = Array.from(document.querySelectorAll(
      'iframe[src*="captcha"], iframe[src*="verify"], [class*="Captcha"], [class*="captcha"], [id*="captcha"]'
    )).some(visible);
    const challengeText = (document.body?.textContent || "").toLowerCase()
      .includes("drag the puzzle piece into place");
    const onFeed = feedScrollingEnabled && window === window.top
      && !challengeFrames && !challengeText;
    document.documentElement.toggleAttribute("data-nima-feed-surface", onFeed);
    if (!document.getElementById("nima-feed-navigation-style")) {
      const style = document.createElement("style");
      style.id = "nima-feed-navigation-style";
      style.textContent = `
        html[data-nima-feed-surface] [class*="DivSideNavPlaceholderContainer"],
        html[data-nima-feed-surface] [class*="DivSideNavContainer"],
        html[data-nima-feed-surface] [data-e2e="side-nav-shell"],
        html[data-nima-feed-surface] [class*="SideNavPlaceholder"],
        html[data-nima-feed-surface] [class*="SideNavContainer"] {
          display: none !important;
          width: 0 !important;
          flex: 0 0 0 !important;
        }
        html[data-nima-feed-surface],
        html[data-nima-feed-surface] body {
          width: 100% !important;
          max-width: 100% !important;
        }
        html[data-nima-feed-surface] :is(main, [role="main"],
          [class*="DivMainContainer"]):has(
            [class*="ArticleItemContainer"], [class*="DivFixedPageContainer"]) {
          width: 100vw !important;
          max-width: 100vw !important;
          min-width: 0 !important;
          margin-left: 0 !important;
          margin-right: 0 !important;
          box-sizing: border-box !important;
        }
        html[data-nima-feed-surface] [class*="ArticleItemContainer"] {
          width: 100vw !important;
          max-width: 100vw !important;
          min-width: 0 !important;
          padding-left: 8px !important;
          padding-right: 8px !important;
          padding-top: 8px !important;
          padding-bottom: 8px !important;
          box-sizing: border-box !important;
        }
        html[data-nima-feed-surface] [class*="ContentFlexLayout"] {
          width: calc(100vw - 16px) !important;
          max-width: calc(100vw - 16px) !important;
          min-width: 0 !important;
          margin-left: auto !important;
          margin-right: auto !important;
          gap: 10px !important;
          box-sizing: border-box !important;
        }
        html[data-nima-feed-surface] [class*="MediaCardContainer"] {
          width: calc(100vw - 60px) !important;
          max-width: calc(100vw - 60px) !important;
          min-width: calc(100vw - 60px) !important;
          flex-shrink: 0 !important;
          box-sizing: border-box !important;
        }
        html[data-nima-feed-surface]
          [class*="ContentFlexLayout"] > [class*="MediaCardContainer"] + * {
          width: 34px !important;
          min-width: 34px !important;
          max-width: 34px !important;
          flex: 0 0 34px !important;
          box-sizing: border-box !important;
        }
        html[data-nima-feed-surface] [class*="DivContaineriOS"] {
          width: calc(100vw - 60px) !important;
          max-width: calc(100vw - 60px) !important;
          height: calc(100vh - 16px) !important;
          margin-left: 8px !important;
          margin-top: 8px !important;
          border-radius: 16px !important;
          overflow: hidden !important;
        }
        html[data-nima-feed-surface] [class*="VideoPlayerContainer"] {
          flex-shrink: 1 !important;
          min-width: 0 !important;
          max-width: 100% !important;
        }
      `;
      (document.head || document.documentElement).appendChild(style);
    }
    const controls = Array.from(document.querySelectorAll(
      "a[href], button, [role='tab'], [role='button']"
    )).filter(visible);
    const labelCount = (container, labels) => new Set(
      Array.from(container.querySelectorAll("a[href], button, [role='tab'], [role='button']"))
        .map(textOf)
        .filter((label) => labels.includes(label))
    ).size;
    const findBar = (labels, requiredCount) => {
      for (const control of controls) {
        if (!labels.includes(textOf(control))) continue;
        let candidate = control.parentElement;
        for (let depth = 0; candidate && depth < 6; depth += 1, candidate = candidate.parentElement) {
          const rect = candidate.getBoundingClientRect && candidate.getBoundingClientRect();
          if (!rect || rect.width < innerWidth * 0.72 || rect.height > 130) continue;
          if (labelCount(candidate, labels) >= requiredCount) return candidate;
        }
      }
      return null;
    };
    hide(findBar(["home", "inbox", "profile", "friends", "following"], 3));
    hide(findBar(["for you", "following", "friends"], 2));
    if (onFeed) {
      // The desktop rail may be a plain div rather than a nav or aside.
      const candidates = new Set(document.querySelectorAll(
        "nav, aside, [role='navigation']"
      ));
      controls.forEach((control) => {
        for (let node = control.parentElement, depth = 0;
            node && depth < 8; node = node.parentElement, depth += 1) {
          candidates.add(node);
        }
      });
      const rail = Array.from(candidates).filter((node) => {
        const rect = node.getBoundingClientRect();
        if (rect.left > innerWidth * 0.08 || rect.width > innerWidth * 0.38
            || rect.height < innerHeight * 0.55 || rect.bottom < innerHeight * 0.7
            || node.querySelector("video")) return false;
        return node.querySelectorAll("a[href], button, [role='button']").length >= 3;
      }).sort((left, right) =>
        right.getBoundingClientRect().height - left.getBoundingClientRect().height
      )[0];
      hide(rail);
    }
  };

  const setFeedLayoutStyle = (node, property, value) => {
    if (!node || (node.style.getPropertyValue(property) === value
        && node.style.getPropertyPriority(property) === "important")) return;
    node.style.setProperty(property, value, "important");
  };

  const repairFriendsFeedLayout = () => {
    if (!feedScrollingEnabled || window !== window.top) return;
    const set = setFeedLayoutStyle;
    document.querySelectorAll("video").forEach((video) => {
      const card = video.closest('[class*="MediaCardContainer"]');
      const layout = card?.parentElement;
      const article = layout?.parentElement;
      if (!card || !layout || !article
          || !String(layout.className).includes("ContentFlexLayout")
          || !String(article.className).includes("ArticleItemContainer")) return;

      set(article, "width", "100vw");
      set(article, "max-width", "100vw");
      set(article, "padding-left", "8px");
      set(article, "padding-right", "8px");
      set(article, "padding-top", "8px");
      set(article, "padding-bottom", "8px");
      set(layout, "width", "calc(100vw - 16px)");
      set(layout, "max-width", "calc(100vw - 16px)");
      set(layout, "height", "calc(100vh - 16px)");
      set(layout, "gap", "10px");
      set(card, "width", feedCardWidth);
      set(card, "max-width", feedCardWidth);
      set(card, "min-width", feedCardWidth);
      set(card, "flex-shrink", "0");
      set(card, "height", "100%");
      set(card, "max-height", "100%");
      const actionRail = card.nextElementSibling;
      if (actionRail && !actionRail.querySelector("video")) {
        set(actionRail, "width", feedActionRailWidth);
        set(actionRail, "min-width", feedActionRailWidth);
        set(actionRail, "max-width", feedActionRailWidth);
        set(actionRail, "flex", `0 0 ${feedActionRailWidth}`);
        set(actionRail, "box-sizing", "border-box");
      }
      for (let node = video; node && node !== card; node = node.parentElement) {
        set(node, "width", "100%");
        set(node, "max-width", "100%");
        set(node, "height", "100%");
        set(node, "max-height", "100%");
      }
      set(video, "object-fit", "cover");
    });
  };

  const repairFollowingFeedLayout = () => {
    if (!feedScrollingEnabled || window !== window.top) return;
    const set = setFeedLayoutStyle;
    document.querySelectorAll("video").forEach((video) => {
      const card = video.closest('[class*="DivContaineriOS"]');
      if (!card) return;
      const layout = card.parentElement;
      if (String(layout?.className).includes("DivFlex1")) {
        set(layout, "height", "100vh");
      }
      set(card, "width", feedCardWidth);
      set(card, "max-width", feedCardWidth);
      set(card, "min-width", feedCardWidth);
      set(card, "height", "calc(100vh - 16px)");
      set(card, "max-height", "calc(100vh - 16px)");
      set(card, "flex-shrink", "0");
      set(card, "margin-left", "8px");
      set(card, "margin-top", "8px");
      set(card, "border-radius", "16px");
      set(card, "overflow", "hidden");
      for (let node = video; node && node !== card; node = node.parentElement) {
        set(node, "width", "100%");
        set(node, "max-width", "100%");
        set(node, "height", "100%");
        set(node, "max-height", "100%");
      }
      set(video, "width", "100%");
      set(video, "height", "100%");
      set(video, "object-fit", "cover");
      const swiper = Array.from(layout?.children || []).find((child) =>
        String(child.className).includes("DivSwiperContainer")
      );
      set(swiper, "height", "100vh");
    });
  };

  const removeEmptySearchDiscovery = () => {
    if (!pathOf(location.href).startsWith("/search")) return;

    // TikTok renders the heading and its recommendations as siblings, so
    // hiding only the heading leaves the actual "You may like" list visible.
    Array.from(document.querySelectorAll("h1, h2, h3, [role='heading'], div, span"))
      .filter((node) => textOf(node) === "you may like")
      .forEach((heading) => {
        // The mobile page often renders the heading and every recommendation
        // row as siblings rather than wrapping them in one section.
        let siblingBoundary = heading;
        for (let depth = 0; depth < 3 && siblingBoundary; depth += 1) {
          if (siblingBoundary.nextElementSibling) {
            let sibling = siblingBoundary.nextElementSibling;
            while (sibling) {
              const next = sibling.nextElementSibling;
              if (!sibling.querySelector("input, form")) {
                sibling.setAttribute("data-nima-search-suggestion", "true");
                hide(sibling);
              }
              sibling = next;
            }
            break;
          }
          siblingBoundary = siblingBoundary.parentElement;
        }

        let candidate = heading.parentElement || heading;
        let section = null;
        for (let depth = 0; candidate.parentElement && depth < 5; depth += 1) {
          const parent = candidate.parentElement;
          const rect = parent.getBoundingClientRect && parent.getBoundingClientRect();
          const recommendations = parent.querySelectorAll(
            "a[href], li, [role='listitem'], button"
          ).length;
          const ownsSearchUI = !!parent.querySelector("input, form");
          const isPageContainer = parent === document.body || parent === document.documentElement;
          if (!ownsSearchUI && !isPageContainer && recommendations >= 2 && rect
              && rect.height < innerHeight * 0.62) {
            section = parent;
            break;
          }
          candidate = parent;
        }
        // Never fall back to the heading's parent: TikTok sometimes places the
        // heading directly inside the container that also owns the search form.
        candidate = section || heading;
        candidate.setAttribute("data-nima-search-suggestion", "true");
        hide(candidate);
      });

    let hasQuery = false;
    try {
      const url = new URL(location.href);
      hasQuery = ["q", "keyword", "query"].some((key) => (url.searchParams.get(key) || "").trim());
    } catch (_) {}
    const searchInput = document.querySelector("input[type='search'], input[placeholder*='Search' i]");
    if (!hasQuery && searchInput) hasQuery = !!searchInput.value.trim();
    if (hasQuery) {
      document.querySelectorAll("[data-nima-search-hidden='true']").forEach((node) => {
        node.style.removeProperty("display");
        node.removeAttribute("data-nima-hidden");
        node.removeAttribute("data-nima-search-hidden");
      });
      document.querySelectorAll("[data-nima-search-suggestion='true']").forEach((node) => {
        node.style.removeProperty("display");
        node.removeAttribute("data-nima-hidden");
      });
      return;
    }

    document.querySelectorAll("a[href]").forEach((anchor) => {
      const path = pathOf(anchor.href);
      if (!isVideoURL(anchor.href) && !path.startsWith("/music/")
          && !path.startsWith("/tag/") && !path.startsWith("/topic/")) return;
      const candidate = anchor.closest("article, li, [role='listitem']") || anchor;
      candidate.setAttribute("data-nima-search-hidden", "true");
      hide(candidate);
    });
    document.querySelectorAll("h1, h2, h3, [role='heading']").forEach((heading) => {
      const label = textOf(heading);
      if (label.includes("explore") || label.includes("trending")
          || label.includes("recommended") || label.includes("you may like")) {
        const candidate = heading.parentElement || heading;
        candidate.setAttribute("data-nima-search-hidden", "true");
        hide(candidate);
      }
    });
  };

  const removeBlockedSurfaces = () => {
    document.querySelectorAll("a[href]").forEach((anchor) => {
      const path = pathOf(anchor.getAttribute("href") || "");
      if (path.startsWith("/live") || path.startsWith("/shop")
          || path.startsWith("/discover") || path.startsWith("/explore")) {
        hide(anchor);
      }
    });
  };

  const repairNotificationInbox = () => {
    if (window !== window.top) return;
    const onInbox = pathOf(location.href).startsWith("/inbox");
    document.documentElement.toggleAttribute("data-nima-notification-surface", onInbox);
    if (!onInbox) return;
    if (!document.getElementById("nima-notification-style")) {
      const style = document.createElement("style");
      style.id = "nima-notification-style";
      style.textContent = `
        html[data-nima-notification-surface] [data-nima-notification-title] { display: none !important; }
        html[data-nima-notification-surface] [data-nima-notification-filters] {
          display: flex !important;
          flex-wrap: nowrap !important;
          overflow-x: auto !important;
          overflow-y: hidden !important;
          -webkit-overflow-scrolling: touch;
          scrollbar-width: none !important;
        }
        html[data-nima-notification-surface] [data-nima-notification-filters]::-webkit-scrollbar { display: none; }
        html[data-nima-notification-surface] [data-nima-notification-filters] > * { flex: 0 0 auto !important; }
        @media (prefers-color-scheme: dark) {
          html[data-nima-notification-surface],
          html[data-nima-notification-surface] body {
            background-color: #000 !important;
            color-scheme: dark;
          }
          html[data-nima-notification-surface] [data-nima-notification-bg="primary"] { background-color: #000 !important; }
          html[data-nima-notification-surface] [data-nima-notification-bg="secondary"] { background-color: #161616 !important; }
          html[data-nima-notification-surface] [data-nima-notification-bg="tertiary"] { background-color: #242424 !important; }
          html[data-nima-notification-surface] [data-nima-notification-color="primary"] { color: #ededed !important; }
          html[data-nima-notification-surface] [data-nima-notification-color="secondary"] { color: #8a8a8a !important; }
          html[data-nima-notification-surface] [data-nima-notification-border] { border-color: #303030 !important; }
          html[data-nima-notification-surface] [data-nima-notification-selected] {
            background-color: #e6e6e6 !important;
            color: #111 !important;
          }
          html[data-nima-notification-surface] [data-nima-notification-selected] * { color: #111 !important; }
        }
      `;
      (document.head || document.documentElement).appendChild(style);
    }

    const neutral = (value) => {
      const match = String(value || "").match(
        /^rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)$/
      );
      if (!match || Number(match[4] ?? 1) < 0.25) return null;
      const channels = match.slice(1, 4).map(Number);
      if (Math.max(...channels) - Math.min(...channels) > 32) return null;
      return channels.reduce((sum, channel) => sum + channel, 0) / 3;
    };
    document.querySelectorAll("body *").forEach((node) => {
      if (node.matches("img, video, canvas, svg, path, picture, iframe, script, style")) return;
      const needsColor = !node.hasAttribute("data-nima-notification-color");
      const needsBackground = !node.hasAttribute("data-nima-notification-bg");
      const needsBorder = !node.hasAttribute("data-nima-notification-border");
      if (!needsColor && !needsBackground && !needsBorder) return;
      const computed = getComputedStyle(node);
      if (needsColor) {
        const tone = neutral(computed.color);
        if (tone !== null && tone < 205) {
          const alpha = computed.color.startsWith("rgba(")
            ? Number(computed.color.match(/,\s*([\d.]+)\)$/)?.[1] ?? 1)
            : 1;
          node.setAttribute("data-nima-notification-color",
            tone < 75 && alpha >= 0.9 ? "primary" : "secondary");
        }
      }
      if (needsBackground) {
        const tone = neutral(computed.backgroundColor);
        if (tone !== null && tone >= 190) {
          node.setAttribute("data-nima-notification-bg",
            tone >= 248 ? "primary" : tone >= 225 ? "secondary" : "tertiary");
        }
      }
      if (needsBorder) {
        const tone = neutral(computed.borderTopColor);
        if (computed.borderTopWidth !== "0px" && tone !== null && tone >= 160) {
          node.setAttribute("data-nima-notification-border", "true");
        }
      }
    });

    const labels = new Set([
      "all activity", "likes", "comments", "mentions and tags", "followers"
    ]);
    const controls = Array.from(document.querySelectorAll(
      "button, [role='tab'], [role='button']"
    )).filter((node) => labels.has(textOf(node)));
    const first = controls.find((node) => textOf(node) === "all activity");
    if (first) {
      let candidate = first.parentElement;
      for (let depth = 0; candidate && candidate !== document.body && depth < 5;
          depth += 1, candidate = candidate.parentElement) {
        if (controls.filter((node) => candidate.contains(node)).length >= 3
            && candidate.getBoundingClientRect().height < 180) {
          candidate.setAttribute("data-nima-notification-filters", "true");
          break;
        }
      }
    }
    controls.forEach((control) => {
      // Read TikTok's own selected state before our dark chip style is applied.
      control.removeAttribute("data-nima-notification-selected");
      const backgroundMarker = control.getAttribute("data-nima-notification-bg");
      control.removeAttribute("data-nima-notification-bg");
      const tone = neutral(getComputedStyle(control).backgroundColor);
      if (backgroundMarker) {
        control.setAttribute("data-nima-notification-bg", backgroundMarker);
      }
      if (control.getAttribute("aria-selected") === "true"
          || control.getAttribute("aria-pressed") === "true"
          || (tone !== null && tone < 75)) {
        control.setAttribute("data-nima-notification-selected", "true");
      } else {
        control.removeAttribute("data-nima-notification-selected");
      }
    });
    Array.from(document.querySelectorAll("h1, h2, [role='heading']"))
      .filter((node) => textOf(node) === "notifications")
      .forEach((heading) => {
        const parent = heading.parentElement;
        const target = parent && parent !== document.body
          && parent.getBoundingClientRect().height < 120
          && !parent.contains(first) ? parent : heading;
        target.setAttribute("data-nima-notification-title", "true");
      });
  };

  const directMessageInput = () => document.querySelector(
    '[data-e2e="message-input"], div.notranslate.public-DraftEditor-content'
  );

  const restoreDirectMessageList = () => {
    directMessageSelectionRequested = false;
    pendingDirectMessageIdentity = null;
    document.querySelectorAll('[data-nima-dm-panel="true"]').forEach((panel) => {
      panel.removeAttribute("data-nima-dm-panel");
      if (directMessagePanelOrigin && directMessagePanelOrigin.panel === panel
          && directMessagePanelOrigin.parent?.isConnected) {
        directMessagePanelOrigin.parent.insertBefore(
          panel,
          directMessagePanelOrigin.nextSibling?.isConnected
            ? directMessagePanelOrigin.nextSibling
            : null
        );
      }
    });
    directMessagePanelOrigin = null;
    document.querySelectorAll('[data-nima-dm-host="true"]').forEach((host) => {
      host.removeAttribute("data-nima-dm-host");
    });
    document.querySelectorAll('[data-nima-dm-web-header="true"]').forEach((header) => {
      header.removeAttribute("data-nima-dm-web-header");
    });
    document.querySelectorAll(
      '[data-nima-dm-composer="true"], [data-nima-dm-input-branch="true"], '
        + '[data-nima-dm-send-branch="true"], [data-nima-dm-send="true"]'
    ).forEach((node) => {
      node.removeAttribute("data-nima-dm-composer");
      node.removeAttribute("data-nima-dm-input-branch");
      node.removeAttribute("data-nima-dm-send-branch");
      node.removeAttribute("data-nima-dm-send");
    });
    document.documentElement.removeAttribute("data-nima-dm-active");
    if (lastDirectMessageIdentity) {
      lastDirectMessageIdentity = "";
      send({ event: "directMessageClosed" });
    }
  };

  const reportDirectMessageIdentity = (panel, input) => {
    if (lastDirectMessageIdentity) return;
    const inputTop = input.getBoundingClientRect().top;
    const headerBottom = Math.min(inputTop, 190);
    const candidates = Array.from(panel.querySelectorAll("a, span, p, div"))
      .map((node) => ({ node, rect: node.getBoundingClientRect(), text: rawTextOf(node) }))
      .filter(({ rect, text }) => text && text.length <= 64 && rect.height > 0
        && rect.top >= 0 && rect.bottom <= headerBottom && rect.height <= 72);
    const profileLink = Array.from(panel.querySelectorAll('a[href*="/@"]')).find((node) => {
      const rect = node.getBoundingClientRect();
      return rect.top >= 0 && rect.bottom <= headerBottom;
    });
    let handle = "";
    if (profileLink) {
      const match = pathOf(profileLink.href).match(/^\/@([^/]+)/);
      if (match) handle = `@${match[1]}`;
    }
    const handleEntry = candidates.find(({ text }) => /^@[a-z0-9._]+$/i.test(text));
    if (!handle) handle = handleEntry?.text || "";

    const ignored = new Set(["inbox", "messages", "send", "send a message…", "send a message..."]);
    const pageName = candidates.find(({ text }) => text !== handle && !text.startsWith("@")
      && (!handle || !text.includes(handle)) && text.length <= 32
      && !ignored.has(text.toLowerCase()) && !/^\d{1,2}:\d{2}$/.test(text)
      && !/^(january|february|march|april|may|june|july|august|september|october|november|december)\b/i
        .test(text))?.text || "";
    const avatar = Array.from(panel.querySelectorAll("img")).find((node) => {
      const rect = node.getBoundingClientRect();
      return rect.top >= 0 && rect.bottom <= headerBottom
        && rect.width >= 24 && rect.width <= 96 && rect.height >= 24 && rect.height <= 96;
    });
    const headerSeed = profileLink || handleEntry?.node || avatar;
    let webHeader = null;
    let headerNode = headerSeed;
    const panelWidth = panel.getBoundingClientRect().width;
    for (let depth = 0; headerNode && headerNode !== panel && depth < 7;
        depth += 1, headerNode = headerNode.parentElement) {
      const rect = headerNode.getBoundingClientRect();
      if (rect.top <= 24 && rect.bottom <= 190 && rect.height <= 160
          && rect.width >= panelWidth * 0.55) {
        webHeader = headerNode;
      }
    }
    webHeader?.setAttribute("data-nima-dm-web-header", "true");

    const name = pendingDirectMessageIdentity?.name || pageName;
    const avatarURL = pendingDirectMessageIdentity?.avatarURL
      || avatar?.currentSrc || avatar?.src || "";
    const payload = {
      event: "directMessageSelected",
      name,
      handle,
      avatarURL
    };
    const identity = JSON.stringify(payload);
    if (identity === lastDirectMessageIdentity) return;
    lastDirectMessageIdentity = identity;
    send(payload);
  };

  const showSelectedDirectMessage = () => {
    if (!directMessageSelectionRequested || !pathOf(location.href).startsWith("/messages")) {
      return false;
    }
    const input = directMessageInput();
    if (!input) return false;

    // TikTok's desktop inbox is a split view. Find the first common ancestor
    // of the conversation list and composer, then use only the composer-side
    // branch. Picking an ancestor by size can accidentally select the whole
    // inbox, leaving the real chat pane off the right edge of the phone.
    let panel = input;
    let parent = input.parentElement;
    while (parent && parent !== document.body) {
      if (parent.querySelector('[data-e2e="dm-new-conversation-item"]')) break;
      panel = parent;
      parent = parent.parentElement;
    }
    if (!parent || parent === document.body || panel === input) return false;

    if (!directMessagePanelOrigin || directMessagePanelOrigin.panel !== panel) {
      directMessagePanelOrigin = {
        panel,
        parent: panel.parentNode,
        nextSibling: panel.nextSibling
      };
    }

    // Keep the composer inside TikTok's React root so keyboard and send-button
    // events still reach TikTok's delegated handlers. Flatten the transformed,
    // clipped desktop ancestors instead of reparenting the live chat pane.
    let host = panel.parentElement;
    while (host && host !== document.body) {
      host.setAttribute("data-nima-dm-host", "true");
      host = host.parentElement;
    }

    panel.setAttribute("data-nima-dm-panel", "true");
    document.documentElement.setAttribute("data-nima-dm-active", "true");
    reportDirectMessageIdentity(panel, input);

    // Keep the chat within the part of the web view still visible above the
    // keyboard. A fixed 100vh desktop pane otherwise sits behind iOS input UI.
    const viewport = window.visualViewport;
    const viewportWidth = Math.floor(viewport?.width || document.documentElement.clientWidth || innerWidth);
    const viewportHeight = Math.floor(viewport?.height || innerHeight);
    const setImportant = (node, property, value) => {
      if (node.style.getPropertyValue(property) !== value
          || node.style.getPropertyPriority(property) !== "important") {
        node.style.setProperty(property, value, "important");
      }
    };
    setImportant(panel, "top", `${Math.floor(viewport?.offsetTop || 0)}px`);
    setImportant(panel, "height", `${viewportHeight}px`);
    setImportant(panel, "width", `${viewportWidth}px`);
    setImportant(panel, "max-width", `${viewportWidth}px`);

    const buttonCandidates = Array.from(panel.querySelectorAll(
      'button, [role="button"], [data-e2e*="send"]'
    ));
    let sendControl = buttonCandidates.find((node) => {
      const label = textOf(node);
      const e2e = (node.getAttribute("data-e2e") || "").toLowerCase();
      return label === "send" || label.includes("send message") || e2e.includes("send");
    });

    // TikTok's send arrow has no accessible label. Identify its clickable
    // wrapper by TikTok's pink fill instead of guessing from sibling order.
    if (!sendControl) {
      const isSendPink = (node) => {
        const samples = [node, ...Array.from(node.querySelectorAll("svg, path"))].slice(0, 12);
        return samples.some((sample) => {
          const style = getComputedStyle(sample);
          return [style.color, style.fill, style.stroke].some((value) => {
            const match = String(value || "").match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
            return match && Number(match[1]) >= 225
              && Number(match[2]) <= 95 && Number(match[3]) >= 65
              && Number(match[3]) <= 150;
          });
        });
      };
      sendControl = buttonCandidates.find((node) => {
        const rect = node.getBoundingClientRect();
        return !node.contains(input) && rect.width >= 16 && rect.width <= 140
          && rect.height >= 16 && rect.height <= 140 && isSendPink(node);
      });
      if (!sendControl) {
        const pinkGraphic = Array.from(panel.querySelectorAll("svg, path")).find(isSendPink);
        if (pinkGraphic) {
          let candidate = pinkGraphic;
          for (let depth = 0; candidate.parentElement && candidate !== panel && depth < 5;
              depth += 1, candidate = candidate.parentElement) {
            const parent = candidate.parentElement;
            const rect = parent.getBoundingClientRect();
            if (parent.matches('button, [role="button"]')) {
              sendControl = parent;
              break;
            }
            if (rect.width >= 24 && rect.width <= 140 && rect.height >= 24 && rect.height <= 140) {
              sendControl = parent;
            }
          }
        }
      }
    }
    let composer = null;
    let inputBranch = null;
    let sendBranch = null;

    if (sendControl) {
      // Use the lowest common ancestor whose direct children split the input
      // and send arrow. This avoids mistaking the emoji branch for Send.
      let ancestor = input.parentElement;
      for (let depth = 0; ancestor && ancestor !== panel && depth < 12;
          depth += 1, ancestor = ancestor.parentElement) {
        if (!ancestor.contains(sendControl)) continue;
        const children = Array.from(ancestor.children);
        const inputPart = children.find((child) => child === input || child.contains(input));
        const sendPart = children.find(
          (child) => child === sendControl || child.contains(sendControl)
        );
        if (!inputPart || !sendPart || inputPart === sendPart) continue;
        if (ancestor.getBoundingClientRect().height > 180) continue;
        composer = ancestor;
        inputBranch = inputPart;
        sendBranch = sendPart;
        break;
      }
    }

    if (composer && composer !== panel && inputBranch && sendBranch) {
      composer.setAttribute("data-nima-dm-composer", "true");
      inputBranch.setAttribute("data-nima-dm-input-branch", "true");
      sendBranch.setAttribute("data-nima-dm-send-branch", "true");
      sendControl?.setAttribute("data-nima-dm-send", "true");

      setImportant(composer, "width", `${viewportWidth}px`);
      setImportant(composer, "max-width", `${viewportWidth}px`);
    }
    if (input.getAttribute("data-nima-dm-input-listener") !== "true") {
      input.setAttribute("data-nima-dm-input-listener", "true");
      input.addEventListener("input", () => requestAnimationFrame(
        () => requestAnimationFrame(showSelectedDirectMessage)
      ));
    }
    return true;
  };

  const repairDirectMessages = () => {
    if (!pathOf(location.href).startsWith("/messages")) return;

    // Keep TikTok's live conversation rows as the tap targets. A native list
    // painted over the web view prevents TikTok from receiving a real tap.
    const rows = Array.from(document.querySelectorAll(
      '[data-e2e="dm-new-conversation-item"]'
    ));
    if (rows.length) {
      let list = rows[0].parentElement;
      while (list && list !== document.body && !rows.every((row) => list.contains(row))) {
        list = list.parentElement;
      }
      if (list && list !== document.body && !list.contains(directMessageInput())) {
        list.setAttribute("data-nima-dm-list", "true");
        let host = list.parentElement;
        while (host && host !== document.body) {
          host.setAttribute("data-nima-dm-list-host", "true");
          host = host.parentElement;
        }
      }
    }

    if (!document.getElementById("nima-dm-mobile-style")) {
      const style = document.createElement("style");
      style.id = "nima-dm-mobile-style";
      style.textContent = `
        :root { --nima-dm-surface: #fff; }
        @media (prefers-color-scheme: dark) {
          :root { --nima-dm-surface: #000; }
        }
        [data-e2e="dm-new-conversation-item"],
        [data-e2e="dm-new-conversation-item"] * {
          pointer-events: auto !important;
        }
        [data-nima-dm-list-host="true"] {
          transform: none !important;
          translate: none !important;
          overflow: visible !important;
          contain: none !important;
          clip: auto !important;
          clip-path: none !important;
          isolation: auto !important;
          z-index: 2147483643 !important;
        }
        [data-nima-dm-list="true"] {
          position: fixed !important;
          inset: 0 !important;
          width: 100vw !important;
          min-width: 0 !important;
          max-width: 100vw !important;
          height: 100vh !important;
          box-sizing: border-box !important;
          padding: 8px 0 24px !important;
          overflow-x: hidden !important;
          overflow-y: auto !important;
          z-index: 2147483644 !important;
          background: var(--nima-dm-surface) !important;
        }
        [data-nima-dm-list="true"] [data-index],
        [data-nima-dm-list="true"] [data-e2e="dm-new-conversation-item"] {
          width: 100% !important;
          min-width: 0 !important;
          max-width: 100% !important;
          box-sizing: border-box !important;
        }
        [data-nima-dm-list="true"] [data-e2e="dm-new-conversation-item"] {
          min-height: 72px !important;
          padding-left: 16px !important;
          padding-right: 16px !important;
        }
        html[data-nima-dm-active="true"] [data-nima-dm-list="true"] {
          display: none !important;
        }
        [data-nima-dm-host="true"] {
          transform: none !important;
          translate: none !important;
          overflow: visible !important;
          contain: none !important;
          clip: auto !important;
          clip-path: none !important;
        }
        [data-nima-dm-panel="true"] {
          position: fixed !important;
          inset: 0 !important;
          width: 100vw !important;
          height: 100vh !important;
          min-width: 0 !important;
          max-width: none !important;
          z-index: 2147483645 !important;
          background: var(--nima-dm-surface) !important;
          overflow-x: hidden !important;
        }
        html[data-nima-dm-active="true"],
        html[data-nima-dm-active="true"] body {
          overflow-x: hidden !important;
          max-width: 100vw !important;
        }
        [data-nima-dm-panel="true"] > *,
        [data-nima-dm-composer="true"] > * {
          min-width: 0 !important;
        }
        html[data-nima-dm-active="true"] [data-e2e="message-input"],
        html[data-nima-dm-active="true"] .public-DraftEditor-content {
          font-size: 16px !important;
        }
        [data-nima-dm-web-header="true"] {
          display: none !important;
        }
        [data-nima-dm-composer="true"] {
          display: flex !important;
          position: relative !important;
          height: auto !important;
          min-height: 56px !important;
          min-width: 0 !important;
          box-sizing: border-box !important;
          align-items: flex-end !important;
          gap: 8px !important;
          padding: 8px 12px !important;
          overflow: visible !important;
        }
        [data-nima-dm-input-branch="true"] {
          flex: 1 1 auto !important;
          width: auto !important;
          max-width: none !important;
          min-width: 0 !important;
          box-sizing: border-box !important;
          position: relative !important;
          inset: auto !important;
          overflow: auto !important;
        }
        [data-nima-dm-input-branch="true"] [data-e2e="message-input"],
        [data-nima-dm-input-branch="true"] .public-DraftEditor-content {
          display: block !important;
          width: 100% !important;
          min-width: 0 !important;
          max-width: 100% !important;
          min-height: 24px !important;
          max-height: 96px !important;
          overflow-y: auto !important;
          font-size: 16px !important;
        }
        [data-nima-dm-send-branch="true"] {
          display: flex !important;
          align-items: center !important;
          justify-content: center !important;
          flex: 0 0 48px !important;
          width: 48px !important;
          min-width: 48px !important;
          max-width: 48px !important;
          margin: 0 !important;
          position: relative !important;
          inset: auto !important;
          transform: none !important;
        }
        [data-nima-dm-send="true"] {
          display: flex !important;
          visibility: visible !important;
          flex: 0 0 auto !important;
          position: static !important;
          inset: auto !important;
          transform: none !important;
          margin: 0 !important;
        }
      `;
      (document.head || document.documentElement).appendChild(style);
    }

    // The native loading cover stays up until the live list has been moved
    // over the desktop page and its mobile layout rules are in place.
    if (!inboxReadyReported && window === window.top
        && document.querySelector('[data-nima-dm-list="true"]')
        && document.getElementById("nima-dm-mobile-style")) {
      inboxReadyReported = true;
      send({ event: "inboxReady" });
    }

    document.querySelectorAll("._TUXModal-wrapper, [role='dialog']").forEach((modal) => {
      const label = textOf(modal);
      if (!label.includes("passkey") && !label.includes("full app experience")) return;
      const dismiss = Array.from(modal.querySelectorAll("button, [role='button']"))
        .find((node) => ["not now", "maybe later", "close"].includes(textOf(node)));
      if (dismiss) dismiss.click();
    });

    if (directMessageSelectionRequested && directMessageInput()) {
      showSelectedDirectMessage();
    }
  };

  const directMessageItemFor = (target) => {
    if (!target || !target.closest || !pathOf(location.href).startsWith("/messages")) return null;
    const item = target.closest('[data-e2e="dm-new-conversation-item"]');
    if (item) return item;
    return target.closest("[data-index]")
      ?.querySelector('[data-e2e="dm-new-conversation-item"]') || null;
  };

  const rememberDirectMessageItem = (item) => {
    if (!item) return;
    const name = (item.innerText || "").split(/\n+/)
      .map((line) => line.trim()).find(Boolean) || "";
    const avatar = item.querySelector("img");
    pendingDirectMessageIdentity = {
      name,
      avatarURL: avatar?.currentSrc || avatar?.src || ""
    };
  };

  const searchInput = () => document.querySelector(
    "input[type='search'], input[placeholder*='Search' i]"
  );

  const repairSearchAppearance = () => {
    if (window !== window.top) return;
    const onSearch = pathOf(location.href).startsWith("/search");
    const hasSearchResults = onSearch && new URL(location.href).searchParams.has("q");
    const wasSearch = document.documentElement.hasAttribute("data-nima-search-surface");
    document.documentElement.toggleAttribute("data-nima-search-surface", onSearch);
    document.documentElement.toggleAttribute("data-nima-search-results", hasSearchResults);
    if (!onSearch) {
      if (wasSearch) {
        document.documentElement.removeAttribute("data-nima-search-light-content");
        document.querySelectorAll(
          "[data-nima-search-bg], [data-nima-search-color], [data-nima-search-border]"
        ).forEach((node) => {
          node.removeAttribute("data-nima-search-bg");
          node.removeAttribute("data-nima-search-color");
          node.removeAttribute("data-nima-search-border");
        });
      }
      return;
    }

    const input = searchInput();
    if (input) {
      // TikTok sometimes presents its search box as a generic text field.
      // Give WebKit the correct keyboard and AutoFill hints before focus.
      if (input.type === "text") input.type = "search";
      if (input.getAttribute("autocomplete") !== "off") {
        input.setAttribute("autocomplete", "off");
      }
      if (input.getAttribute("enterkeyhint") !== "search") {
        input.setAttribute("enterkeyhint", "search");
      }
    }

    if (!document.getElementById("nima-search-style")) {
      const style = document.createElement("style");
      style.id = "nima-search-style";
      style.textContent = `
        /* Desktop search results include a fixed side rail and its flex spacer. */
        html[data-nima-search-surface] [class*="DivSideNavPlaceholderContainer"],
        html[data-nima-search-surface] [class*="DivSideNavContainer"],
        html[data-nima-search-surface] [data-e2e="side-nav-shell"] {
          display: none !important;
          width: 0 !important;
          flex: 0 0 0 !important;
        }
        html[data-nima-search-results],
        html[data-nima-search-results] body {
          width: 100% !important;
          max-width: 100% !important;
          overflow-x: hidden !important;
        }
        html[data-nima-search-results] :is(main, [role="main"],
          [class*="DivMainContainer"], [class*="DivSearchContainer"],
          [class*="DivSearchResultContainer"]) {
          width: 100% !important;
          max-width: 100% !important;
          min-width: 0 !important;
          box-sizing: border-box !important;
        }
        html[data-nima-search-results] main {
          /* TikTok's desktop tab row is wider than the phone. Keep that
             overflow inside the tabs instead of scrolling the whole page. */
          overflow-x: hidden !important;
          overflow-y: auto !important;
        }
        html[data-nima-search-results] [class*="DivSearchTabBarContainer"] {
          width: 100% !important;
          max-width: 100% !important;
          min-width: 0 !important;
          overflow-x: auto !important;
          overflow-y: hidden !important;
        }
        @media (prefers-color-scheme: dark) {
          html[data-nima-search-surface][data-nima-search-light-content],
          html[data-nima-search-surface][data-nima-search-light-content] body {
            background-color: #000 !important;
            color-scheme: dark;
          }
          html[data-nima-search-surface][data-nima-search-light-content] [data-nima-search-bg="primary"] { background-color: #000 !important; }
          html[data-nima-search-surface][data-nima-search-light-content] [data-nima-search-bg="secondary"] { background-color: #202020 !important; }
          html[data-nima-search-surface][data-nima-search-light-content] [data-nima-search-color="primary"] { color: #ededed !important; }
          html[data-nima-search-surface][data-nima-search-light-content] [data-nima-search-color="secondary"] { color: #a0a0a0 !important; }
          html[data-nima-search-surface][data-nima-search-light-content] [data-nima-search-border] { border-color: #303030 !important; }
        }
      `;
      (document.head || document.documentElement).appendChild(style);
    }

    if (hasSearchResults) {
      const main = document.querySelector("main");
      if (main && !main.hasAttribute("data-nima-search-horizontal-lock")) {
        main.setAttribute("data-nima-search-horizontal-lock", "true");
        main.addEventListener("scroll", () => {
          if (document.documentElement.hasAttribute("data-nima-search-results")
              && main.scrollLeft !== 0) main.scrollLeft = 0;
        }, { passive: true });
      }
      if (main && main.scrollLeft !== 0) main.scrollLeft = 0;
    }

    if (!matchMedia("(prefers-color-scheme: dark)").matches) return;
    const toneOf = (value) => {
      const match = String(value || "").match(
        /^rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)$/
      );
      if (!match || Number(match[4] ?? 1) < 0.25) return null;
      const channels = match.slice(1, 4).map(Number);
      if (Math.max(...channels) - Math.min(...channels) > 32) return null;
      return channels.reduce((sum, channel) => sum + channel, 0) / 3;
    };
    if (!document.documentElement.hasAttribute("data-nima-search-light-content")) {
      const hasLightPanel = Array.from(document.querySelectorAll("html, body, main, [role='main'], body div"))
        .some((node) => {
          const rect = node.getBoundingClientRect();
          return rect.width >= innerWidth * 0.6 && rect.height >= 100
            && toneOf(getComputedStyle(node).backgroundColor) >= 225;
        });
      if (!hasLightPanel) return;
    }
    document.documentElement.setAttribute("data-nima-search-light-content", "true");
    document.querySelectorAll("body *").forEach((node) => {
      if (node.matches("img, video, canvas, svg, path, picture, iframe, script, style")) return;
      const computed = getComputedStyle(node);
      if (!node.hasAttribute("data-nima-search-bg")) {
        const background = toneOf(computed.backgroundColor);
        if (background !== null && background >= 225) {
          node.setAttribute("data-nima-search-bg", background >= 248 ? "primary" : "secondary");
        }
      }
      if (!node.hasAttribute("data-nima-search-color")) {
        const foreground = toneOf(computed.color);
        if (foreground !== null && foreground < 205) {
          node.setAttribute("data-nima-search-color", foreground < 75 ? "primary" : "secondary");
        }
      }
      if (!node.hasAttribute("data-nima-search-border")) {
        const border = toneOf(computed.borderTopColor);
        if (computed.borderTopWidth !== "0px" && border !== null && border >= 160) {
          node.setAttribute("data-nima-search-border", "true");
        }
      }
    });
  };

  const submitSearchThroughNima = () => {
    if (!pathOf(location.href).startsWith("/search")) return false;
    const query = (searchInput()?.value || "").trim();
    if (!query) return false;
    send({ event: "submitSearch", query });
    return true;
  };

  const isSearchSubmitTarget = (target) => {
    if (!target || !pathOf(location.href).startsWith("/search")) return false;
    const input = searchInput();
    const inputRect = input && input.getBoundingClientRect();
    if (!inputRect) return false;
    let node = target;
    for (let depth = 0; node && depth < 7; depth += 1, node = node.parentElement) {
      if (!node.getBoundingClientRect) continue;
      const rect = node.getBoundingClientRect();
      const besideInput = rect.left >= inputRect.right - 12
        && rect.top < inputRect.bottom + 12
        && rect.bottom > inputRect.top - 12;
      if (besideInput || textOf(node) === "search") return true;
    }
    return false;
  };

  const detectVideoOverlay = () => {
    if (locked() || !currentSurfaceAllowsVideo()) return;
    const video = Array.from(document.querySelectorAll("video")).find((candidate) => {
      if (!visible(candidate)) return false;
      const rect = candidate.getBoundingClientRect();
      return rect.width >= Math.min(220, innerWidth * 0.55)
        && rect.height >= Math.min(320, innerHeight * 0.42);
    });
    if (!video) return;
    const surface = video.closest("[role='dialog']") || video.closest("article") || video.parentElement;
    const link = surface && surface.querySelector("a[href*='/video/']");
    const url = link ? link.href : null;
    const overlay = video.closest("[role='dialog']")
      || (surface && getComputedStyle(surface).position === "fixed");
    if (!overlay) return;
    window.__nimaTikTokVideoOverlayOpen = true;
    if (url) window.__nimaTikTokGrantedVideoURL = url;
    send({ event: "videoActivated", url });
  };

  const applyVideoLock = () => {
    const shouldLock = locked();
    document.documentElement.style.setProperty("overscroll-behavior", shouldLock ? "none" : "auto", "important");
    document.body && document.body.style.setProperty("overscroll-behavior", shouldLock ? "none" : "auto", "important");
    document.querySelectorAll("[data-nima-video-lock='true']").forEach((node) => {
      if (!shouldLock) {
        node.style.removeProperty("touch-action");
        node.removeAttribute("data-nima-video-lock");
      }
    });
    if (!shouldLock) return;
    document.querySelectorAll("video").forEach((video) => {
      const surface = video.closest("[role='dialog']") || video.closest("article") || video.parentElement;
      if (!surface) return;
      surface.style.setProperty("touch-action", "pan-x", "important");
      surface.setAttribute("data-nima-video-lock", "true");
    });
  };

  addEventListener("message", (event) => {
    if (event.data?.nimaTikTokFeedStateRequest === true && window === window.top) {
      try {
        event.source?.postMessage({
          nimaTikTokFeedScrolling: feedScrollingEnabled
        }, "*");
      } catch (_) {}
      return;
    }
    if (typeof event.data?.nimaTikTokFeedScrolling === "boolean") {
      feedScrollingEnabled = event.data.nimaTikTokFeedScrolling;
      applyVideoLock();
    }
  });

  const reportHealth = () => {
    const forYouVisible = Array.from(document.querySelectorAll("a, button, [role='tab']"))
      .some((node) => visible(node) && textOf(node) === "for you");
    const key = forYouVisible ? "limited" : "healthy";
    if (key === lastHealth) return;
    lastHealth = key;
    if (!forYouVisible) send({ event: "health" });
  };

  const clean = () => {
    updateSurfaceMode(location.href);
    repairFriendsFeedLayout();
    repairFollowingFeedLayout();
    removeForYou();
    removeBlockedSurfaces();
    removeAppPrompts();
    hideNativeNavigation();
    removeEmptySearchDiscovery();
    repairSearchAppearance();
    repairNotificationInbox();
    repairDirectMessages();
    detectVideoOverlay();
    applyVideoLock();
    reportHealth();
    if (location.href !== lastLocation) {
      lastLocation = location.href;
      const payload = {
        event: "locationChanged",
        url: location.href,
        feedScrolling: feedScrollingEnabled
      };
      if (isVideoURL(location.href) && lastNotificationTapSource
          && performance.now() - lastNotificationTapAt < 4000) {
        payload.notificationTapSourceURL = lastNotificationTapSource;
        lastNotificationTapSource = null;
      }
      send(payload);
    }
  };

  document.addEventListener("click", (event) => {
    const control = event.target && event.target.closest
      && event.target.closest("a[href], button, [role='tab'], [role='button']");
    if (window === window.top && pathOf(location.href).startsWith("/inbox")
        && !["all activity", "likes", "comments", "mentions and tags", "followers",
          "follow requests"].includes(textOf(control))) {
      // Notification rows often navigate through React without an anchor URL.
      // Pair the next single-video route with this trusted tap only.
      lastNotificationTapSource = location.href;
      lastNotificationTapAt = performance.now();
      send({ event: "notificationTapped", sourceURL: location.href });
    }
    if (!nativeNavigationInProgress && control && textOf(control) === "inbox") {
      event.preventDefault();
      event.stopImmediatePropagation();
      send({ event: "openInbox" });
      return;
    }
    const directMessageItem = directMessageItemFor(event.target);
    if (directMessageItem) {
      lastDirectMessageClickItem = directMessageItem;
      lastDirectMessageClickAt = performance.now();
      rememberDirectMessageItem(directMessageItem);
      directMessageSelectionRequested = true;
      // Keep TikTok's trusted click intact. Once TikTok creates the actual
      // chat composer, move that conversation pane into the phone viewport.
      setTimeout(showSelectedDirectMessage, 420);
    }
    if (isSearchSubmitTarget(event.target) && submitSearchThroughNima()) {
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }
    const anchor = event.target && event.target.closest && event.target.closest("a[href]");
    if (!anchor) return;
    if (isForYou(anchor.href)) {
      event.preventDefault();
      event.stopImmediatePropagation();
      send({ event: "locationChanged", url: anchor.href });
      return;
    }
    if (isVideoURL(anchor.href) && currentSurfaceAllowsVideo()) {
      window.__nimaTikTokGrantedVideoURL = anchor.href;
      window.__nimaTikTokVideoOverlayOpen = true;
      send({ event: "videoActivated", url: anchor.href });
    }
  }, true);

  document.addEventListener("touchend", (event) => {
    const item = directMessageItemFor(event.target);
    if (!item || event.changedTouches?.length > 1) return;
    // Let WebKit deliver the trusted tap to TikTok. Only synthesize a click
    // if its desktop hover behavior swallowed that tap without a click event.
    rememberDirectMessageItem(item);
    directMessageSelectionRequested = true;
    const endedAt = performance.now();
    setTimeout(() => {
      if (!directMessageSelectionRequested || !item.isConnected) return;
      if (lastDirectMessageClickItem === item && lastDirectMessageClickAt >= endedAt) return;
      item.click();
    }, 450);
  }, { capture: true, passive: true });

  window.visualViewport?.addEventListener("resize", () => {
    if (document.documentElement.hasAttribute("data-nima-dm-active")) {
      requestAnimationFrame(showSelectedDirectMessage);
    }
  });

  document.addEventListener("submit", (event) => {
    if (!submitSearchThroughNima()) return;
    event.preventDefault();
    event.stopImmediatePropagation();
  }, true);

  document.addEventListener("touchstart", (event) => {
    touchStartY = event.touches && event.touches[0] ? event.touches[0].clientY : null;
  }, { capture: true, passive: true });
  document.addEventListener("touchmove", (event) => {
    if (!locked() || touchStartY == null || !event.touches || !event.touches[0]) return;
    if (Math.abs(event.touches[0].clientY - touchStartY) > 8) {
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  }, { capture: true, passive: false });
  document.addEventListener("wheel", (event) => {
    if (locked() && Math.abs(event.deltaY) > Math.abs(event.deltaX)) {
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  }, { capture: true, passive: false });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && (event.target === searchInput() || document.activeElement === searchInput())
        && submitSearchThroughNima()) {
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }
    if (locked() && ["ArrowUp", "ArrowDown", "PageUp", "PageDown", " "].includes(event.key)) {
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  }, true);

  const wrapHistory = (name) => {
    const original = history[name];
    history[name] = function () {
      const result = original.apply(this, arguments);
      queueMicrotask(clean);
      return result;
    };
  };
  wrapHistory("pushState");
  wrapHistory("replaceState");
  addEventListener("popstate", clean);

  window.__nimaTikTokConfigure = (configuration) => {
    window.__nimaTikTokMode = configuration.mode === "dm_only" ? "dm_only" : "clean";
    window.__nimaTikTokGrantedVideoURL = configuration.grantedVideoURL || null;
    window.__nimaTikTokVideoOverlayOpen = !!configuration.videoOverlayOpen;
    if (typeof configuration.feedScrollingEnabled === "boolean") {
      feedScrollingEnabled = configuration.feedScrollingEnabled;
    }
    broadcastFeedScrollingState();
    clean();
  };

  window.__nimaTikTokOpenInbox = () => {
    const candidates = Array.from(document.querySelectorAll(
      "a[href], button, [role='tab'], [role='button']"
    ));
    const target = candidates.find((node) => {
      const label = textOf(node);
      const path = pathOf(node.getAttribute && node.getAttribute("href"));
      return visible(node) && (label === "inbox" || label === "messages"
        || path.startsWith("/messages") || path.startsWith("/inbox"));
    });
    if (!target) return false;
    target.click();
    return true;
  };

  window.__nimaTikTokCloseDirectMessage = () => {
    if (!directMessageSelectionRequested
        && !document.querySelector('[data-nima-dm-panel="true"]')) return false;
    restoreDirectMessageList();
    return true;
  };

  window.__nimaTikTokOpenNativeSurface = (surface) => {
    const wanted = String(surface || "").trim().toLowerCase();
    if (!["following", "friends", "search", "inbox", "profile"].includes(wanted)) {
      return false;
    }
    feedScrollingEnabled = wanted === "following" || wanted === "friends";
    broadcastFeedScrollingState();
    const candidates = Array.from(document.querySelectorAll(
      "a[href], button, [role='tab'], [role='button']"
    ));
    const target = candidates.find((node) => textOf(node) === wanted);
    if (!target) return false;

    nativeNavigationInProgress = true;
    const href = target.href || (target.closest && target.closest("a[href]") || {}).href;
    if (href) {
      location.assign(href);
    } else {
      target.click();
    }
    queueMicrotask(() => { nativeNavigationInProgress = false; });
    return true;
  };

  const start = () => {
    clean();
    broadcastFeedScrollingState();
    new MutationObserver(() => queueMicrotask(clean)).observe(document.documentElement, {
      childList: true,
      characterData: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["href", "aria-label", "style", "class"]
    });
    setInterval(clean, 750);
  };
  if (document.documentElement) start();
  else addEventListener("DOMContentLoaded", start, { once: true });
})();
