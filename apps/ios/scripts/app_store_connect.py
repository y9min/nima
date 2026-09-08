#!/usr/bin/env python3
"""Small, dependency-free App Store Connect release tool for Nima."""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from decimal import Decimal, InvalidOperation
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urljoin
from urllib.request import Request, urlopen


API_ROOT = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "so.nima.app"
APPLE_ID = "6790122342"
CONFIRM_PRICE = "SET_PRICE"


class AscError(RuntimeError):
    pass


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def der_ecdsa_to_raw(signature: bytes, component_size: int = 32) -> bytes:
    """Convert OpenSSL's DER ECDSA signature to the raw R||S JWT form."""

    def read_length(data: bytes, offset: int) -> tuple[int, int]:
        if offset >= len(data):
            raise AscError("Invalid ECDSA signature returned by OpenSSL")
        first = data[offset]
        offset += 1
        if first < 0x80:
            return first, offset
        count = first & 0x7F
        if count == 0 or count > 4 or offset + count > len(data):
            raise AscError("Invalid ECDSA signature length")
        return int.from_bytes(data[offset : offset + count], "big"), offset + count

    if not signature or signature[0] != 0x30:
        raise AscError("OpenSSL did not return a DER ECDSA signature")
    sequence_length, offset = read_length(signature, 1)
    if offset + sequence_length != len(signature):
        raise AscError("Invalid ECDSA signature sequence")

    values: list[bytes] = []
    for _ in range(2):
        if offset >= len(signature) or signature[offset] != 0x02:
            raise AscError("Invalid ECDSA signature integer")
        integer_length, offset = read_length(signature, offset + 1)
        value = signature[offset : offset + integer_length]
        offset += integer_length
        value = value.lstrip(b"\x00")
        if len(value) > component_size:
            raise AscError("ECDSA signature component is too large")
        values.append(value.rjust(component_size, b"\x00"))
    return b"".join(values)


class Credentials:
    def __init__(self, key_id: str, issuer_id: str, private_key: Path):
        self.key_id = key_id
        self.issuer_id = issuer_id
        self.private_key = private_key

    @classmethod
    def from_environment(cls) -> "Credentials":
        key_id = os.getenv("APP_STORE_CONNECT_KEY_ID", "").strip()
        issuer_id = os.getenv("APP_STORE_CONNECT_ISSUER_ID", "").strip()
        key_path = os.getenv("APP_STORE_CONNECT_PRIVATE_KEY_PATH", "").strip()
        missing = [
            name
            for name, value in (
                ("APP_STORE_CONNECT_KEY_ID", key_id),
                ("APP_STORE_CONNECT_ISSUER_ID", issuer_id),
                ("APP_STORE_CONNECT_PRIVATE_KEY_PATH", key_path),
            )
            if not value
        ]
        if missing:
            raise AscError("Missing environment variable(s): " + ", ".join(missing))
        if not re.fullmatch(r"[A-Z0-9]{8,20}", key_id):
            raise AscError("APP_STORE_CONNECT_KEY_ID has an unexpected format")
        if not re.fullmatch(r"[0-9a-fA-F-]{36}", issuer_id):
            raise AscError("APP_STORE_CONNECT_ISSUER_ID must be a UUID")
        private_key = Path(key_path).expanduser().resolve()
        if not private_key.is_file():
            raise AscError(f"Private key does not exist: {private_key}")
        if private_key.suffix != ".p8":
            raise AscError("The App Store Connect private key must be a .p8 file")
        if "PRIVATE KEY" not in private_key.read_text(encoding="utf-8", errors="ignore"):
            raise AscError("The .p8 file does not look like a PEM private key")
        return cls(key_id, issuer_id, private_key)

    def jwt(self) -> str:
        now = int(dt.datetime.now(dt.timezone.utc).timestamp())
        header = {"alg": "ES256", "kid": self.key_id, "typ": "JWT"}
        payload = {
            "iss": self.issuer_id,
            "iat": now,
            "exp": now + 15 * 60,
            "aud": "appstoreconnect-v1",
        }
        signing_input = ".".join(
            b64url(json.dumps(value, separators=(",", ":")).encode("utf-8"))
            for value in (header, payload)
        )
        result = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", str(self.private_key)],
            input=signing_input.encode("ascii"),
            capture_output=True,
            check=False,
        )
        if result.returncode != 0:
            message = result.stderr.decode("utf-8", errors="replace").strip()
            raise AscError(f"Could not sign App Store Connect token: {message}")
        return signing_input + "." + b64url(der_ecdsa_to_raw(result.stdout))


