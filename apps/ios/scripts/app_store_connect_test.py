#!/usr/bin/env python3

import base64
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))

from app_store_connect import der_ecdsa_to_raw, iso_date, relationship_territory


class AppStoreConnectToolTests(unittest.TestCase):
    def test_der_signature_conversion(self):
        r = bytes.fromhex("80" + "11" * 31)
        s = bytes.fromhex("22" * 32)
        der = b"\x30\x45\x02\x21\x00" + r + b"\x02\x20" + s
        self.assertEqual(der_ecdsa_to_raw(der), r + s)

    def test_territory_from_price_point_id(self):
        encoded = base64.urlsafe_b64encode(
            json.dumps({"s": "123", "t": "GBR", "p": "42"}).encode()
        ).rstrip(b"=").decode()
        self.assertEqual(relationship_territory({"id": encoded}), "GBR")

    def test_iso_date(self):
        self.assertEqual(iso_date("2026-09-07"), "2026-09-07")


if __name__ == "__main__":
    unittest.main()
