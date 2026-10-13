#!/usr/bin/env python3
"""App Store Connect listing text, kept as files in git and pushed through Apple's API.

    python3 appstore/push.py check                             # the credentials work, and each app's Apple ID
    python3 appstore/push.py validate                          # every app's text against Apple's limits; no network
    python3 appstore/push.py push --app bigger-fish --dry-run   # what would change, field by field
    python3 appstore/push.py push --app bigger-fish             # push it (only the fields that differ)
    python3 appstore/push.py push --app bigger-fish --only promotional_text,description
    python3 appstore/push.py media --app bigger-fish --screenshots DIR [DIR ...] --creative FILE --dry-run

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
import hashlib
import json
import os
import re
import struct
import sys
import time
import urllib.error
import urllib.parse
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
EDITABLE_STATES = {"PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED",
                   "WAITING_FOR_REVIEW", "INVALID_BINARY"}
# A version in a draft submission (Ready for Review) keeps its text editable but not its images and videos.
MEDIA_EDITABLE_STATES = EDITABLE_STATES - {"READY_FOR_REVIEW"}


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


def measure(name: str, value: str) -> int:
    """A field's length as Apple limits it: keywords in UTF-8 bytes, everything else in characters."""
    return len(value.encode()) if name == "keywords" else len(value)


def problems(app: str, locale: str) -> list[str]:
    """Everything wrong with one locale's text, by Apple's limits and a few house rules."""
    found = []
    text = listing(app, locale)
    for name in REQUIRED:
        if name not in text:
            found.append(f"{name}.txt is missing")
    for name, value in text.items():
        limit = FIELDS[name][2]
        if measure(name, value) > limit:
            unit = "bytes" if name == "keywords" else "characters"
            found.append(f"{name}: {measure(name, value)} {unit}, over the limit of {limit}")
        if name.endswith("_url") and not value.startswith("https://"):
            found.append(f"{name}: not an https:// link")
    keywords = text.get("keywords", "")
    if ", " in keywords:
        found.append("keywords: a space after a comma wastes a character")
    # Words in the name and subtitle are already searched; repeating them in keywords wastes room.
    named = set(re.findall(r"\w+", (text.get("name", "") + " " + text.get("subtitle", "")).lower()))
    repeats = [k for k in keywords.split(",") if (words := set(re.findall(r"\w+", k.lower()))) and words <= named]
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
            sizes = ", ".join(f"{name} {measure(name, value)}/{FIELDS[name][2]}" for name, value in listing(app, locale).items())
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


def transfer(operations: list[dict], data: bytes) -> None:
    """Sends a reserved asset's bytes to the upload URLs Apple returned: unauthenticated and time-limited."""
    for op in operations:
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders") or []}
        part = data[op["offset"]:op["offset"] + op["length"]]
        request = urllib.request.Request(op["url"], method=op["method"], data=part, headers=headers)
        with urllib.request.urlopen(request, timeout=120) as response:
            response.read()


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
    every = client.get(f"/v1/apps/{app_id}/appStoreVersions?limit=50")
    versions = [v for v in every if v["attributes"].get("appStoreState") in EDITABLE_STATES]
    if not versions and only == {"promotional_text"}:
        # Promotional text can change on the live version, without a new one.
        versions = [v for v in every if v["attributes"].get("appStoreState") == "READY_FOR_SALE"]
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


# --------------------------------------------------------------------------------------------------------------------
# Screenshots and creative assets, through the App Asset Library

SCREENSHOT, HEADER, SEARCH = "APP_SCREENSHOT", "PRODUCT_PAGE_HEADER_ASSET", "APP_STORE_SEARCH_RESULTS_ASSET"
PREVIEW = "APP_PREVIEW"
# The app preview goes to the 6.9" and 6.3" iPhones; Apple fills in smaller sizes from these.
PREVIEW_GROUPS = ("IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE", "IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE")
VIDEO_SUFFIXES = {".mp4", ".m4v", ".mov"}


def library_kind(path: Path) -> tuple[str, str, str]:
    """Where a file lives in the asset library: its collection, resource type, and placement relationship."""
    if path.suffix.lower() in VIDEO_SUFFIXES:
        return "videos", "appAssetLibraryVideos", "video"
    return "images", "appAssetLibraryImages", "image"


def png_info(path: Path) -> tuple[int, int, bool]:
    """A PNG's width, height, and whether it has an alpha channel (App Store Connect refuses one)."""
    with path.open("rb") as file:
        head = file.read(33)
    if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        raise SystemExit(f"{path}: not a PNG")
    width, height = struct.unpack(">II", head[16:24])
    return width, height, head[25] in (4, 6)


