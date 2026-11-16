<p align="center"><img src="Media/BestSkillUp_400.png" width="128" alt="BestSkillUp icon"></p>

<h1 align="center">BestSkillUp</h1>

Find the **cheapest way to level your professions** in **World of Warcraft: Forever**. BestSkillUp ranks every recipe you can make by its expected gold cost per skill point, using your [Auctionator](https://www.curseforge.com/wow/addons/auctionator) prices.

Open your profession window and the ranked list appears beside it, with the best recipe to craft right now at the top. Supports **Blacksmithing**, **Mining** (smelting), **Enchanting**, **Cooking** and **First Aid**.

## Features

- **Cost per skill point** – every recipe is ranked by what a point really costs you, counting the chance that a yellow or green recipe gives no point at all.
- **Cheapest reagents** – each reagent is priced the cheapest way you can get it: vendor, Auction House, or crafting or smelting it yourself (bars are priced from ore when your Mining skill can smelt them).
- **Resale value** – optionally counts what you get back for the item you make (vendor price, or AH price after the cut and a sell-through rate).
- **In the crafting window** – under each recipe: your skill-up chance, the orange/yellow/green/grey thresholds, and the cost per point with vendor and AH resale.
- **Follows your profession** – the list switches to whichever profession window you open; click its title (or `/bsu prof`) to switch by hand.
- **Live recipe colours** – at your current skill, the game's own recipe colour wins if it disagrees with the data.
- **Knows what you've learned** – recipes you know always appear; choose whether to also suggest unlearned recipes, and from which sources (trainer, vendor, drop, quest).
- **Your own prices** – set a manual price for any item with `/bsu price`.
- **Tooltips** – hover a row for the full cost breakdown; Shift-click for a Wowhead link you can copy.
- **EllesmereUI styling** when installed.

## Install

**WowUp:** Get Addons → Install from URL → `https://github.com/Aganmar/BestSkillUp`. WowUp picks up new releases automatically.

**Manually:** download `BestSkillUp-<version>-forever.zip` from [Releases](https://github.com/Aganmar/BestSkillUp/releases), copy the `BestSkillUp` folder into `World of Warcraft\_forever_\Interface\AddOns\` and restart the game.

Auctionator is optional but recommended: without it, BestSkillUp falls back to vendor and Wowhead prices. To share prices between characters or players, use an add-on that writes into Auctionator, such as [ScanShare](https://github.com/Aganmar/ScanShare).

## Commands

| Command | |
|---|---|
| `/bsu` | Show or hide the list |
| `/bsu prof` | Switch to the next profession |
| `/bsu opt` | Options |
| `/bsu resale none\|vendor\|ah` | How to value what you make |
| `/bsu unlearned` | Also suggest recipes you haven't learned |
| `/bsu source trainer\|vendor\|drop\|quest\|other` | Include or exclude recipes by where they're learned |
| `/bsu wh` | Use Wowhead average prices when Auctionator has none |
| `/bsu price <itemID> [copper]` | Set your own price for an item (blank clears it) |
| `/bsu debug` | Show what the crafting-window lines are doing |
| `/bsu reset` | Reset the window position |

## How it works

```
cost per point = (reagent cost − value of what you make) ÷ chance to skill up
```

| Recipe colour | Chance to skill up |
|---|---|
| Orange | 100% |
| Yellow / green | Falls in a straight line from 100% at the yellow threshold to 0% at grey |
| Grey | 0% (not listed) |

Each reagent costs the cheapest of:

| Source | |
|---|---|
| Manual | Your own price from `/bsu price` (always wins) |
| Vendor | Auctionator's vendor price, else the built-in list |
| Auction House | Your Auctionator price |
| Craft / smelt | The cost of making it yourself, if you know the recipe (or could learn it from a trainer) |
| Wowhead average | Last resort when nothing else has a price (`/bsu wh` turns it off) |

Recipes with a reagent that has no price at all sort to the bottom.

## License

BestSkillUp is free software under the [GNU General Public License v3.0](LICENSE).

## Credits

- Recipe data (skill thresholds, reagents, item prices) from [Wowhead's WoW: Forever database](https://www.wowhead.com/forever). It can be off for some recipes.
- Prices from [Auctionator](https://www.curseforge.com/wow/addons/auctionator).
- For developers: [HANDOFF.md](HANDOFF.md) covers the code layout, data generation and releases.
