# BestSkillUp — hand-off

WoW: Forever add-on that ranks profession recipes by **expected gold per skill point**, using Auctionator prices. Blacksmithing and Cooking. Version 0.7.0, Interface 16001.

- Source (git repo): `C:\Users\User\BestSkillUp`, pushed to the private GitHub repo https://github.com/Aganmar/BestSkillUp
- Install path (managed by WowUp from the GitHub releases): `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\BestSkillUp`

## Releasing

Bump `## Version:` in `BestSkillUp.toc`, commit and push, then either push a matching tag (`git tag v0.5.1 && git push origin v0.5.1`) or press **Run workflow** on the Release workflow in the repo's Actions tab (it tags the commit `v<TOC version>`). The `Release` workflow (`.github/workflows/release.yml`) checks a pushed tag matches the TOC version, builds `BestSkillUp-<tag>-forever.zip` (the TOC and the files it loads, under a `BestSkillUp/` folder) plus a `release.json` (flavor `forever`), and publishes the GitHub release that WowUp installs from.

## How it works

```
expected cost per point = (reagent cost − value of what you make) ÷ chance to skill up
chance (Classic rule)   = orange 100%, grey 0%, yellow/green = (grey − skill) ÷ (grey − yellow)
```

- **Prices**: AH prices come only from Auctionator. Sharing prices between characters is left to a separate add-on that writes into Auctionator (BestSkillUp's own sync, `Sync.lua` and `Tools/SyncAuctionator.ps1`, was removed in 0.7.0).
- **Reagent cost** (`ns.UnitCost`, recursive, memoised, depth ≤ 5): cheapest of manual override → vendor → Auctionator AH → crafting/smelting it from its own reagents → Wowhead average price (fallback, toggle `useWH`).
- **Value of what you make** (`ns.ResaleValue`): `none` / `vendor` (vendor sell price) / `ah` (AH price × (1 − AH cut) × sell-through, or vendor if higher). BoP items always use vendor value.
- **Live colour override** (`ns.Chance`): at your current skill, the game's own recipe difficulty wins if it disagrees with the data.
- **Professions**: each `Data_<Profession>.lua` registers itself with `ns.AddProfessionData` (`Data.lua`). The list shows the *active* profession: the one whose window you last opened (`ns.SetActive`), switchable by clicking the list's title or `/bsu prof`. Reagent crafting (`ns.UnitCost`) looks across every profession's recipes plus Mining smelts.
- **Ranking** (`ns.Evaluate(skill, skillLine)`, both default to the active profession): every usable recipe with chance > 0, sorted by cost per point, then chance, then ID. Recipes with an unpriced reagent sort last. Recipes you know always count; the source and "unlearned" filters only apply to recipes you don't know.

## Files

| File | What it does |
|---|---|
| `BestSkillUp.toc` | Load order: Data → Data_Blacksmithing → Data_Cooking → Core → UI → Native. OptionalDeps Auctionator, EllesmereUI, EllesmereUIBlizzardSkin. SavedVariables `BestSkillUpDB`, per-character `BestSkillUpCharDB`. |
| `Data.lua` | Data registry: `ns.Data.professions[skillLine] = { name, skillLine, recipes }`, `ns.Data.order` (load order), and the merged `ns.Data.items[id] = { name, quality, vendorSell, wowheadAvg }`, `ns.Data.vendor[id]`, `ns.Data.mining` (smelting recipes). |
| `Data_Blacksmithing.lua`, `Data_Cooking.lua` | **Generated, don't hand-edit.** `ns.AddProfessionData{ profession, skillLine, recipes = { [spellID] = { name, outputItemID, minMade, maxMade, orange, yellow, green, grey, source, { reagentID, qty, … } } }, items, vendor[, mining] }`. Blacksmithing is skillLine 164 (and carries Mining 186 smelts), Cooking 185. |
| `Core.lua` | Settings defaults, prices, skill-up maths, evaluation, scanning the open Professions window (known recipes, current skill, live difficulty), events, `/bsu` slash command. |
| `UI.lua` | Suggestion list docked to the Professions window, options panel, item tooltips (comparison tooltips suppressed unless Shift is held), Shift-click → copyable Wowhead URL, EllesmereUI skin via `EllesmereUI.RegisterSkin`. |
| `Native.lua` | Adds lines under the recipe in Blizzard's crafting window: `Skill-up: N%` + coloured thresholds (orange/yellow/green/grey), `Cost Per Point (Vendor)`, and `Cost Per Point (AH)` (omitted for BoP output). Hidden when no skill-up is possible. Hooks `ProfessionsFrame.CraftingPage.SchematicForm:Init`; anchors under Auctionator's crafting-cost frame if present. |
| `Tools/gen_data.py` | Builds a `Data_<Profession>.lua` (see below). |
| `Tools/data/` | Wowhead exports used for the data files (only `cooking.json` so far). |

## Settings (`BestSkillUpDB`)

`resale` (none/vendor/ah, default vendor), `ahCut` 5, `ahSellThrough` 60, `useWH` true, `reagents` {vendor, ah, craft, smelt}, `includeUnlearned` true, `sources` {trainer, vendor, other on; drop, quest off}, `overrides` [itemID] = copper, `point`, `shown`. (`shared`, `partner`, `pushAuctionator` belonged to the price sync removed in 0.7.0 and are cleared on load.)
Per character (`BestSkillUpCharDB`): `profs[skillLine] = { known, scanned, skill, maxSkill }`, `active` (last profession opened), `mining`. Saved data from 0.5.0 (top-level `known`/`skill`/…) is moved into `profs[164]` on load.

## Slash commands

`/bsu` toggle · `prof` (next profession) · `opt` · `resale none/vendor/ah` · `unlearned` · `source <type>` · `wh` · `price <itemID> [copper]` (blank clears) · `debug` (Native.lua state) · `reset` (window position)

## Data generation

```
python3 Tools/gen_data.py Cooking 185 Tools/data/cooking.json Data_Cooking.lua
python3 Tools/gen_data.py Blacksmithing 164 <blacksmithing.json> Data_Blacksmithing.lua <mining.json>
```

The inputs are Wowhead (WoW Forever) exports from the profession's skill page (e.g. `https://www.wowhead.com/forever/skill=185/cooking`): `g_listviews.recipes` (colors, reagents, creates, learnedat, source) and `g_items` (jsonequip buyprice/sellprice/avgbuyout), mapped in the browser console into the shape described at the top of `gen_data.py`. `Tools/data/cooking.json` is kept. **The Blacksmithing and Mining exports weren't kept**, so regenerating Blacksmithing needs them scraped again (its data file was converted to the new format by hand, contents unchanged). Notes:
- Thresholds: orange = colors[0], else learnedat; starter recipes (no orange, no trainer, learnedat ≤ 20) are treated as skill 1. Wowhead's `learnedat` is sometimes wrong (e.g. Rough Sharpening Stone).
- Recipes whose grey threshold is 0 (unfinished Wowhead entries such as Cleansing Stew) are left out.
- Wowhead's `buyprice` is a template value, not proof an item is vendor-sold; vendor items come from the `VENDOR_NAMES` list in the script.
- Wowhead rate-limits fast scraping (CloudFront 403) — fetch slowly or in one request per profession.

## Testing / gotchas

- Adding a file to the TOC needs a **full game restart**, not `/reload`.
- `|` in chat text is a WoW escape code — help text uses `/` instead.
- `StaticPopup` data doesn't pass through on Forever; the Shift-click link uses a custom frame.
- EllesmereUI already skins GameTooltip; the add-on uses its own tooltip frames (`BestSkillUpItemTip`, `BestSkillUpCostTip`) and doesn't re-skin them.
- Logic was tested outside the game with lua5.1 and stubbed WoW APIs; there is no test harness in this folder.

## Open items

1. **Ranking skew (undecided).** With resale on, profitable crafts with a low skill-up chance can outrank reliable ones, because a negative net cost divided by a small chance looks great. Suggested fix: a "profit credit %" setting (count only part of the resale value) plus a "cost per craft" column, so cheap-but-unlikely recipes are visible for what they are.
2. **More professions.** Adding one is: export its Wowhead skill page into `Tools/data/<profession>.json`, run `gen_data.py`, add the file to the TOC (after `Data.lua`, before `Core.lua`), and add any vendor-sold reagents to `VENDOR_NAMES`. Cooking's starter recipes (Charred Wolf Meat, Roasted Boar Meat) have learn levels from Wowhead that are too high; they still show once the Cooking window has been opened, because known recipes always count.