class Client:
    def __init__(self, credentials: Credentials):
        self.credentials = credentials

    def request(
        self, method: str, path_or_url: str, body: dict[str, Any] | None = None
    ) -> dict[str, Any]:
        url = (
            path_or_url
            if path_or_url.startswith("https://")
            else urljoin(API_ROOT, path_or_url)
        )
        payload = None if body is None else json.dumps(body).encode("utf-8")
        request = Request(
            url,
            data=payload,
            method=method,
            headers={
                "Authorization": f"Bearer {self.credentials.jwt()}",
                "Accept": "application/json",
                "Content-Type": "application/json",
            },
        )
        try:
            with urlopen(request, timeout=60) as response:
                content = response.read()
                return json.loads(content) if content else {}
        except HTTPError as error:
            content = error.read().decode("utf-8", errors="replace")
            try:
                details = json.loads(content).get("errors", [])
                message = "; ".join(
                    f"{item.get('status', error.code)} {item.get('title', 'Error')}: "
                    f"{item.get('detail', '')}" for item in details
                )
            except json.JSONDecodeError:
                message = content
            raise AscError(f"App Store Connect request failed: {message or error.reason}") from error
        except URLError as error:
            raise AscError(f"Could not reach App Store Connect: {error.reason}") from error

    def get_all(self, path: str) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
        data: list[dict[str, Any]] = []
        included: list[dict[str, Any]] = []
        next_url: str | None = path
        while next_url:
            response = self.request("GET", next_url)
            data.extend(response.get("data", []))
            included.extend(response.get("included", []))
            next_url = response.get("links", {}).get("next")
        return data, included


def find_subscription(client: Client, product_id: str) -> dict[str, Any]:
    groups, _ = client.get_all(
        f"/v1/apps/{APPLE_ID}/subscriptionGroups?" + urlencode({"limit": "200"})
    )
    matches: list[dict[str, Any]] = []
    for group in groups:
        subscriptions, _ = client.get_all(
            f"/v1/subscriptionGroups/{group['id']}/subscriptions?"
            + urlencode({"limit": "200"})
        )
        matches.extend(
            item
            for item in subscriptions
            if item.get("attributes", {}).get("productId") == product_id
        )
    if len(matches) != 1:
        raise AscError(
            f"Expected one subscription with product ID {product_id!r}; found {len(matches)}"
        )
    return matches[0]


def price_points(client: Client, subscription_id: str, territory: str) -> list[dict[str, Any]]:
    params = urlencode({"filter[territory]": territory, "limit": "200"})
    points, _ = client.get_all(
        f"/v1/subscriptions/{subscription_id}/pricePoints?{params}"
    )
    return points


def find_price_point(
    client: Client, subscription_id: str, territory: str, customer_price: str
) -> dict[str, Any]:
    try:
        wanted = Decimal(customer_price)
    except InvalidOperation as error:
        raise AscError(f"Invalid customer price: {customer_price}") from error
    matches = [
        point
        for point in price_points(client, subscription_id, territory)
        if Decimal(point["attributes"]["customerPrice"]) == wanted
    ]
    if len(matches) != 1:
        raise AscError(
            f"Price {wanted} is not a unique Apple price point for {territory}; "
            "run list-prices to see valid values"
        )
    return matches[0]


def relationship_territory(price_point: dict[str, Any]) -> str:
    try:
        encoded = price_point["id"].split(".")[0]
        padding = "=" * (-len(encoded) % 4)
        decoded = json.loads(base64.urlsafe_b64decode(encoded + padding))
        return decoded["t"]
    except (KeyError, ValueError, json.JSONDecodeError):
        return "unknown"


def command_doctor(client: Client, credentials: Credentials, _: argparse.Namespace) -> None:
    mode = credentials.private_key.stat().st_mode & 0o777
    apps, _ = client.get_all(
        "/v1/apps?" + urlencode({"filter[bundleId]": BUNDLE_ID, "limit": "2"})
    )
    if not any(item.get("id") == APPLE_ID for item in apps):
        raise AscError(f"Credentials work, but cannot access Nima ({BUNDLE_ID})")
    print(f"Connected to App Store Connect for {BUNDLE_ID} ({APPLE_ID}).")
    if mode & 0o077:
        print(
            f"Warning: {credentials.private_key} has permissions {mode:o}; "
            "use chmod 600 to restrict it."
        )
    else:
        print("Private-key file permissions are restricted.")


def command_list_prices(client: Client, _: Credentials, args: argparse.Namespace) -> None:
    subscription = find_subscription(client, args.product_id)
    points = price_points(client, subscription["id"], args.territory)
    print(f"Valid {args.territory} customer prices for {args.product_id}:")
    for point in points:
        attributes = point["attributes"]
        print(
            f"  {attributes['customerPrice']} "
            f"(proceeds {attributes.get('proceeds', 'unknown')})"
        )


