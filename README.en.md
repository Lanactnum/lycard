<div align="center">

# lycard

**A deck assistant for Lycee Overture**

Offline-first card database · card art · Chinese translation · deck building · in-game stat calculator

[中文](README.md) ｜ [**English**](README.en.md) ｜ [日本語](README.ja.md)

[Download](../../releases) · [Changelog](CHANGELOG.md) · [Card art data pack](#card-art-data-pack)

</div>

---

## What is this

`lycard` is an Android (arm64) utility for players of **LYCEE OVERTURE**.

Everything lives on your device, so you can **browse, build and calculate with no network at all**.
Card art uses a two-layer scheme: the APK bundles a compressed WebP set (good enough to read),
and the official 372×520 PNG originals are shipped separately as a data pack — which is why
the installer doesn't balloon to several gigabytes.

> Unofficial, fan-made. Card stats, effect text and card art belong to the LYCEE OVERTURE
> rights holders. This project is for personal collection and looking things up during games,
> and must not be used commercially. See [License](#license).

## Features

### Search

- Search by **card name / card number / effect text** — Chinese names work too
  (a Chinese search index is bundled)
- Filter by attribute (Sun / Moon / Flower / Snow / Star / Aether), cost, EX, card type,
  series, rarity and more
- Card detail: art, stats, Japanese effect text plus the Chinese translation; **card names
  mentioned inside effect text are tappable** and jump to that card
- Four-level fallback for art: **pack original → bundled art → official website → placeholder**,
  so a missing layer never crashes anything
- Batch-save art to the gallery

### Deck building

- Main deck 60 cards, max 4 copies per card number, at most 1 leader; **restricted format**
  automatically switches to 30 cards / max 2 copies / no side deck
- Deck folders are grouped by **the series the card belongs to** (work / game / company),
  not by LO number
- Opening-hand simulator, deck statistics charts (attribute / cost / card type breakdown)
- Deck import: **two separate recognition systems** — official deck codes and the usual
  shared text — so if one misreads you can switch to the other
- Deck export: QR code sharing, text sharing
- Print a deck list to PDF

### Calculator

Put cards on the field during a game and let it do the arithmetic.

- **Auto-calculated the moment a card lands**: effects that are simply "on while on the field"
  (`[常時]`, or untagged) are applied immediately; activated/triggered ones (`[誘発]`, `[宣言]`)
  are never guessed for you — apply them from the card's panel, all at once or one by one
- **Whole field is recomputed on every change**: field-wide effects like
  "ＡＰ＋１ to all allied characters" also reach cards played later, and removing the source
  card takes its bonus off everyone
- **Every step is visible, editable and removable**: each modifier is labelled with its source
  (manual / effect / auto) and its timing (last turn / this turn / response / always)
- **Charge** and **storage zones (置き場)** counts sit under each card, just like real cards
- The board state is **not saved** — it clears when you leave

### Everything else

- Rules quick reference, ban/restriction list (updatable online)
- Keyword and effect-fragment lookup
- Camera scanning: read card text or a QR code and jump straight to that card
- UI in multiple languages (简体中文 / 繁體中文 / English / 日本語 / 한국어 / Русский)
- Hot data updates: card list, translations and ban list can be updated incrementally online,
  or imported from a data pack via the file manager
- Local backup / restore (zip), printing, in-app feedback

## Download & install

arm64 only (that's virtually every phone now). Grab from [Releases](../../releases):

| File | What it is |
|---|---|
| `lycard-<version>.apk` | The installer, about **600 MB** — compressed art is already inside, so this alone is enough |
| `lycard-<version>.apk.sha256` | Checksum |

After installing, **launch it once** so the app can create its own data directory.

## Card art data pack

The APK bundles **compressed** art. For the official **372×520 PNG originals**, download the data pack:

| File | Size |
|---|---|
| `lycee_cards.pack.part01` + `.part02` | **3.65 GB** joined (3,919,354,515 bytes) |

GitHub caps a single release asset at 2 GB, so the pack is split into two volumes.
**Join them** (pick one):

**Windows (recommended, script from this repo)**

```bat
python tools\join_cards_pack.py %USERPROFILE%\Downloads
```

**Windows (no Python)**

```bat
copy /b lycee_cards.pack.part01+lycee_cards.pack.part02 lycee_cards.pack
```

**Linux / macOS / WSL**

```bash
cat lycee_cards.pack.part* > lycee_cards.pack
```

The joined file must be exactly **3,919,354,515 bytes** and its SHA256 must be:

```
49b26768074e345710ec7d6d9599a6bf3c9aaf2111114017d7b05c599170f5a9
```

> Please do check it. Truncated downloads really do happen, and the symptom is
> "**some card images are blank**", which is easy to mistake for an app bug.

**Where to put it** (either one):

1. **On the phone** (recommended, no cable needed): drop `lycee_cards.pack` into the phone's
   Downloads folder, then in the app go to **Mine → Data & backup → Pick data pack from file manager**.
2. **From a computer**: `adb push lycee_cards.pack /sdcard/Android/data/com.lycard.app/files/`
   — the app must have been **launched once first**, otherwise that directory doesn't exist yet.

The app picks it up automatically; you can also hit "Rescan" in settings.

> Why not just tell everyone to use a cable: since Android 11, `Android/data` is simply not
> visible in a file manager, so option 1 is the one that works for ordinary users.

## Building from source

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

arm64 only on purpose: a universal build is more than twice the size and takes twice as long
to install, and essentially every phone is arm64 now.

**Signing**: no signing keys are in this repository (`android/key.properties` and `android/*.jks`
are both in `.gitignore`). To produce your own build, generate one:

```bash
keytool -genkey -v -keystore android/my-release.jks -keyalg RSA -keysize 2048 \
        -validity 10000 -alias mykey
```

then create `android/key.properties` following the `signingConfigs` block in
`android/app/build.gradle.kts`.

**Tests**:

```bash
flutter analyze     # should report: No issues found
flutter test        # 200+ tests
python tools/check_bottom_pad.py   # bottom-bar overlap self-check
```

## Data sources

- Card data and art: the **official LYCEE OVERTURE website** (`lycee-tcg.com`)
- Chinese translations: **translated by this project**, terminology aligned with the official
  《基本能力及字段说明》
- Some historical data was filled in from the **Wayback Machine**

`tools/` holds the one-off data pipeline (fetching / translating / packing / auditing).

## Project layout

```
lib/
  data/       card loading, Chinese search index, data pack reader
  l10n/       UI translation tables
  models/     card and deck models
  pages/      screens (search / build / calculator / mine / rules …)
  services/   scanning, printing, backup
  state/      app state; calculator model and effect parser
  widgets/    shared visual components (glass panels / tags / layout constants)
assets/
  data/       card list, translations, search index, ban list, keywords
  cards/      bundled compressed art (~517 MB)
tools/        data pipeline + self-check scripts
test/         tests
```

## Toolchain

| Script | Purpose |
|---|---|
| `tools/fetch_list.py` | Scrape the card list from the official site |
| `tools/make_app_data.py` | Produce `cards_app.json` for the app (field whitelist) |
| `tools/build_pack.py` | Pack the PNG originals into `lycee_cards.pack` |
| `tools/join_cards_pack.py` | Rejoin the split release volumes |
| `tools/build_search_keys.py` | Rebuild the Chinese search index |
| `tools/check_bottom_pad.py` | Bottom-bar overlap self-check |

## License

- **Code**: MIT, see [LICENSE](LICENSE)
- **Card data / effect text / card art**: owned by the LYCEE OVERTURE rights holders, and
  **not covered by the MIT license** — personal collection and in-game reference only,
  no commercial use
- **This project's Chinese translations**: translated here, released under MIT along with the code
