# App Store listing text

Each app's App Store Connect listing lives here as plain text files, reviewed in pull requests like code, and
`push.py` sends them to App Store Connect through Apple's API. The workflow is adapted from a friend's App Store
listing kit.

```
appstore/
├── push.py
└── <app>/                                  # bigger-fish, math-reef
    ├── app/<locale>/<field>.txt            # name, subtitle, promotional_text, description, keywords,
    │                                       # release_notes, support_url, marketing_url, privacy_policy_url
    └── iap/<purchase>/<locale>/{name,description}.txt
```

```bash
python3 appstore/push.py validate                             # Apple's limits and a few house rules; no network
python3 appstore/push.py check                                # the credentials work; lists each app's Apple ID
python3 appstore/push.py push --app bigger-fish --dry-run     # what would change, field by field
python3 appstore/push.py push --app bigger-fish                # push only what differs
python3 appstore/push.py push --app bigger-fish --only promotional_text
python3 appstore/push.py media --app bigger-fish --screenshots DIR DIR --header FILE --search FILE --dry-run
python3 appstore/push.py media --app bigger-fish --preview VIDEO --poster 00:00:26:20 --dry-run
```

`media` replaces the editable version's screenshots (each folder's PNGs in name order, one folder per device size)
and its product page header (`--header`) and search results asset (`--search`), each a 5244×2950 image; `--creative`
puts one image in both. Check the header in App Store Connect's preview on an iPhone, which crops it hard.
`--preview` replaces the app preview video on the 6.9" and 6.3" iPhones, and `--poster` picks the frame the App Store
shows until it plays (a timecode into the video, HH:MM:SS:FF; it can only be a frame of the video). It goes
through Apple's App Asset Library: each file is uploaded and processed first, and the old placements are swapped
out only once all of them are ready, so a failure leaves the listing as it was. A screenshot's device size comes from
its dimensions, matched against Apple's reference data. For Bigger Fish, the files come from
`scripts/bigger-fish-store-capture.sh` (and `--ipad`), `scripts/bigger-fish-store-frames.py` (captions),
`scripts/bigger-fish-creative.py` (the universal creative), and `scripts/bigger-fish-trailer.sh` (the preview); see
the main README.

- **A push writes to the editable version** (Prepare for Submission and the like). Nothing goes public until that
  version is submitted and released. Always dry-run first.
- **Promotional text can change any time** without review. A new version can come up with it empty: push it again
  with `--only promotional_text`.
- **Edited something in App Store Connect's website?** Copy it back into the file, or the next push overwrites it.
- **An app's first version has no What's New**, so `release_notes.txt` waits for the second.
- **validate checks**: the character limits (name and subtitle 30, promotional text 170, keywords 100, description
  and What's New 4000, an in-app purchase's name 30 and description 45), https links, no space after a keyword's
  comma, and no keyword that's already in the name or subtitle (those are searched anyway).

## Credentials

Nothing secret is in a file. The App Store Connect API key (App Manager role) is in the 1Password Environment
**App Store Connect**, which 1Password mounts at `~/.appstoreconnect/.env`: a pipe it feeds when the script reads it,
never plaintext on disk. It holds `ASCC_KEY_ID`, `ASCC_ISSUER_ID`, `ASCC_PRIVATE_KEY` (the `.p8` file's contents,
concealed), `ASCC_APP_ID_BIGGER_FISH`, and `ASCC_APP_ID_MATH_REEF`. Set `ASCC_ENV_FILE` to read another path, or set
the variables in the environment.

Talking to the API needs the `cryptography` package (`python3 -m pip install --user cryptography`, or a virtual
environment); `validate` needs nothing.