def command_set_price(client: Client, _: Credentials, args: argparse.Namespace) -> None:
    subscription = find_subscription(client, args.product_id)
    base_point = find_price_point(
        client, subscription["id"], args.territory, args.customer_price
    )
    points = [base_point]
    if args.equalize_all:
        params = urlencode({"limit": "200"})
        points, _ = client.get_all(
            f"/v1/subscriptionPricePoints/{base_point['id']}/equalizations?{params}"
        )
        if not any(point["id"] == base_point["id"] for point in points):
            points.append(base_point)

    print(
        f"Price plan: {args.product_id} -> {args.customer_price} in {args.territory}; "
        f"{len(points)} territor{'y' if len(points) == 1 else 'ies'}; "
        f"starts {args.start_date}; preserve existing price: {args.preserve_current_price}."
    )
    if args.confirm != CONFIRM_PRICE:
        print(f"Preview only. Re-run with --confirm {CONFIRM_PRICE} to apply.")
        return

    failures: list[str] = []
    for index, point in enumerate(points, start=1):
        body = {
            "data": {
                "type": "subscriptionPrices",
                "attributes": {
                    "startDate": args.start_date,
                    "preserveCurrentPrice": args.preserve_current_price,
                },
                "relationships": {
                    "subscription": {
                        "data": {"type": "subscriptions", "id": subscription["id"]}
                    },
                    "subscriptionPricePoint": {
                        "data": {"type": "subscriptionPricePoints", "id": point["id"]}
                    },
                },
            }
        }
        territory = relationship_territory(point)
        try:
            client.request("POST", "/v1/subscriptionPrices", body)
            print(f"[{index}/{len(points)}] Scheduled {territory}")
        except AscError as error:
            failures.append(f"{territory}: {error}")
            print(f"[{index}/{len(points)}] Failed {territory}", file=sys.stderr)
    if failures:
        raise AscError(
            f"{len(failures)} territory update(s) failed after partial application:\n"
            + "\n".join(failures)
        )
    print("Subscription price schedule applied.")


def command_upload(_: Client, credentials: Credentials, args: argparse.Namespace) -> None:
    ipa = Path(args.ipa).expanduser().resolve()
    if not ipa.is_file() or ipa.suffix.lower() != ".ipa":
        raise AscError(f"IPA does not exist or is not an .ipa file: {ipa}")
    operation = "--validate-app" if args.validate_only else "--upload-package"
    command = [
        "xcrun",
        "altool",
        operation,
        str(ipa),
        "--api-key",
        credentials.key_id,
        "--api-issuer",
        credentials.issuer_id,
        "--p8-file-path",
        str(credentials.private_key),
        "--output-format",
        "json",
        "--show-progress",
    ]
    if args.wait and not args.validate_only:
        command.append("--wait")
    result = subprocess.run(command, check=False)
    if result.returncode != 0:
        raise AscError("Apple build validation/upload failed; see the output above")


def iso_date(value: str) -> str:
    try:
        return dt.date.fromisoformat(value).isoformat()
    except ValueError as error:
        raise argparse.ArgumentTypeError("use YYYY-MM-DD") from error


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Secure App Store Connect build and subscription-price automation"
    )
    subcommands = result.add_subparsers(dest="command", required=True)

    doctor = subcommands.add_parser("doctor", help="verify credentials and Nima access")
    doctor.set_defaults(handler=command_doctor)

    prices = subcommands.add_parser("list-prices", help="list valid Apple price points")
    prices.add_argument("--product-id", required=True)
    prices.add_argument("--territory", default="GBR", type=str.upper)
    prices.set_defaults(handler=command_list_prices)

    set_price = subcommands.add_parser("set-price", help="preview or apply a price schedule")
    set_price.add_argument("--product-id", required=True)
    set_price.add_argument("--customer-price", required=True)
    set_price.add_argument("--territory", default="GBR", type=str.upper)
    set_price.add_argument("--start-date", required=True, type=iso_date)
    set_price.add_argument(
        "--equalize-all",
        action="store_true",
        help="apply Apple's equivalent price point in every territory",
    )
    set_price.add_argument(
        "--preserve-current-price",
        action="store_true",
        help="keep the old price for existing subscribers where Apple permits it",
    )
    set_price.add_argument("--confirm", help=f"must be exactly {CONFIRM_PRICE} to write")
    set_price.set_defaults(handler=command_set_price)

    upload = subcommands.add_parser("upload-build", help="validate or upload an exported IPA")
    upload.add_argument("--ipa", required=True)
    upload.add_argument("--validate-only", action="store_true")
    upload.add_argument("--wait", action="store_true", help="wait for Apple processing")
    upload.set_defaults(handler=command_upload)
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        credentials = Credentials.from_environment()
        args.handler(Client(credentials), credentials, args)
        return 0
    except (AscError, FileNotFoundError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
