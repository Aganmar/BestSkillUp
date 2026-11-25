# Changelog

## 0.15.0
- **Profit tab:** every recipe you can craft, ranked by profit per craft, at any skill (`/bsu profit`). At max skill (150/150, 300/300 ...) the Skill-ups tab is hidden and Profit shows instead; tick **Skill-ups at max** in Options (or `/bsu max`) to keep it.
- Column headers under the tabs: Item / Skill-up % / Cost per point, Item / Profit per craft, and Recipe / Learned at / Source.
- Recipe data re-checked against Wowhead: no recipes, colours, reagents or amounts changed. 44 recipes have updated sources, mostly newly listed as drops, so they now follow the Drop source filter (off by default for recipes you don't know).
- Enchanting wands and oils that Wowhead lists with an amount of 0 now count as making 1, like the other professions.

## 0.14.0
- New professions: **Alchemy**, **Tailoring** and **Engineering**. BestSkillUp now covers every crafting profession.
- **Specializations:** once you've learned Armorsmith or Weaponsmith (and a master weaponsmith school), a Leatherworking school, or Gnomish or Goblin Engineering, plans for the rival specializations are no longer suggested. Before you specialise, everything is still shown, with a "Needs ..." note in the tooltip.
- **Arcane Salvager:** a new option in Options. When ticked, disenchant values include the Salvager's bonus (a 30% chance that dust or essence comes out at one more than the normal maximum, measured in game).
- **Master Chef:** set your rank of the Legacy talent (Options, or `/bsu chef 0-5`) and cooking counts 10% more food per craft per rank.
- **Recipes tab:** switch from Skill-ups to Recipes at the top of the window to see every recipe of the profession, with where it's learned. Show All, Owned or Missing; Shift-click a recipe for its Wowhead link.
- Blacksmithing data refreshed from Wowhead and checked against the game: every recipe matches.
- Colour corrections now only move the thresholds your own scans contradict, instead of shifting the whole recipe.
- Picking a profession by clicking the title now sticks; the list only follows the crafting window when you open or change professions.

## 0.13.1
- Packaging fix: a testing file is no longer included in the download.

## 0.13.0
- New profession: **Leatherworking**.

## 0.12.0
- **Working Overtime:** set your rank of the Legacy talent (Options, or `/bsu overtime 0-5`). Each rank reduces the chance that a yellow or green craft gives no point by 4%.

## 0.11.0
- **Learns the real thresholds:** the recipe colours the game shows are remembered for all your characters and used to correct Wowhead's orange/yellow/green/grey levels where WoW: Forever differs.

## 0.10.3
- Item tooltips show the Auctionator price.

## 0.10.2
- The suggestion list scrolls, so you can see every option, not just the top 16.

## 0.10.1
- Disenchant values use item-level tables. Items made by Enchanting aren't counted, and bind-on-pickup items only count when the character has Enchanting.

## 0.10.0
- **Disenchant value:** green, blue and purple items you make are valued by what they disenchant into, whenever that beats selling them.

## 0.9.1
- Below Enchanting 60, Disenchant sits at the top of the Enchanting list at no cost.

## 0.9.0
- New profession: **Enchanting**.

## 0.8.0
- New professions: **Mining** (smelting) and **First Aid**.

## 0.7.2
- Licensed under the GNU GPL v3.

## 0.7.1
- New icon.

## 0.7.0
- Removed the built-in price sharing between characters. Prices come from Auctionator, so use an add-on that shares Auctionator prices, such as ScanShare.

## 0.6.0
- First public release: Blacksmithing and Cooking, ranked by cost per skill point with Auctionator prices.
