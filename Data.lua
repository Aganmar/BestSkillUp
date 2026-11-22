-- Shared data registry. Each generated Data_<Profession>.lua calls ns.AddProfessionData{...}.
--   D.professions[skillLine] = { name, skillLine, recipes = { [spellID] = recipe } }
--   D.items / D.vendor / D.mining are merged from every data file.
local _, ns = ...

local D = { professions = {}, order = {}, items = {}, vendor = {}, mining = {}, miningSkillLine = 186 }
ns.Data = D

-- Disenchanting results by ITEM level (Classic), from https://warcraft.wiki.gg/wiki/Disenchanting_tables
-- Each row: { minItemLevel, maxItemLevel, { chance%, minQty, maxQty, itemID }, ... }
-- WoW: Forever has no Burning Crusade materials, so the top rows also cover item levels above 65.
local SD, SOUL, VIS, DREAM, ILL = 10940, 11083, 11137, 11176, 16204           -- dusts
local LME, GME, LAE, GAE, LMY, GMY = 10938, 10939, 10998, 11082, 11134, 11135 -- essences
local LNE, GNE, LEE, GEE = 11174, 11175, 16202, 16203
local SGS, LGS, SGL, LGL, SRS, LRS, SBS, LBS = 10978, 11084, 11138, 11139, 11177, 11178, 14343, 14344 -- shards
local NEXUS = 20725
D.disenchant = {
  armor = {   -- uncommon armour
    {  5, 15, { 80, 1, 2, SD },    { 20, 1, 2, LME } },
    { 16, 20, { 75, 2, 3, SD },    { 20, 1, 2, GME }, { 5, 1, 1, SGS } },
    { 21, 25, { 75, 4, 6, SD },    { 15, 1, 2, LAE }, { 10, 1, 1, SGS } },
    { 26, 30, { 75, 1, 2, SOUL },  { 20, 1, 2, GAE }, { 5, 1, 1, LGS } },
    { 31, 35, { 75, 2, 5, SOUL },  { 20, 1, 2, LMY }, { 5, 1, 1, SGL } },
    { 36, 40, { 75, 1, 2, VIS },   { 20, 1, 2, GMY }, { 5, 1, 1, LGL } },
    { 41, 45, { 75, 2, 5, VIS },   { 20, 1, 2, LNE }, { 5, 1, 1, SRS } },
    { 46, 50, { 75, 1, 2, DREAM }, { 20, 1, 2, GNE }, { 5, 1, 1, LRS } },
    { 51, 55, { 75, 2, 5, DREAM }, { 20, 1, 2, LEE }, { 5, 1, 1, SBS } },
    { 56, 60, { 75, 1, 2, ILL },   { 20, 1, 2, GEE }, { 5, 1, 1, LBS } },
    { 61, 999, { 75, 2, 5, ILL },  { 20, 2, 3, GEE }, { 5, 1, 1, LBS } },
  },
  weapon = {  -- uncommon weapons
    {  6, 15, { 20, 1, 2, SD },    { 80, 1, 2, LME } },
    { 16, 20, { 20, 2, 3, SD },    { 75, 1, 2, GME }, { 5, 1, 1, SGS } },
    { 21, 25, { 15, 4, 6, SD },    { 75, 1, 2, LAE }, { 10, 1, 1, SGS } },
    { 26, 30, { 20, 1, 2, SOUL },  { 75, 1, 2, GAE }, { 5, 1, 1, LGS } },
    { 31, 35, { 20, 2, 5, SOUL },  { 75, 1, 2, LMY }, { 5, 1, 1, SGL } },
    { 36, 40, { 20, 1, 2, VIS },   { 75, 1, 2, GMY }, { 5, 1, 1, LGL } },
    { 41, 45, { 20, 2, 5, VIS },   { 75, 1, 2, LNE }, { 5, 1, 1, SRS } },
    { 46, 50, { 20, 1, 2, DREAM }, { 75, 1, 2, GNE }, { 5, 1, 1, LRS } },
    { 51, 55, { 22, 2, 5, DREAM }, { 75, 1, 2, LEE }, { 3, 1, 1, SBS } },
    { 56, 60, { 22, 1, 2, ILL },   { 75, 1, 2, GEE }, { 3, 1, 1, LBS } },
    { 61, 999, { 22, 2, 5, ILL },  { 75, 2, 3, GEE }, { 3, 1, 1, LBS } },
  },
  rare = {    -- armour and weapons alike
    {  1, 25, { 100, 1, 1, SGS } },
    { 26, 30, { 100, 1, 1, LGS } },
    { 31, 35, { 100, 1, 1, SGL } },
    { 36, 40, { 100, 1, 1, LGL } },
    { 41, 45, { 100, 1, 1, SRS } },
    { 46, 50, { 100, 1, 1, LRS } },
    { 51, 55, { 100, 1, 1, SBS } },
    { 56, 999, { 99.5, 1, 1, LBS }, { 0.5, 1, 1, NEXUS } },
  },
  epic = {
    { 40, 45, { 100, 2, 4, SRS } },
    { 46, 50, { 100, 2, 4, LRS } },
    { 51, 55, { 100, 2, 4, SBS } },
    { 56, 60, { 100, 1, 1, NEXUS } },
    { 61, 999, { 100, 1, 2, NEXUS } },
  },
}