def media(app: str, locale: str, folders: list[Path], creatives: dict[str, Path], preview: Path | None,
          poster: str | None, dry_run: bool) -> int:
    """Replaces the editable version's screenshots (each folder's PNGs, in name order), its product page header and
    search results asset (`creatives`, by placement type), and its app preview video, with `poster` as the frame shown
    before it plays. New files are uploaded and processed first; the old placements are only swapped out once every
    one is ready, so a failure leaves the listing as it was."""
    load_credentials()
    app_id = os.environ.get(APPS[app]["app_id_env"])
    if not app_id:
        raise SystemExit(f"missing {APPS[app]['app_id_env']} in the 1Password Environment")
    client = Client()
    ref = client.call("GET", "/v1/appAssetLibraryRefData")["data"]
    ref = (ref[0] if isinstance(ref, list) else ref)["attributes"]
    specs = {s["specId"]: s for s in ref["imageSpecs"]}

    def groups_for(kind: str, width: int, height: int) -> list[str]:
        out = []
        for placement in ref["placementTypes"]:
            if placement["placementTypeId"] != kind:
                continue
            for mapping in placement["specMappings"]:
                for spec_id in mapping["specs"]:
                    d = specs.get(spec_id, {}).get("dimensions", {})
                    if d.get("minWidth", 0) <= width <= d.get("maxWidth", 0) and d.get("minHeight", 0) <= height <= d.get("maxHeight", 0):
                        out.append(mapping["placementGroupId"])
                        break
        return out

    # What goes where: (placement type, group) -> files in order.
    plan: dict[tuple[str, str], list[Path]] = {}
    for folder in folders:
        for path in sorted(folder.glob("*.png")):
            width, height, alpha = png_info(path)
            if alpha:
                raise SystemExit(f"{path}: has an alpha channel, which App Store Connect refuses")
            groups = groups_for(SCREENSHOT, width, height)
            if not groups:
                raise SystemExit(f"{path}: {width}x{height} isn't an App Store screenshot size")
            plan.setdefault((SCREENSHOT, groups[0]), []).append(path)
    for kind, creative in creatives.items():
        width, height, alpha = png_info(creative)
        if alpha:
            raise SystemExit(f"{creative}: has an alpha channel")
        groups = groups_for(kind, width, height)
        if not groups:
            raise SystemExit(f"{creative}: {width}x{height} doesn't fit {kind}")
        plan[(kind, groups[0])] = [creative]
    if preview:
        if preview.suffix.lower() not in VIDEO_SUFFIXES:
            raise SystemExit(f"{preview}: an app preview is a .mp4, .m4v or .mov")
        if poster and not re.fullmatch(r"\d\d:\d\d:\d\d:\d\d", poster):
            raise SystemExit(f"--poster {poster}: a timecode into the video, HH:MM:SS:FF (FF is the frame)")
        for group in PREVIEW_GROUPS:
            plan[(PREVIEW, group)] = [preview]
    for (kind, group), files in plan.items():
        if kind == SCREENSHOT and len(files) > 10:
            raise SystemExit(f"{group}: {len(files)} screenshots, over Apple's 10")

    versions = [v for v in client.get(f"/v1/apps/{app_id}/appStoreVersions?limit=50")
                if v["attributes"].get("appStoreState") in MEDIA_EDITABLE_STATES]
    if not versions:
        raise SystemExit("no version whose media can change: create the next version in App Store Connect, or take "
                         "it out of its draft submission")
    version = versions[0]
    localization = next((l for l in client.get(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations?limit=200")
                         if l["attributes"]["locale"] == locale), None)
    if localization is None:
        raise SystemExit(f"version {version['attributes'].get('versionString')} has no {locale} localization yet: push the text first")
    print(f"{app} {locale}: version {version['attributes'].get('versionString')} ({version['attributes'].get('appStoreState')})"
          + (" — dry run, nothing is written" if dry_run else ""))

    def existing(kind: str, group: str) -> list[dict]:
        return client.get(f"/v1/appStoreVersionLocalizations/{localization['id']}/placements?filter[placementType]={kind}"
                          f"&filter[placementGroup]={group}&sort=placementGroupPosition&limit=50")

    current = {key: existing(*key) for key in plan}
    for (kind, group), files in plan.items():
        print(f"  {kind} {group}: replace {len(current[(kind, group)])} with {len(files)}: "
              + ", ".join(p.name for p in files) + (f" (poster at {poster})" if kind == PREVIEW and poster else ""))
    if dry_run:
        return 0

    # Upload every distinct file once, and wait until each is processed. Apple wants each asset's reference name
    # unique, so it ends with a hash of the contents; an asset the library already has under that name is reused.
    library = client.call("GET", f"/v1/apps/{app_id}/assetLibrary")["data"]["id"]
    uploaded: dict[Path, str] = {}
    for (kind, group), files in plan.items():
        category = "CREATIVE_ASSETS" if kind in (HEADER, SEARCH) else "APP_SCREENSHOTS_AND_PREVIEWS"
        for path in files:
            if path in uploaded:
                continue
            collection, resource, _ = library_kind(path)
            data = path.read_bytes()
            digest = hashlib.sha256(data).hexdigest()[:8]
            name = f"{app} {path.parent.name} {path.stem}"[:91] + f" {digest}"
            found = [a for a in client.get(f"/v1/appAssetLibraries/{library}/{collection}?filter[referenceName]="
                                           f"{urllib.parse.quote(name)}&limit=5")
                     if a["attributes"].get("state") != "FAILED"]
            if found:
                uploaded[path] = found[0]["id"]
                print(f"  {path.name}: already in the library")
                if resource == "appAssetLibraryVideos" and poster and found[0]["attributes"].get("previewFrameTimeCode") != poster:
                    client.call("PATCH", f"/v1/{resource}/{found[0]['id']}", {"data": {
                        "type": resource, "id": found[0]["id"], "attributes": {"previewFrameTimeCode": poster}}})
                    print(f"  {path.name}: poster frame moved to {poster}")
                continue
            attributes = {"fileName": path.name, "fileSize": len(data), "category": category, "referenceName": name}
            if resource == "appAssetLibraryVideos" and poster:
                attributes["previewFrameTimeCode"] = poster
            asset = client.call("POST", f"/v1/{resource}", {"data": {
                "type": resource, "attributes": attributes,
                "relationships": {"assetLibrary": {"data": {"type": "appAssetLibraries", "id": library}}}}})["data"]
            transfer(asset["attributes"]["uploadOperations"], data)
            client.call("PATCH", f"/v1/{resource}/{asset['id']}",
                        {"data": {"type": resource, "id": asset["id"], "attributes": {"uploaded": True}}})
            uploaded[path] = asset["id"]
            print(f"  uploaded {path.name}")
    minutes = 20 if any(library_kind(p)[0] == "videos" for p in uploaded) else 10
    deadline = time.time() + minutes * 60
    waiting = dict(uploaded)
    while waiting:
        for path, asset_id in list(waiting.items()):
            attributes = client.call("GET", f"/v1/{library_kind(path)[1]}/{asset_id}")["data"]["attributes"]
            if attributes["state"] == "PREPARE_FOR_SUBMISSION":
                del waiting[path]
            elif attributes["state"] == "FAILED":
                raise RuntimeError(f"{path.name} failed processing: {attributes.get('stateDetails')}. The listing is unchanged.")
        if waiting:
            if time.time() > deadline:
                raise RuntimeError(f"still processing after {minutes} minutes: {', '.join(p.name for p in waiting)}. "
                                   "The listing is unchanged; run again to retry.")
            time.sleep(5)
    print(f"  {len(uploaded)} files processed")

    # Swap the placements, then put each screenshot group in order.
    for (kind, group), files in plan.items():
        for old in current[(kind, group)]:
            client.call("DELETE", f"/v1/appAssetLibraryPlacements/{old['id']}")
        placed = []
        for path in files:
            _, resource, relationship = library_kind(path)
            placement = client.call("POST", "/v1/appAssetLibraryPlacements", {"data": {
                "type": "appAssetLibraryPlacements",
                "attributes": {"placementType": kind, "placementGroup": group},
                "relationships": {
                    relationship: {"data": {"type": resource, "id": uploaded[path]}},
                    "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations",
                                                             "id": localization["id"]}}}}})["data"]
            placed.append(placement["id"])
        if kind == SCREENSHOT and len(placed) > 1:
            client.call("POST", "/v1/appAssetLibraryPlacementOrderingRequests", {"data": {
                "type": "appAssetLibraryPlacementOrderingRequests",
                "attributes": {"placementGroup": group},
                "relationships": {
                    "orderedPlacements": {"data": [{"type": "appAssetLibraryPlacements", "id": i} for i in placed]},
                    "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations",
                                                             "id": localization["id"]}}}}})
        print(f"  {kind} {group}: {len(placed)} placed")
    return 0


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
    images = sub.add_parser("media", help="replace the editable version's screenshots and creative assets")
    images.add_argument("--app", choices=APPS, required=True)
    images.add_argument("--locale", default="en-US")
    images.add_argument("--screenshots", type=Path, nargs="*", default=[],
                        help="folders of PNGs, one per device size, uploaded in name order")
    images.add_argument("--creative", type=Path, help="a 5244x2950 PNG for the product page header and search results")
    images.add_argument("--header", type=Path, help="a 5244x2950 PNG for the product page header only")
    images.add_argument("--search", type=Path, help="a 5244x2950 PNG for the search results asset only")
    images.add_argument("--preview", type=Path, help="the app preview video (1920x886), for the 6.9\" and 6.3\" iPhones")
    images.add_argument("--poster", help="the preview's poster frame, the still shown before it plays (HH:MM:SS:FF)")
    images.add_argument("--dry-run", action="store_true", help="show what would change; write nothing")
    args = parser.parse_args()
    if args.command == "check":
        return check()
    if args.command == "media":
        creatives = {kind: path for kind, path in ((HEADER, args.header or args.creative),
                                                   (SEARCH, args.search or args.creative)) if path}
        if args.poster and not args.preview:
            raise SystemExit("--poster sets the frame of the --preview video it comes with")
        if not args.screenshots and not creatives and not args.preview:
            raise SystemExit("nothing to do: give --screenshots folders, a --creative (or --header, --search) image, "
                             "or a --preview video")
        try:
            return media(args.app, args.locale, args.screenshots, creatives, args.preview, args.poster, args.dry_run)
        except RuntimeError as error:
            print(f"error: {error}", file=sys.stderr)
            return 2
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
