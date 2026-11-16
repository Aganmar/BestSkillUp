-- Shared data registry. Each generated Data_<Profession>.lua calls ns.AddProfessionData{...}.
--   D.professions[skillLine] = { name, skillLine, recipes = { [spellID] = recipe } }
--   D.items / D.vendor / D.mining are merged from every data file.
local _, ns = ...

local D = { professions = {}, order = {}, items = {}, vendor = {}, mining = {}, miningSkillLine = 186 }
ns.Data = D

-- Disenchanting results by item level (Classic tables, which WoW: Forever's guides repeat):
--   { minItemLevel, maxItemLevel, dustID, dustMin, dustMax, essenceID, essenceMin, essenceMax, shardID, nexusCrystal }
-- Uncommon armour: 75% dust, 20% essence, 5% shard; uncommon weapons swap dust and essence.
-- Rare: the shard (0.5% Nexus Crystal where listed). Epic: 2-4 shards up to item level 55, a Nexus Crystal above.
-- Sources: https://www.wow-professions.com/forever/disenchanting-guide , https://warcraft.wiki.gg/wiki/Disenchanting_tables
D.disenchant = {
  {  5, 10, 10940, 1, 2, 10938, 1, 2, nil },     -- Strange Dust, Lesser Magic Essence
  { 11, 15, 10940, 2, 3, 10939, 1, 2, 10978 },   -- Strange Dust, Greater Magic Essence, Small Glimmering Shard
  { 16, 20, 10940, 4, 6, 10998, 1, 2, 10978 },   -- Strange Dust, Lesser Astral Essence, Small Glimmering Shard
  { 21, 25, 11083, 1, 2, 11082, 1, 2, 11084 },   -- Soul Dust, Greater Astral Essence, Large Glimmering Shard
  { 26, 30, 11083, 2, 5, 11134, 1, 2, 11138 },   -- Soul Dust, Lesser Mystic Essence, Small Glowing Shard
  { 31, 35, 11137, 1, 2, 11135, 1, 2, 11139 },   -- Vision Dust, Greater Mystic Essence, Large Glowing Shard
  { 36, 40, 11137, 2, 5, 11174, 1, 2, 11177 },   -- Vision Dust, Lesser Nether Essence, Small Radiant Shard
  { 41, 45, 11176, 1, 2, 11175, 1, 2, 11178 },   -- Dream Dust, Greater Nether Essence, Large Radiant Shard
  { 46, 50, 11176, 2, 5, 16202, 1, 2, 14343 },   -- Dream Dust, Lesser Eternal Essence, Small Brilliant Shard
  { 51, 55, 16204, 1, 2, 16203, 1, 2, 14344, true }, -- Illusion Dust, Greater Eternal Essence, Large Brilliant Shard
  { 56, 999, 16204, 2, 5, 16203, 1, 3, 14344, true },
}
D.NEXUS_CRYSTAL = 20725

function ns.AddProfessionData(t)
  D.professions[t.skillLine] = { name = t.profession, skillLine = t.skillLine, recipes = t.recipes or {} }
  D.order[#D.order + 1] = t.skillLine
  for id, it in pairs(t.items or {}) do D.items[id] = D.items[id] or it end
  for id, p in pairs(t.vendor or {}) do D.vendor[id] = D.vendor[id] or p end
  for id, r in pairs(t.mining or {}) do D.mining[id] = r end
  if t.miningSkillLine then D.miningSkillLine = t.miningSkillLine end
end
