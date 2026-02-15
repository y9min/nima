"""
VeilHeuristicBlocker - mitmproxy addon for application-layer filtering.

Blocks Instagram Reels by killing large video responses from Instagram / its
CDNs before the body is downloaded (checked in responseheaders).
Blocks YouTube video playback by dropping all googlevideo.com/videoplayback
requests (the CDN endpoint for all YouTube video streams).
Blocks Kalshi order placement by killing POST requests to the orders API.
Passes through TLS for hosts with certificate pinning (e.g. Cursor).
"""
import os
import re
import time
from mitmproxy import http, tls
import logging

from analytics import AnalyticsClient

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class VeilHeuristicBlocker:
    PASSTHROUGH_HOSTS = {".cursor.sh", ".icloud.com", ".apple.com"}

    def __init__(self):
        self.analytics = AnalyticsClient(
            flush_interval=float(os.environ.get("ANALYTICS_FLUSH_INTERVAL", "10")),
            flush_size=int(os.environ.get("ANALYTICS_FLUSH_SIZE", "50")),
        )

    # --- Content-attribute blocking ---
    # Instagram and its CDN domains (where media is served)
    INSTAGRAM_MEDIA_DOMAINS = {
        "instagram",        # keyword match (covers *.instagram.com, cdninstagram.com)
    }
    INSTAGRAM_CDN_DOMAINS = {
        "fbcdn.net",
        "fbsbx.com",
        "facebook.net",
    }

    # Block video responses larger than this from Instagram domains (bytes).
    # Reels are typically 2-15 MB; feed images are < 500 KB.
    # Default 500 KB — high enough for images, low enough to catch video.
    VIDEO_SIZE_THRESHOLD = int(os.environ.get("REELS_VIDEO_MAX_BYTES", 500_000))

    # Content-Types treated as video
    VIDEO_CONTENT_TYPES = {"video/mp4", "video/webm", "video/ogg", "video/quicktime"}

    # --- YouTube video blocking ---
    # googlevideo.com CDN domain where YouTube video chunks are served.
    YOUTUBE_CDN_DOMAIN = "googlevideo.com"
    # The path used for all YouTube video stream requests.
    YOUTUBE_VIDEOPLAYBACK_PATH = "/videoplayback"

    # --- Kalshi order blocking ---
    # Block POST requests to the Kalshi orders API to prevent placing bets.
    # Matches: /v1/users/{uuid}/orders and /trade-api/v2/portfolio/orders etc.
    KALSHI_DOMAIN = "kalshi.com"
    KALSHI_ORDERS_PATTERN = re.compile(r"/(?:v\d+/users/[^/]+/orders|trade-api/v\d+/portfolio/orders)")

    # ---- helpers ----

    def _is_googlevideo_domain(self, host: str) -> bool:
        """True for googlevideo.com or any subdomain."""
        if not host:
            return False
        h = host.lower()
        return h == self.YOUTUBE_CDN_DOMAIN or h.endswith("." + self.YOUTUBE_CDN_DOMAIN)

    def _is_videoplayback_request(self, flow: http.HTTPFlow) -> bool:
        """True if the request path is /videoplayback (YouTube video stream)."""
        path = flow.request.path or ""
        # path may include query string; check the path component only
        return path.split("?")[0] == self.YOUTUBE_VIDEOPLAYBACK_PATH

    def _is_kalshi_domain(self, host: str) -> bool:
        """True for kalshi.com or any subdomain (e.g. api.elections.kalshi.com)."""
        if not host:
            return False
        h = host.lower()
        return h == self.KALSHI_DOMAIN or h.endswith("." + self.KALSHI_DOMAIN)

    def _is_kalshi_order_post(self, flow: http.HTTPFlow) -> bool:
        """True if this is a POST to a Kalshi orders endpoint."""
        if flow.request.method.upper() != "POST":
            return False
        path = (flow.request.path or "").split("?")[0]
        return bool(self.KALSHI_ORDERS_PATTERN.search(path))

    def _is_instagram_domain(self, host: str) -> bool:
        """True for any Instagram or Instagram-CDN host."""
        if not host:
            return False
        h = host.lower()
        if any(kw in h for kw in self.INSTAGRAM_MEDIA_DOMAINS):
            return True
        return any(h == d or h.endswith("." + d) for d in self.INSTAGRAM_CDN_DOMAINS)

    def _is_large_video_response(self, flow: http.HTTPFlow) -> bool:
        """Check response headers for video content above the size threshold."""
        resp = flow.response
        if not resp or not resp.headers:
            return False

        content_type = (resp.headers.get("content-type", "") or "").lower().split(";")[0].strip()
        if content_type not in self.VIDEO_CONTENT_TYPES:
            return False

        try:
            content_length = int(resp.headers.get("content-length", "0"))
        except ValueError:
            content_length = 0

        return content_length > self.VIDEO_SIZE_THRESHOLD

    # ---- mitmproxy hooks ----

    def tls_clienthello(self, data: tls.ClientHelloData) -> None:
        """Skip TLS interception for hosts that pin certificates."""
        sni = data.client_hello.sni or ""
        if any(sni == h.lstrip(".") or sni.endswith(h) for h in self.PASSTHROUGH_HOSTS):
            logger.info("passthrough: TLS for %s", sni)
            data.ignore_connection = True

    def request(self, flow: http.HTTPFlow) -> None:
        """Kill blocked requests before any data is fetched."""
        host = flow.request.pretty_host or ""

        # Store request start time for duration tracking
        flow.metadata["_start_time"] = time.time()

        # YouTube video playback
        if self._is_googlevideo_domain(host) and self._is_videoplayback_request(flow):
            logger.info(
                "block(yt): YouTube video from %s%s",
                host,
                (flow.request.path or "")[:80],
            )
            self.analytics.record(flow, blocked=True, block_reason="youtube_video")
            flow.kill()
            return

        # Kalshi order placement
        if self._is_kalshi_domain(host) and self._is_kalshi_order_post(flow):
            logger.info(
                "block(kalshi): POST order to %s%s",
                host,
                (flow.request.path or "")[:80],
            )
            self.analytics.record(flow, blocked=True, block_reason="kalshi_order")
            flow.kill()
            return

    def responseheaders(self, flow: http.HTTPFlow) -> None:
        """Kill large video responses from Instagram CDNs before body downloads."""
        host = flow.request.pretty_host or ""
        if not self._is_instagram_domain(host):
            return
        if not self._is_large_video_response(flow):
            return

        content_length = flow.response.headers.get("content-length", "?")
        logger.info(
            "block(size): video %s bytes from %s%s",
            content_length,
            host,
            (flow.request.path or "")[:60],
        )
        try:
            bytes_out = int(content_length)
        except (ValueError, TypeError):
            bytes_out = 0
        self.analytics.record(flow, blocked=True, block_reason="instagram_video", bytes_out=bytes_out)
        flow.kill()

    def response(self, flow: http.HTTPFlow) -> None:
        """Record allowed (non-killed) traffic after response completes."""
        if flow.response is None:
            return

        start = flow.metadata.get("_start_time")
        duration_ms = int((time.time() - start) * 1000) if start else None

        bytes_in = len(flow.request.content) if flow.request.content else 0
        bytes_out = len(flow.response.content) if flow.response.content else 0

        self.analytics.record(
            flow,
            blocked=False,
            status_code=flow.response.status_code,
            bytes_in=bytes_in,
            bytes_out=bytes_out,
            duration_ms=duration_ms,
        )


addons = [VeilHeuristicBlocker()]