function ns.AddProfessionData(t)
  D.professions[t.skillLine] = { name = t.profession, skillLine = t.skillLine, recipes = t.recipes or {} }
  if t.skillLine == 185 then for _, r in pairs(t.recipes or {}) do r.cook = true end end   -- Master Chef applies
  D.order[#D.order + 1] = t.skillLine
  for id, it in pairs(t.items or {}) do D.items[id] = D.items[id] or it end
  for id, p in pairs(t.vendor or {}) do D.vendor[id] = D.vendor[id] or p end
  for id, r in pairs(t.mining or {}) do D.mining[id] = r end
  if t.miningSkillLine then D.miningSkillLine = t.miningSkillLine end
end

-- Specialization plans (Wowhead's "specialization" field, WoW: Forever, 2026-11-19): spell the recipe needs.
-- Blacksmithing: Weaponsmith 9787 / Armorsmith 9788, and the Weaponsmith masters Swordsmith 17039,
-- Hammersmith 17040, Axesmith 17041. Leatherworking: Dragonscale 10656 / Elemental 10658 / Tribal 10660.
-- Engineering: Gnomish 20219 / Goblin 20222.
D.specNames = { [9787] = "Weaponsmith", [9788] = "Armorsmith", [17039] = "Master Swordsmith", [17040] = "Master Hammersmith",
  [17041] = "Master Axesmith", [10656] = "Dragonscale Leatherworking", [10658] = "Elemental Leatherworking",
  [10660] = "Tribal Leatherworking", [20219] = "Gnomish Engineering", [20222] = "Goblin Engineering" }
D.specOf = {}
for spell, ids in pairs({
  [9787] = { 23638, 23639, 16995, 15294, 15292, 10015, 10011, 10007, 10003 },
  [9788] = { 24399, 23637, 23636, 20876, 16745, 16742, 16744, 20873, 16729, 16741, 27829, 16724, 20874, 20872, 16660,
    16655, 15296, 16667, 9974, 9954 },
  [17039] = { 16990, 20890, 16992, 27832, 23652, 16985, 16978 },
  [17040] = { 16988, 16993, 27830, 23650, 16983, 16973 },
  [17041] = { 16994, 20897, 16991, 23653, 16970 },
  [10656] = { 20855, 22926, 23708, 24654, 19107, 19054, 24655, 19094, 19089, 19085, 19077, 10650, 19060, 19050, 10619 },
  [10658] = { 23710, 20854, 22928, 16746, 16661, 19095, 26279, 19101, 19090, 19078, 19079, 19076, 19067, 19061, 19059,
    10632, 10630 },
  [20219] = { 12759, 12895, 12897, 12899, 12902, 12903, 12905, 12906, 12907, 15633, 23096, 23129, 23489 },
  [20222] = { 8895, 12715, 12716, 12717, 12718, 12754, 12755, 12758, 12760, 12908, 13240, 15628, 23078, 23486 },
  [10660] = { 23709, 22927, 16728, 20853, 19097, 19104, 19087, 16650, 19081, 19084, 19086, 19074, 19080, 19073, 19063,
    19066, 19068, 19062, 19053, 10647, 10621 },
}) do
  for _, id in ipairs(ids) do D.specOf[id] = spell end
end
