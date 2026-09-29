<div align="center">

# lycard

**A deck assistant for Lycee Overture**

Offline-first card database · card art · Chinese translation · deck building · in-game stat calculator

[中文](README.md) ｜ [**English**](README.en.md) ｜ [日本語](README.ja.md)

[Download APK](https://github.com/Lanactnum/lycard-updates/releases) · [Features](FEATURES.en.md) · [Changelog](CHANGELOG.md) · [Card art data pack](../../releases/tag/cards-pack-v1)

</div>

---

## What is this

`lycard` is an Android (arm64) utility for players of **LYCEE OVERTURE** — put together by my
whale girl, in exchange for bowls of steamed rice.
(She wrote this repository too. One of these days I'll go through it by hand... *flops over*)

Everything lives on your device, so you can **browse, build and calculate with no network at all**.
Card art uses a two-layer scheme: the APK bundles a compressed WebP set (good enough to read),
and the official 372×520 PNG originals are shipped separately as a data pack — which is why
the installer doesn't balloon to several gigabytes.

> Unofficial, fan-made. Card stats, effect text and card art belong to the LYCEE OVERTURE
> rights holders. This project is for personal collection and looking things up during games,
> and must not be used commercially. See [License](#license).


## Screenshots

<p align="center">
  <img src="docs/shots/01-search.png" width="270" alt="search">
</p>

| Search results | Card detail | Deck overview |
|:---:|:---:|:---:|
| <img src="docs/shots/02-results.png" width="215"> | <img src="docs/shots/03-card-detail.png" width="215"> | <img src="docs/shots/04-deck.png" width="215"> |
| **Deck cards** | **Calculator** | **My** |
| <img src="docs/shots/05-deck-cards.png" width="215"> | <img src="docs/shots/06-calculator.png" width="215"> | <img src="docs/shots/07-mine.png" width="215"> |

## Features

> The full list, screen by screen, lives in [**Features**](FEATURES.en.md). Below is an overview.

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

**Both builds are published** — the arm64 build (smallest) and the universal build (installs anywhere).

**The APK lives in the update repo**: [`Lanactnum/lycard-updates` → Releases](https://github.com/Lanactnum/lycard-updates/releases)
— that is also the endpoint the app's "Check for updates" hits. This repo's Releases carry
only the **card art data pack**.

| File | Size | What it is |
|---|---|---|
| `lycard-<version>-arm64.apk` | **573.5 MB** | **arm64 build**, the smallest — use this for essentially every phone |
| `lycard-<version>-universal.apk` | **616.1 MB** | **Universal build** (arm64 + 32-bit ARM + x86_64) for older devices or when you don't know what the recipient has |
| `lycard-<version>*.sha256` | | Checksums |

> The in-app "Check for updates" **picks by your device's ABI**: arm64 phones get the arm64 build, others get the universal one.
> The `arm64` / `universal` tokens in the asset names are meaningful - please don't rename them.

After installing, **launch it once** so the app can create its own data directory.

## Card art data pack

The APK bundles **compressed** art. For the official **372×520 PNG originals**, grab the
[**cards-pack-v1**](../../releases/tag/cards-pack-v1) release in this repo:

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

# (1) arm64 only - smallest, and that is virtually every phone today
flutter build apk --release --target-platform android-arm64

# (2) all ABIs in one APK (arm64 + 32-bit ARM + x86_64) - installs anywhere
flutter build apk --release --target-platform android-arm,android-arm64,android-x64

# (3) one APK per ABI
flutter build apk --release --split-per-abi
```

| Build | Size (measured on 0.85.1) | Notes |
|---|---|---|
| `--target-platform android-arm64` | 573.5 MB | arm64 native libraries only |
| `--target-platform android-arm,android-arm64,android-x64` | 616.1 MB | three sets of native libraries in one APK |

**Why the universal build is only ~42 MB larger**: the card data and images (~518 MB) are
**shared** across ABIs; only the native libraries are duplicated
(arm64 36.8 MB + 32-bit ARM 29.4 MB + x86_64 39.8 MB). So if you are worried about a device
not being able to install it, just ship the universal build - the cost is smaller than it sounds.

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
