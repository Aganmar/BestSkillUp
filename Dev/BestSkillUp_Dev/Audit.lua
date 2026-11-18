-- BestSkillUp_Dev: /bsu audit. With a profession window open, saves every recipe the game has for it (learned or
-- not) with what it makes, its reagents and, if the game gives one, its source text and colour, into
-- BestSkillUpDB.audit[skillLine]. Then compares that with BestSkillUp's data and prints what differs.
-- Claude reads the saved snapshot to find recipes Wowhead hasn't found and reagent / output changes.
local ns = BestSkillUpAPI
if not ns then return end

local T = C_TradeSkillUI
local DIFF = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "grey" }

local function openLine()
  if not (T and T.GetBaseProfessionInfo) then return end
  local ok, info = pcall(T.GetBaseProfessionInfo)
  if not ok or not info then return end
  local D = ns.Data.professions
  if D[info.professionID] then return info.professionID, info end
  if D[info.parentProfessionID] then return info.parentProfessionID, info end
  return info.professionID, info   -- a profession BSU has no data for: still worth a snapshot
end

local function schematic(id)
  if not T.GetRecipeSchematic then return end
  local ok, s = pcall(T.GetRecipeSchematic, id, false)
  if not ok or type(s) ~= "table" then return end
  local reag = {}
  for _, slot in ipairs(s.reagentSlotSchematics or {}) do
    local r = slot.reagents and slot.reagents[1]
    if r and r.itemID and (slot.reagentType == nil or slot.reagentType == 1 or slot.required) then
      reag[#reag + 1] = r.itemID; reag[#reag + 1] = slot.quantityRequired or 1
    end
  end
  return s.outputItemID or 0, s.quantityMin or 1, s.quantityMax or s.quantityMin or 1, reag
end

local function sourceText(id)
  if not T.GetRecipeSourceText then return end
  local ok, txt = pcall(T.GetRecipeSourceText, id)
  if ok and type(txt) == "string" and txt ~= "" then return (txt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
end

local function sameReagents(a, b)   -- a: { id, qty, ... } from the game; b: BSU recipe reagents { id, qty, ... }
  if #a ~= #b then return false end
  local want = {}
  for i = 1, #b, 2 do want[b[i]] = b[i + 1] end
  for i = 1, #a, 2 do if want[a[i]] ~= a[i + 1] then return false end end
  return true
end

local function audit()
  local line, info = openLine()
  if not line then ns.Print("Open a profession window first, then /bsu audit."); return end
  if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then ns.Print("That's someone else's profession link: open your own."); return end
  local ids = T.GetAllRecipeIDs and T.GetAllRecipeIDs() or {}
  local snap = { t = time(), skill = info.skillLevel, max = info.maxSkillLevel, name = info.professionName, recipes = {} }
  local P = ns.Data.professions[line]
  local R = P and P.recipes or {}
  local n, learned, missing, reagDiff, outDiff, noSchem = 0, 0, {}, {}, {}, 0
  for _, id in ipairs(ids) do
    local ok, ri = pcall(T.GetRecipeInfo, id)
    if ok and ri then
      n = n + 1
      if ri.learned then learned = learned + 1 end
      local out, lo, hi, reag = schematic(id)
      if not out then noSchem = noSchem + 1 end
      snap.recipes[id] = { name = ri.name, learned = ri.learned and true or false,
        colour = ri.learned and DIFF[ri.relativeDifficulty] or nil, out = out, lo = lo, hi = hi, reag = reag,
        source = (not ri.learned) and sourceText(id) or nil }
      local r = R[id]
      if not r and not (ns.Data.mining and ns.Data.mining[id]) then
        missing[#missing + 1] = ri.name
      elseif r and out then
        if reag and #reag > 0 and not sameReagents(reag, r[10] or {}) then reagDiff[#reagDiff + 1] = ri.name end
        if out ~= 0 and r[2] ~= 0 and (out ~= r[2] or lo ~= r[3] or hi ~= r[4]) then outDiff[#outDiff + 1] = ri.name end
      end
    end
  end
  ns.DB.audit = ns.DB.audit or {}
  ns.DB.audit[line] = snap
  ns.Print(("Audit of %s (%s/%s): %d recipes in game, %d learned%s. Saved for Claude: /reload to write it to disk.")
    :format(info.professionName or line, tostring(info.skillLevel), tostring(info.maxSkillLevel), n, learned,
      noSchem > 0 and (", " .. noSchem .. " without details") or ""))
  local function list(label, t)
    if #t == 0 then return end
    table.sort(t)
    local shown = {}
    for i = 1, math.min(#t, 8) do shown[i] = t[i] end
    ns.Print(("  %s %d: %s%s"):format(label, #t, table.concat(shown, ", "), #t > 8 and ", ..." or ""))
  end
  list("Not in BSU's data", missing)
  list("Different reagents", reagDiff)
  list("Different output", outDiff)
  if #missing + #reagDiff + #outDiff == 0 then ns.Print("  Everything the game lists matches BSU's data.") end
end

local prev = ns.DevSlash
function ns.DevSlash(cmd, rest)
  if cmd == "audit" then audit(); return true end
  return prev and prev(cmd, rest) or false
end
ns.DevHelp = (ns.DevHelp or "") .. "audit  "
