#!/usr/bin/env python3
"""App Store Connect listing text, kept as files in git and pushed through Apple's API.

    python3 appstore/push.py check                             # the credentials work, and each app's Apple ID
    python3 appstore/push.py validate                          # every app's text against Apple's limits; no network
    python3 appstore/push.py push --app bigger-fish --dry-run   # what would change, field by field
    python3 appstore/push.py push --app bigger-fish             # push it (only the fields that differ)
    python3 appstore/push.py push --app bigger-fish --only promotional_text,description

The text lives in appstore/<app>/app/<locale>/<field>.txt, and the in-app purchase's display name and description in
appstore/<app>/iap/<folder>/<locale>/. A push writes to the version that's still editable (Prepare for Submission and
the like), so nothing goes public until that version is submitted and released.

Credentials come from the 1Password Environment "App Store Connect", mounted at ~/.appstoreconnect/.env (another path
with ASCC_ENV_FILE), or from the process environment: ASCC_KEY_ID, ASCC_ISSUER_ID, ASCC_PRIVATE_KEY (the contents of the
.p8), and ASCC_APP_ID_<APP> (each app's numeric Apple ID). Nothing secret is written to disk or printed. Talking to the
API needs the cryptography package (python3 -m pip install --user cryptography); validate needs nothing.

Adapted from a friend's App Store listing kit.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
API = "https://api.appstoreconnect.apple.com"

# Each app: where its Apple ID comes from, and its in-app purchases (folder under iap/ -> product ID).
APPS = {
    "bigger-fish": {"app_id_env": "ASCC_APP_ID_BIGGER_FISH",
                    "iap": {"allworlds": "com.kraigstrong.biggerfish.allworlds"}},
    "math-reef": {"app_id_env": "ASCC_APP_ID_MATH_REEF",
                  "iap": {"fullreef": "com.kraigstrong.mathreef.fullreef"}},
}

# Listing fields: file name -> (where App Store Connect keeps it, its attribute, character limit). Version
# localizations hold what can change with each version; app info localizations hold the name and subtitle.
FIELDS = {
    "name": ("info", "name", 30),
    "subtitle": ("info", "subtitle", 30),
    "privacy_policy_url": ("info", "privacyPolicyUrl", 255),
    "promotional_text": ("version", "promotionalText", 170),
    "description": ("version", "description", 4000),
    "keywords": ("version", "keywords", 100),
    "release_notes": ("version", "whatsNew", 4000),
    "support_url": ("version", "supportUrl", 255),
    "marketing_url": ("version", "marketingUrl", 255),
}
REQUIRED = ["name", "subtitle", "description", "keywords", "support_url", "privacy_policy_url"]
IAP_LIMITS = {"name": 30, "description": 45}
# An app's first version has no What's New, so release_notes.txt is left out until there's a second.
EDITABLE_STATES = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED",
                   "WAITING_FOR_REVIEW", "INVALID_BINARY"}


# --------------------------------------------------------------------------------------------------------------------
# The files

def read(path: Path) -> str | None:
    """A field's text, without the file's final newline."""
    if not path.exists():
        return None
    text = path.read_text(encoding="utf-8")
    return text[:-1] if text.endswith("\n") else text


def locales(app: str) -> list[str]:
    folder = HERE / app / "app"
    return sorted(p.name for p in folder.iterdir() if p.is_dir()) if folder.exists() else []


def listing(app: str, locale: str) -> dict[str, str]:
    base = HERE / app / "app" / locale
    return {name: text for name in FIELDS if (text := read(base / f"{name}.txt")) is not None}


def purchases(app: str, locale: str) -> dict[str, dict[str, str]]:
    out = {}
    for folder in APPS[app]["iap"]:
        base = HERE / app / "iap" / folder / locale
        fields = {name: text for name in IAP_LIMITS if (text := read(base / f"{name}.txt")) is not None}
        if fields:
            out[folder] = fields
    return out


def problems(app: str, locale: str) -> list[str]:
    """Everything wrong with one locale's text, by Apple's limits and a few house rules."""
    found = []
    text = listing(app, locale)
    for name in REQUIRED:
        if name not in text:
            found.append(f"{name}.txt is missing")
    for name, value in text.items():
        limit = FIELDS[name][2]
        if len(value) > limit:
            found.append(f"{name}: {len(value)} characters, over the limit of {limit}")
        if name.endswith("_url") and not value.startswith("https://"):
            found.append(f"{name}: not an https:// link")
    keywords = text.get("keywords", "")
    if ", " in keywords:
        found.append("keywords: a space after a comma wastes a character")
    # Words in the name and subtitle are already searched; repeating them in keywords wastes room.
    named = set(re.findall(r"[a-z]+", (text.get("name", "") + " " + text.get("subtitle", "")).lower()))
    repeats = [k for k in keywords.split(",") if k and set(re.findall(r"[a-z]+", k.lower())) <= named]
    if repeats:
        found.append(f"keywords: already in the name or subtitle: {', '.join(repeats)}")
    for folder, fields in purchases(app, locale).items():
        for name, value in fields.items():
            if len(value) > IAP_LIMITS[name]:
                found.append(f"iap/{folder} {name}: {len(value)} characters, over the limit of {IAP_LIMITS[name]}")
    return found


def validate(apps: list[str]) -> int:
    bad = 0
    for app in apps:
        for locale in locales(app):
            found = problems(app, locale)
            sizes = ", ".join(f"{name} {len(value)}/{FIELDS[name][2]}" for name, value in listing(app, locale).items())
            print(f"{app} {locale}: {'ok' if not found else 'NOT OK'} ({sizes})")
            for problem in found:
                print(f"  - {problem}")
            bad += len(found)
    return 1 if bad else 0


# --------------------------------------------------------------------------------------------------------------------
# Credentials and the API

def load_credentials() -> None:
    """Fills the environment from the mounted 1Password Environment, without overriding what's already set. The mount
    is a pipe 1Password feeds when it's read, so it's read once, here, and never copied anywhere."""
    path = Path(os.path.expanduser(os.environ.get("ASCC_ENV_FILE", "~/.appstoreconnect/.env")))
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    for key, value in re.findall(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*("(?:[^"\\]|\\.)*"|\'[^\']*\'|[^\n]*)', text, re.M):
        if value[:1] in "\"'" and value[-1:] == value[:1]:
            value = value[1:-1]
        os.environ.setdefault(key, value)


def pem(raw: str) -> bytes:
    """The private key as PEM, however it was pasted: real line breaks, literal \\n, or all on one line."""
    text = raw.strip().strip("\"'").replace("\\n", "\n")
    match = re.match(r"(-----BEGIN [A-Z ]+-----)\s*(.+?)\s*(-----END [A-Z ]+-----)", text, re.S)
    if not match:
        raise SystemExit("ASCC_PRIVATE_KEY doesn't look like the .p8's contents (no BEGIN/END PRIVATE KEY lines)")
    body = re.sub(r"\s+", "", match.group(2))
    lines = [body[i:i + 64] for i in range(0, len(body), 64)]
    return "\n".join([match.group(1), *lines, match.group(3), ""]).encode()


def token() -> str:
    """A signed token for the API, good for 19 minutes (Apple allows 20)."""
    missing = [k for k in ("ASCC_KEY_ID", "ASCC_ISSUER_ID", "ASCC_PRIVATE_KEY") if not os.environ.get(k)]
    if missing:
        raise SystemExit(f"missing {', '.join(missing)}: add them to the 1Password Environment \"App Store Connect\"")
    try:
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
    except ImportError:
        raise SystemExit("talking to App Store Connect needs cryptography: python3 -m pip install --user cryptography")

    def b64(data: bytes) -> str:
        return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

    now = int(time.time())
    header = {"alg": "ES256", "kid": os.environ["ASCC_KEY_ID"], "typ": "JWT"}
    claims = {"iss": os.environ["ASCC_ISSUER_ID"], "iat": now, "exp": now + 19 * 60, "aud": "appstoreconnect-v1"}
    message = f"{b64(json.dumps(header).encode())}.{b64(json.dumps(claims).encode())}".encode()
    key = serialization.load_pem_private_key(pem(os.environ["ASCC_PRIVATE_KEY"]), password=None)
    r, s = decode_dss_signature(key.sign(message, ec.ECDSA(hashes.SHA256())))
    return f"{message.decode()}.{b64(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))}"


class Client:
    def __init__(self) -> None:
        self.auth = f"Bearer {token()}"

    def call(self, method: str, path: str, body: dict | None = None) -> dict:
        request = urllib.request.Request(f"{API}{path}", method=method,
                                         data=json.dumps(body).encode() if body is not None else None,
                                         headers={"Authorization": self.auth, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                text = response.read().decode()
        except urllib.error.HTTPError as error:
            raise RuntimeError(f"{method} {path}: {error.code} {error.read().decode()[:500]}") from None
        return json.loads(text) if text else {}

    def get(self, path: str) -> list[dict]:
        return self.call("GET", path).get("data", [])


def upsert(client: Client, kind: str, existing: dict | None, attrs: dict, parent: tuple[str, str, str],
           locale: str, dry_run: bool, label: str) -> bool:
    """Changes only the attributes that differ from what App Store Connect has; creates the localization if needed."""
    current = existing.get("attributes", {}) if existing else {}
    changed = {k: v for k, v in attrs.items() if (current.get(k) or "") != v}
    for k in attrs:
        print(f"  {label}.{k}: {'changes' if k in changed else 'same'}"
              + (f" ({len(current.get(k) or '')} -> {len(attrs[k])} characters)" if k in changed else ""))
    if not changed or dry_run:
        return bool(changed)
    if existing:
        client.call("PATCH", f"/v1/{kind}/{existing['id']}",
                    {"data": {"type": kind, "id": existing["id"], "attributes": changed}})
    else:
        relationship, parent_type, parent_id = parent
        client.call("POST", f"/v1/{kind}", {"data": {"type": kind, "attributes": {**changed, "locale": locale},
                                                     "relationships": {relationship: {"data": {"type": parent_type,
                                                                                               "id": parent_id}}}}})
    return True


def push(app: str, only: set[str] | None, dry_run: bool) -> int:
    if validate([app]):
        print("Fix the text before pushing.")
        return 1
    load_credentials()
    app_id = os.environ.get(APPS[app]["app_id_env"])
    if not app_id:
        raise SystemExit(f"missing {APPS[app]['app_id_env']} (the app's numeric Apple ID) in the 1Password Environment")
    client = Client()
    versions = [v for v in client.get(f"/v1/apps/{app_id}/appStoreVersions?limit=50")
                if v["attributes"].get("appStoreState") in EDITABLE_STATES]
    if not versions:
        raise SystemExit("no editable version: create the next version in App Store Connect first")
    version = versions[0]
    infos = client.get(f"/v1/apps/{app_id}/appInfos")
    info = next((i for i in infos if i["attributes"].get("appStoreState") in EDITABLE_STATES
                 or i["attributes"].get("state") in EDITABLE_STATES), infos[0] if len(infos) == 1 else None)
    print(f"{app}: version {version['attributes'].get('versionString')} ({version['attributes'].get('appStoreState')})"
          + (" — dry run, nothing is written" if dry_run else ""))
    version_locs = {l["attributes"]["locale"]: l
                    for l in client.get(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations?limit=200")}
    info_locs = {l["attributes"]["locale"]: l
                 for l in client.get(f"/v1/appInfos/{info['id']}/appInfoLocalizations?limit=200")} if info else {}
    changes = 0
    for locale in locales(app):
        print(f"[{locale}]")
        text = {k: v for k, v in listing(app, locale).items() if only is None or k in only}
        by_place = {"version": {}, "info": {}}
        for name, value in text.items():
            place, attribute, _ = FIELDS[name]
            by_place[place][attribute] = value
        if by_place["version"]:
            changes += upsert(client, "appStoreVersionLocalizations", version_locs.get(locale), by_place["version"],
                              ("appStoreVersion", "appStoreVersions", version["id"]), locale, dry_run, "listing")
        if by_place["info"]:
            if info is None:
                print("  name, subtitle, privacy policy: no editable app info, skipped")
            else:
                changes += upsert(client, "appInfoLocalizations", info_locs.get(locale), by_place["info"],
                                  ("appInfo", "appInfos", info["id"]), locale, dry_run, "app info")
        if only is None or "iap" in only:
            for folder, fields in purchases(app, locale).items():
                product_id = APPS[app]["iap"][folder]
                found = client.get(f"/v1/apps/{app_id}/inAppPurchasesV2?filter[productId]={product_id}&limit=1")
                if not found:
                    print(f"  iap {folder}: {product_id} isn't in App Store Connect yet, skipped")
                    continue
                purchase = found[0]["id"]
                locs = {l["attributes"]["locale"]: l
                        for l in client.get(f"/v2/inAppPurchases/{purchase}/inAppPurchaseLocalizations?limit=50")}
                changes += upsert(client, "inAppPurchaseLocalizations", locs.get(locale), fields,
                                  ("inAppPurchaseV2", "inAppPurchases", purchase), locale, dry_run, f"iap {folder}")
    print(f"{changes} localization{'' if changes == 1 else 's'} {'would change' if dry_run else 'changed'}.")
    return 0


def check() -> int:
    """Whether the credentials work, printing nothing secret: the key loads, and Apple answers with your apps."""
    load_credentials()
    names = ["ASCC_KEY_ID", "ASCC_ISSUER_ID", "ASCC_PRIVATE_KEY"] + [a["app_id_env"] for a in APPS.values()]
    for name in names:
        print(f"{name}: {'set' if os.environ.get(name) else 'missing'}")
    if not os.environ.get("ASCC_PRIVATE_KEY"):
        return 1
    try:
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric import ec
    except ImportError:
        raise SystemExit("checking the key needs cryptography: python3 -m pip install --user cryptography")
    try:
        key = serialization.load_pem_private_key(pem(os.environ["ASCC_PRIVATE_KEY"]), password=None)
    except ValueError:
        print("ASCC_PRIVATE_KEY doesn't load as a private key: paste the whole .p8, BEGIN and END lines included")
        return 1
    good = isinstance(key, ec.EllipticCurvePrivateKey) and key.curve.name == "secp256r1"
    print(f"private key: {'loads, an EC P-256 key as Apple issues' if good else 'loads, but it is not an EC P-256 key'}")
    if not (os.environ.get("ASCC_KEY_ID") and os.environ.get("ASCC_ISSUER_ID")):
        print("Add ASCC_KEY_ID and ASCC_ISSUER_ID (App Store Connect > Users and Access > Integrations) to talk to Apple.")
        return 0 if good else 1
    try:
        apps = Client().get("/v1/apps?limit=50&fields[apps]=name,bundleId")
    except RuntimeError as error:
        print(f"Apple said no: {error}")
        return 1
    print("Apple answered. Your apps (the number is each one's ASCC_APP_ID_...):")
    for app in apps:
        print(f"  {app['id']}  {app['attributes']['name']}  ({app['attributes']['bundleId']})")
    return 0 if good else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check", help="whether the credentials work, and each app's Apple ID; prints nothing secret")
    checks = sub.add_parser("validate", help="check every app's text against Apple's limits; no network")
    checks.add_argument("--app", choices=APPS)
    send = sub.add_parser("push", help="push an app's text to its editable version")
    send.add_argument("--app", choices=APPS, required=True)
    send.add_argument("--only", help="comma-separated fields to push (file names, or iap)")
    send.add_argument("--dry-run", action="store_true", help="show what would change; write nothing")
    args = parser.parse_args()
    if args.command == "check":
        return check()
    if args.command == "validate":
        return validate([args.app] if args.app else [a for a in APPS if (HERE / a).exists()])
    only = set(args.only.split(",")) if args.only else None
    if only and only - set(FIELDS) - {"iap"}:
        raise SystemExit(f"unknown fields: {', '.join(sorted(only - set(FIELDS) - {'iap'}))}")
    try:
        return push(args.app, only, args.dry_run)
    except RuntimeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
