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
  D.order[#D.order + 1] = t.skillLine
  for id, it in pairs(t.items or {}) do D.items[id] = D.items[id] or it end
  for id, p in pairs(t.vendor or {}) do D.vendor[id] = D.vendor[id] or p end
  for id, r in pairs(t.mining or {}) do D.mining[id] = r end
  if t.miningSkillLine then D.miningSkillLine = t.miningSkillLine end
end
