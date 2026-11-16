# BestSkillUp — hand-off

WoW: Forever add-on that ranks profession recipes by **expected gold per skill point**, using Auctionator prices. Blacksmithing only so far. Version 0.5.0, Interface 16001.

- Source (git repo): `C:\Users\User\BestSkillUp`, pushed to the private GitHub repo https://github.com/Aganmar/BestSkillUp
- Install path (managed by WowUp from the GitHub releases): `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\BestSkillUp`

## Releasing

Bump `## Version:` in `BestSkillUp.toc`, commit and push, then either push a matching tag (`git tag v0.5.1 && git push origin v0.5.1`) or press **Run workflow** on the Release workflow in the repo's Actions tab (it tags the commit `v<TOC version>`). The `Release` workflow (`.github/workflows/release.yml`) checks a pushed tag matches the TOC version, builds `BestSkillUp-<tag>-forever.zip` (the TOC and the files it loads, under a `BestSkillUp/` folder) plus a `release.json` (flavor `forever`), and publishes the GitHub release that WowUp installs from.

## How it works

```
expected cost per point = (reagent cost − value of what you make) ÷ chance to skill up
chance (Classic rule)   = orange 100%, grey 0%, yellow/green = (grey − skill) ÷ (grey − yellow)
```

- **Reagent cost** (`ns.UnitCost`, recursive, memoised, depth ≤ 5): cheapest of manual override → vendor → Auctionator AH → crafting/smelting it from its own reagents → Wowhead average price (fallback, toggle `useWH`).
- **Value of what you make** (`ns.ResaleValue`): `none` / `vendor` (vendor sell price) / `ah` (AH price × (1 − AH cut) × sell-through, or vendor if higher). BoP items always use vendor value.
- **Live colour override** (`ns.Chance`): at your current skill, the game's own recipe difficulty wins if it disagrees with the data.
- **Ranking** (`ns.Evaluate`): every usable recipe with chance > 0, sorted by cost per point, then chance, then ID. Recipes with an unpriced reagent sort last.

## Files

| File | What it does |
|---|---|
| `BestSkillUp.toc` | Load order: Data → Core → UI → Native → Sync. OptionalDeps Auctionator, EllesmereUI, EllesmereUIBlizzardSkin. SavedVariables `BestSkillUpDB`, per-character `BestSkillUpCharDB`. |
| `Data_Blacksmithing.lua` | **Generated, don't hand-edit.** `ns.Data.recipes[spellID] = { name, outputItemID, minMade, maxMade, orange, yellow, green, grey, source, { reagentID, qty, … } }`, `ns.Data.items[id] = { name, quality, vendorSell, wowheadAvg }`, `ns.Data.vendor[id]`, `ns.Data.mining` (smelting recipes). |
| `Core.lua` | Settings defaults, prices, skill-up maths, evaluation, scanning the open Professions window (known recipes, current skill, live difficulty), events, `/bsu` slash command. |
| `UI.lua` | Suggestion list docked to the Professions window, options panel, item tooltips (comparison tooltips suppressed unless Shift is held), Shift-click → copyable Wowhead URL, EllesmereUI skin via `EllesmereUI.RegisterSkin`. |
| `Native.lua` | Adds lines under the recipe in Blizzard's crafting window: `Skill-up: N%` + coloured thresholds (orange/yellow/green/grey), `Cost Per Point (Vendor)`, and `Cost Per Point (AH)` (omitted for BoP output). Hidden when no skill-up is possible. Hooks `ProfessionsFrame.CraftingPage.SchematicForm:Init`; anchors under Auctionator's crafting-cost frame if present. |
| `Sync.lua` | Partner price sync between two characters over addon WHISPER (prefix `BSUSYNC1`). The side with the newer Auctionator scan sends; the receiver stores prices in `BestSkillUpDB.shared` and can push them into Auctionator (`/bsu auctionator`). |
| `Tools/SyncAuctionator.ps1` | Offline sync: copies `AUCTIONATOR_PRICE_DATABASE` from the account with the newest `TimeOfLastBrowseScan` into the other accounts' `Auctionator.lua`, backing each up as `.bsu-bak`, then launches Battle.net. Refuses to run while WoW is open. Started by `Desktop\Sync Auctionator + Play WoW.bat`. |
| `Tools/gen_data.py` | Rebuilds `Data_Blacksmithing.lua` (see below). |

## Settings (`BestSkillUpDB`)

`resale` (none/vendor/ah, default vendor), `ahCut` 5, `ahSellThrough` 60, `useWH` true, `reagents` {vendor, ah, craft, smelt}, `includeUnlearned` true, `sources` {trainer, vendor, other on; drop, quest off}, `overrides` [itemID] = copper, `point`, `shown`, `shared` (synced prices), `pushAuctionator`.
Per character (`BestSkillUpCharDB`): `known`, `scanned`, `skill`, `maxSkill`, `mining`.

## Slash commands

`/bsu` toggle · `opt` · `partner [name]` · `sync` · `auctionator` · `resale none/vendor/ah` · `unlearned` · `source <type>` · `wh` · `price <itemID> [copper]` (blank clears) · `debug` (Native.lua state) · `reset` (window position)

## Data generation

```
python3 Tools/gen_data.py <blacksmithing.json> <mining.json> Data_Blacksmithing.lua
```

The inputs were Wowhead (WoW Forever) exports: `g_listviews.recipes` (colors, reagents, creates, learnedat, source) and `g_items` (jsonequip buyprice/sellprice/avgbuyout). **The JSON exports weren't kept**, so a regeneration needs them scraped again. Notes:
- Thresholds: orange = colors[0], else learnedat; starter recipes (no orange, no trainer, learnedat ≤ 20) are treated as skill 1. Wowhead's `learnedat` is sometimes wrong (e.g. Rough Sharpening Stone).
- Wowhead's `buyprice` is a template value, not proof an item is vendor-sold; vendor items come from the `VENDOR_NAMES` list in the script.
- Wowhead rate-limits fast scraping (CloudFront 403) — fetch slowly or in one request per profession.

## Testing / gotchas

- Adding a file to the TOC needs a **full game restart**, not `/reload`.
- `|` in chat text is a WoW escape code — help text uses `/` instead.
- `StaticPopup` data doesn't pass through on Forever; the Shift-click link uses a custom frame.
- EllesmereUI already skins GameTooltip; the add-on uses its own tooltip frames (`BestSkillUpItemTip`, `BestSkillUpCostTip`) and doesn't re-skin them.
- Forever character names include a surname ("Mung Bean"); compare names with `sameName` in Sync.lua.
- Logic was tested outside the game with lua5.1 and stubbed WoW APIs; there is no test harness in this folder.

## Open items

1. **Ranking skew (undecided).** With resale on, profitable crafts with a low skill-up chance can outrank reliable ones, because a negative net cost divided by a small chance looks great. Suggested fix: a "profit credit %" setting (count only part of the resale value) plus a "cost per craft" column, so cheap-but-unlikely recipes are visible for what they are.
2. **Overlap with ScanShare.** ScanShare (github.com/Aganmar/ScanShare) now writes shared prices straight into Auctionator, which BestSkillUp already reads. `Sync.lua` and `Tools/SyncAuctionator.ps1` are probably redundant and could be removed.
3. **Other professions.** Everything except the data file and the profession check is generic; the check uses skillLine 164 (Blacksmithing) and Mining 186 for smelting. Adding a profession means generating its data file and generalising those checks.
