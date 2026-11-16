-- Shared data registry. Each generated Data_<Profession>.lua calls ns.AddProfessionData{...}.
--   D.professions[skillLine] = { name, skillLine, recipes = { [spellID] = recipe } }
--   D.items / D.vendor / D.mining are merged from every data file.
local _, ns = ...

local D = { professions = {}, order = {}, items = {}, vendor = {}, mining = {}, miningSkillLine = 186 }
ns.Data = D

function ns.AddProfessionData(t)
  D.professions[t.skillLine] = { name = t.profession, skillLine = t.skillLine, recipes = t.recipes or {} }
  D.order[#D.order + 1] = t.skillLine
  for id, it in pairs(t.items or {}) do D.items[id] = D.items[id] or it end
  for id, p in pairs(t.vendor or {}) do D.vendor[id] = D.vendor[id] or p end
  for id, r in pairs(t.mining or {}) do D.mining[id] = r end
  if t.miningSkillLine then D.miningSkillLine = t.miningSkillLine end
end
