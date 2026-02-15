"""
VeilHeuristicBlocker - mitmproxy addon for application-layer filtering.

Blocks Instagram Reels by killing large video responses from Instagram / its
CDNs before the body is downloaded (checked in responseheaders).
Blocks YouTube Shorts by dropping googlevideo.com requests whose query
string contains ctier=SH (Shorts content tier).
Passes through TLS for hosts with certificate pinning (e.g. Cursor).
"""
import os
from urllib.parse import parse_qs, urlparse
from mitmproxy import http, tls
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class VeilHeuristicBlocker:
    PASSTHROUGH_HOSTS = {".cursor.sh"}

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

    # --- YouTube Shorts blocking ---
    # googlevideo.com CDN domain where YouTube video chunks are served.
    YOUTUBE_CDN_DOMAIN = "googlevideo.com"
    # Content-tier query parameter values to block (SH = Shorts).
    YOUTUBE_BLOCKED_CTIERS = {
        s.strip().upper()
        for s in os.environ.get("YT_BLOCKED_CTIERS", "SH").split(",")
        if s.strip()
    }

    # ---- helpers ----

    def _is_googlevideo_domain(self, host: str) -> bool:
        """True for googlevideo.com or any subdomain."""
        if not host:
            return False
        h = host.lower()
        return h == self.YOUTUBE_CDN_DOMAIN or h.endswith("." + self.YOUTUBE_CDN_DOMAIN)

    def _has_blocked_ctier(self, url: str) -> bool:
        """True if the URL query string contains a blocked ctier value."""
        try:
            qs = parse_qs(urlparse(url).query)
            ctier_values = qs.get("ctier", [])
            return any(v.upper() in self.YOUTUBE_BLOCKED_CTIERS for v in ctier_values)
        except Exception:
            return False

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
        """Kill YouTube Shorts video requests before any data is fetched."""
        host = flow.request.pretty_host or ""
        if not self._is_googlevideo_domain(host):
            return
        if not self._has_blocked_ctier(flow.request.url):
            return

        logger.info(
            "block(ctier): YouTube Shorts from %s%s",
            host,
            (flow.request.path or "")[:80],
        )
        flow.kill()

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
        flow.kill()


addons = [VeilHeuristicBlocker()]
