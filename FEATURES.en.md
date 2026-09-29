<div align="center">

# lycard — Feature list

[中文](FEATURES.md) ｜ [**English**](FEATURES.en.md) ｜ [日本語](FEATURES.ja.md)

← Back to [README](README.en.md)

</div>

---

## Search

- **Search** card name / card number / effect text — Chinese names work too (a Chinese search index is bundled)
- **Switchable keyboard**: numeric keypad by default (fast for card numbers), one tap to the text keyboard
- **Combined filters**: attribute (Sun / Moon / Flower / Snow / Star / Aether), cost, EX, card type
  (character / event / item / area), series (title), company / brand, rarity, type, artist — stackable,
  with a "N filters selected" readout and one-tap clear
- **Result grid**: cards per row (auto / manual column count), optional effect text in list view
- **Paging**: "Load More (N remaining)"
- **Card detail**:
  - Large art, AP / DP / SP / DMG / EX / cost / attribute / card type / rarity / artist / first release / title
  - Japanese effect text plus the Chinese translation; **keywords are tappable** for their meaning and
    **card names are tappable** to jump to that card
  - **Related cards**: cards in this deck plus cards with similar effects (e.g. "Bounce"), grouped
  - **My card**: acquisition cost / date / exchange rate / your own condition / per-card notes / MVP mark
  - **Edit card info**: change name, effect, artwork — or "Restore Official Card Art / Data"
  - Copy card name or card info; **save art to the gallery** (multi-select batch save)
  - **+1 / -1 straight into a deck** without leaving the page
- **Scanning**: recognise a card number or QR code inside the viewfinder (Google ML Kit), haptic feedback
  on a hit, card shown in a floating panel, with "Continue Scanning"
- **Clipboard monitoring** (optional): copy a card number or deck share code, return to the app, and it is
  detected automatically with a one-tap action

## Deck building

- **Deck list**: each deck shows its cover art (editable), main card icons, card count, description,
  win/loss record and win rate, and missing-card warnings
- **Rules mode switch**: Free Build (Mix Format) / Single Title (Neo-Classic) / Mixed Attributes /
  Limited (Draft / Sealed) — decks are revalidated under the selected rules
- **Deck-building rules**:
  - Main deck must be exactly 60 cards (30 in Limited)
  - Max 4 copies per card number (2 in Limited)
  - Max 1 card with the "Leader" ability, placed in the Leader slot
  - **Sideboard** optional, 0–10 cards, not counted toward the 60 but counted toward the 4-per-number limit
  - Company / title restrictions (cards usable only in a single-company deck, single-title decks)
- **Two-level validation**: **Errors** (hard problems: wrong card count, copy limit exceeded, ban list
  violations) and **Warnings** (ignorable: missing Leader, region restrictions, etc.)
- **Ban / restriction list**: officially banned, copy-limited and deck-restricted cards, updatable online;
  plus your own **custom banned cards** and custom restrictions (store events, group rules), carried in backups
- **Visual editing**: add/remove cards right in the grid; **drag** to swap cards between main deck and
  sideboard with charts updating live; quick +1 / -1
- **Charts overlay**: attribute distribution, cost curve, character / event / item ratio (main deck only),
  can be turned off
- **Opening hand simulator / draw test**: 8 cards going first, 9 going second; mulligan (return unwanted
  cards, shuffle, redraw the same number); pick "key cards" and it computes the chance of drawing them
