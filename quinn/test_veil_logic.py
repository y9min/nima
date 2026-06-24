import ast
import base64
import json
import sys
import types
import unittest
from pathlib import Path
from types import SimpleNamespace


mitmproxy = types.ModuleType("mitmproxy")
mitmproxy.http = SimpleNamespace(HTTPFlow=object)
mitmproxy.tls = SimpleNamespace(ClientHelloData=object)
sys.modules.setdefault("mitmproxy", mitmproxy)

from veil_logic import VeilHeuristicBlocker


class FakeFlow:
    def __init__(self, host: str, path: str, method: str = "GET", query=None):
        self.request = SimpleNamespace(
            pretty_host=host,
            path=path,
            method=method,
            query=query or {},
        )
        self.killed = False

    def kill(self):
        self.killed = True


class VeilHeuristicBlockerTests(unittest.TestCase):
    def setUp(self):
        self.blocker = VeilHeuristicBlocker()

    def test_blocks_instagram_reel(self):
        payload = base64.b64encode(
            json.dumps({"vencode_tag": "ig-xpvds.clips.c2"}).encode()
        ).decode()
        flow = FakeFlow(
            "scontent.cdninstagram.com",
            "/video",
            query={"efg": payload},
        )

        self.blocker.request(flow)

        self.assertTrue(flow.killed)

    def test_blocks_youtube_short(self):
        flow = FakeFlow(
            "rr1---sn.googlevideo.com",
            "/videoplayback?ctier=sh",
            query={"ctier": "sh"},
        )

        self.blocker.request(flow)

        self.assertTrue(flow.killed)

    def test_blocks_kalshi_order(self):
        flow = FakeFlow(
            "api.elections.kalshi.com",
            "/trade-api/v2/portfolio/orders",
            method="POST",
        )

        self.blocker.request(flow)

        self.assertTrue(flow.killed)

    def test_has_no_analytics_import_or_response_hook(self):
        source = Path(__file__).with_name("veil_logic.py").read_text()
        tree = ast.parse(source)
        imported_modules = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imported_modules.update(alias.name for alias in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module:
                imported_modules.add(node.module)

        self.assertNotIn("analytics", imported_modules)
        self.assertFalse(hasattr(VeilHeuristicBlocker, "response"))
        self.assertFalse(hasattr(self.blocker, "analytics"))


if __name__ == "__main__":
    unittest.main()