- **Version snapshots**: save a snapshot, roll back to any earlier version (rolling back also restores that
  version's win/loss record)
- **Match records**: wins, losses and win rate per deck
- **Card notes & MVP**: write a note on a specific card ("this deck relies on it appearing on turn 2") or mark it MVP
- **Missing cards**: cards in a deck you don't own (or own too few of) can be **added to "Wanted" in one tap**
  (optionally just some of them)
- **Cross-deck conflicts**: when several decks share physical cards you don't own enough of, the deck list flags it
- **Sharing**: `LYD1` share code (compressed to under 500 characters to fit input-method clipboard limits)
  and **QR sharing** (optionally embedding the main card art as a centre logo, or a glass-style QR)
- **Import**: paste a share code, or **scan a QR code to import a deck**
- **Printing**: export the deck list straight to PDF

## My · Decks & collection

- **Collection progress**: N cards collected with a progress bar; grouped by **company (brand) → title (series)**,
  with an "All" option
- **Acquisition info**: per-card cost, date, currency and an **independent exchange rate** (enter it manually
  or fetch the rate of that time online), normalised per card's original currency; a missing date falls back
  to the current rate and then to a default
- **Deck value**: total value in large type at the top, switchable currency unit, with a hide/show button
  (hidden by default)
- **Rarity / alternate art**: long-press a card to record rarity and alternate art (parallel foil); badge
  style is configurable (colour / blur / opacity, ✦ mark) with a live preview in settings
- **My categories**: create, rename and delete custom categories; file cards into them
- **Custom cards**: create new cards, edit existing ones, swap artwork, assign categories — and restore
  official data in one tap

## Wanted / For sale

- Two separate pages, **Wanted** and **For sale**, for cards you want to buy or sell
- **Condition**: built-in grades (S / A / B) plus common descriptors (sealed, never played, subtle white
  border, corner damage, creased, indentation, signed version, sleeved…), and **your own custom tags** shown
  in the detail view
- Record price, notes and purchase location
- **Photos**: attach your own photo to each card; tap to save it to the gallery
- **Automatic tally**: which card numbers you're missing, how many, and the estimated cost to complete
  (based on the prices you entered; shows `-` if not all are filled in) — take the list shopping

## In-game stat calculator

- Field is 3 AF slots + 3 DF slots for each player; pick cards straight from a deck to place them
- **Automatically calculated on placement**: effects that are simply "on while on the field" (`[常時]`, or
  untagged) are applied to the stats immediately
- **Activated effects are never guessed for you**: `[誘発]` / `[宣言]` / effects with a cost / conditional
  ones / ones with variables / ones needing a single target all stay in the card's panel, where you can apply
  them one by one or hit "apply all remaining N"
- **The whole field is recomputed on every change**: field-wide effects ("ＡＰ＋１ to all allied characters")
  also reach cards played later, and removing the source card takes its bonus off everyone
- **Every step is visible, editable and removable**: each modifier is labelled with its source
  (manual / effect / auto) and timing (last turn / this turn / response / always); values are editable and
  applied ones can be undone
- **Charge** and **storage zone (置き場)** counts sit under each card, just like physical cards
- The board is **not saved** — it clears when you leave

## Rules & quick reference

- **Game rules**: what attributes, AP / DP / SP / DMG / EX / cost mean, card type descriptions, turn flow,
  the Leader and deck construction
- **Abilities & keywords**: what `[常時]` / `[誘発]` / `[宣言]` / `[手牌宣言]` / `[対応]` and other markers mean,
  plus a keyword lookup
- **Ban / restriction list**: official bans, copy limits and deck restrictions, plus your own
- **Official update history**

## Appearance & settings

- **Startup & defaults**: which page the app opens on (Search / Decks / My), interface scale (DPI)
- **Display & search**: cards per row, numeric keypad for the search box, effect text in lists, show Chinese by default
- **Interface language**: 简体中文 / 繁體中文 / English / 日本語 / 한국어 / Русский
- **Appearance & animation**:
  - Floating / transparency / rounded corners / background / font — each adjustable
  - Glass opacity and blur; top bar and pill tuned together; custom corner radius
  - Light / dark / system, plus palettes: 9+ colour schemes in one tap (Mint / Coral / Lapis Blue /
    Lavender / Pale Yellow / Red Gold / Plum / Azure / Slate Blue / Slate Gray / Jet Black / Monochrome)
  - Colour sources: system theme (Material You) / extract from the background image / fine-tune colours /
    enter a hex code `#RRGGBB`
- **Fonts & text**: pick a font file (ttf / otf / ttc), font colour, **dynamic font weight (variable font)** —
  weight changes continuously as you scroll or select; one-tap restore of the default font
- **App background**: change the background image with crop / rotate 90° / zoom / brightness / overlay colour
  and opacity / remove background
- **Haptics**: different intensities for adding a card, removing a card, deck validation errors
- **Clipboard monitoring** toggle
- **Predictive back gesture** (Android)

## Data & backup

- **Export / import backup**: decks, collection, wanted / for-sale, photos, custom card art, backgrounds,
  fonts and all settings in a single zip; legacy backups (without images) are still supported
- **Categorised cache cleanup**: see exactly what extra data the app holds (image cache / temporary files /
  exported backups …) and choose what to clear; anything cleared goes to the **trash** first and is
  **recoverable for 15 days** before being destroyed for real
- **Card art data pack**: pick `lycee_cards.pack` from the file manager to import and auto-mount it, rescan,
  or check its mount status
- **Online updates**: incremental updates for the card list, translations and ban list, triggerable in settings
- **In-app update check**: queries GitHub Releases for a new version, shows the notes and downloads the APK

## Other

- Three or more UI languages (Chinese / Japanese / English) and documentation in all three
- A new **glass / floating** visual system: top bar, bottom pill, sheets and panels are all driven from a
  handful of files, so one change applies everywhere
- Motion: list-to-detail arc + zoom, M3 spring physics, predictive back
