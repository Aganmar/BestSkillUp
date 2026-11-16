-- BestSkillUp: ranks recipes by expected gold per skill point.
--   expected cost per point = (reagent cost - value of what you make) / chance to skill up
--   chance (Classic rule): orange 100%, grey 0%, yellow/green = (grey - skill) / (grey - yellow)
-- Reagents are costed at the cheapest of: vendor, Auctionator AH price, or crafting/smelting them (recursively).
-- Professions: every Data_<Profession>.lua registers itself in ns.Data.professions (see Data.lua).

local ADDON, ns = ...
local CALLER = "BestSkillUp"
local D = ns.Data
ns.CALLER = CALLER

local DEFAULTS = {
  resale = "vendor",          -- "none" | "vendor" | "ah"
  ahCut = 5,                  -- %
  ahSellThrough = 60,         -- % of AH price you realistically get
  useWH = true,               -- fall back to Wowhead avg price when Auctionator has none
  reagents = { vendor = true, ah = true, craft = true, smelt = true },
  includeUnlearned = true,    -- also suggest recipes you haven't learned yet
  sources = { trainer = true, vendor = true, drop = false, quest = false, other = true },
  overrides = {},             -- [itemID] = copper
  disenchant = nil,           -- count disenchant value of what you make: nil = if this character has Enchanting, or true/false
  point = nil,                -- saved window position
  seen = {},                  -- [spellID] = { [difficulty] = { lowSkill, highSkill } }: colours the game showed (all characters)
  shown = true,
}
-- profs[skillLine] = { known = { [spellID] = true }, scanned, skill, maxSkill }; active = last profession opened
local CHAR_DEFAULTS = { profs = {}, mining = nil, active = nil, overtime = 0 }   -- overtime: Working Overtime rank (Legacy talent)

local DB, CDB
ns.live = { diff = {}, craftable = {}, at = nil, line = nil }   -- live data from the open Professions window

-- ---------------------------------------------------------------- utils
local function copyDefaults(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      if type(v) == "table" then dst[k] = {}; copyDefaults(dst[k], v) else dst[k] = v end
    elseif type(v) == "table" and type(dst[k]) == "table" then
      copyDefaults(dst[k], v)
    end
  end
end

function ns.Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffe8c35aBestSkillUp|r: " .. tostring(msg)) end

function ns.Money(c, signed)
  if c == nil or c ~= c or c == math.huge then return "|cff808080--|r" end
  local neg = c < 0
  c = math.floor(math.abs(c) + 0.5)
  local g, s, cc = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
  local out = ""
  if g > 0 then out = out .. "|cffffd700" .. g .. "g|r " end
  if g > 0 or s > 0 then out = out .. "|cffc7c7cf" .. s .. "s|r " end
  out = out .. "|cffc87533" .. cc .. "c|r"
  if neg then return "|cff40c040-|r" .. out end
  return (signed and "+" or "") .. out
end

function ns.ItemName(id)
  local it = D.items[id]
  if it then return it[1] end
  local name = (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id)) or (GetItemInfo and GetItemInfo(id))
  return name or ("item:" .. tostring(id))
end

function ns.ItemColor(id)
  local q = D.items[id] and D.items[id][2] or 1
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  return c and c.hex or "|cffffffff"
end

-- ---------------------------------------------------------------- professions
-- Per-character state for one profession (the active one by default).
function ns.Prof(line)
  line = line or ns.active
  local p = CDB.profs[line]
  if not p then p = { known = {}, scanned = false }; CDB.profs[line] = p end
  return p
end

function ns.ProfName(line)
  local P = D.professions[line or ns.active]
  return P and P.name or "?"
end

-- Recipe data and profession for a spell ID, from any profession.
function ns.FindRecipe(id)
  if not id then return end
  for line, P in pairs(D.professions) do
    local r = P.recipes[id]
    if r then return r, line end
  end
end

-- Which profession the list shows: the last one opened, else one this character has, else the first.
local function pickActive()
  if CDB.active and D.professions[CDB.active] then return CDB.active end
  for _, line in ipairs(D.order) do
    if CDB.profs[line] and CDB.profs[line].skill then return line end
  end
  return D.order[1]
end

function ns.SetActive(line)
  if not D.professions[line] then return end
  ns.active = line
  CDB.active = line
end

-- Next profession in load order (for the list's title button and /bsu prof).
function ns.CycleActive()
  local n = #D.order
  for i, line in ipairs(D.order) do
    if line == ns.active then ns.SetActive(D.order[i % n + 1]); return end
  end
  ns.SetActive(D.order[1])
end

-- Saved data from before Cooking was added was Blacksmithing-only.
local function migrate()
  if CDB.known or CDB.skill then
    local p = CDB.profs[164] or {}
    p.known = p.known or CDB.known or {}
    if p.scanned == nil then p.scanned = CDB.scanned end
    p.skill = p.skill or CDB.skill
    p.maxSkill = p.maxSkill or CDB.maxSkill
    CDB.profs[164] = p
  end
  CDB.known, CDB.scanned, CDB.skill, CDB.maxSkill = nil, nil, nil, nil
end

-- ---------------------------------------------------------------- recipe maths
-- recipe = { name, out, minMade, maxMade, orange, yellow, green, grey, source, reagents }
function ns.Thresholds(r) return r[5], r[6], r[7], r[8] end
function ns.Made(r) return (r[3] + r[4]) / 2 end

function ns.Colour(r, s)
  local _, y, g, gr = r[5], r[6], r[7], r[8]
  if s >= gr then return "grey" elseif s >= g then return "green" elseif s >= y then return "yellow" end
  return "orange"
end

local LIVE_FALLBACK = { [0] = 1, [1] = 0.75, [2] = 0.25, [3] = 0 } -- optimal / medium / easy / trivial

local baseChance
-- Working Overtime (Legacy talent, per character): 4% per rank. It takes that share off the chance of
-- NOT getting a point: 1 - (1 - p) * (1 - 0.04 * rank), so 80% -> 84% and 10% -> 28% at 5/5.
-- (Measured: Lesser Magic Wand 100->115 took 52 crafts at 5/5; x1.2 predicts ~111, this ~44.)
-- Orange stays 100%, grey stays 0%.
function ns.OvertimeRank() return CDB and math.max(0, math.min(5, tonumber(CDB.overtime) or 0)) or 0 end
function ns.OvertimeBonus() return 0.04 * ns.OvertimeRank() end
function ns.Chance(id, r, s, line)
  local p = baseChance(id, r, s, line)
  if p > 0 and p < 1 then p = 1 - (1 - p) * (1 - ns.OvertimeBonus()) end
  return p
end

function baseChance(id, r, s, line)
  local _, y, _, gr = r[5], r[6], r[7], r[8]
  local p
  if s >= gr then p = 0
  elseif s < y then p = 1
  elseif gr <= y then p = 0
  else p = (gr - s) / (gr - y) end
  if p < 0 then p = 0 elseif p > 1 then p = 1 end
  -- At your current skill the game's own colour wins if it disagrees with the data.
  local live = ns.live.diff[id]
  line = line or ns.active
  if live ~= nil and CDB and ns.live.line == line and s == ns.Prof(line).skill then
    if live == 3 then return 0 end
    if p == 0 then return LIVE_FALLBACK[live] or 0 end
    if live == 0 then return 1 end
  end
  return p
end

-- ---------------------------------------------------------------- colours learned from the game
-- Wowhead's thresholds are sometimes wrong for WoW: Forever (Mithril Spurs is trained at 215, not 235).
-- Every scan records each known recipe's colour at that skill (0 orange, 1 yellow, 2 green, 3 grey);
-- the recipe's thresholds are then moved to fit everything seen. r.base keeps Wowhead's values.
local function clamp(v, lo, hi)
  if lo and v < lo then v = lo end
  if hi and v > hi then v = hi end
  return v
end
local function mn(a, b) if a == nil then return b elseif b == nil then return a end return math.min(a, b) end
local function mx(a, b) if a == nil then return b elseif b == nil then return a end return math.max(a, b) end

function ns.ApplySeen(id)
  local S = DB.seen[id]
  local r = S and ns.FindRecipe(id)
  if not r then return end
  if not r.base then r.base = { r[5], r[6], r[7], r[8] } end
  local o, y, g, gr = r.base[1], r.base[2], r.base[3], r.base[4]
  local lo = function(d) return S[d] and S[d][1] end
  local hi = function(d) return S[d] and S[d][2] end
  -- Known at a lower skill than Wowhead's learn level: shift the whole recipe down (a first guess).
  local first = mn(mn(lo(0), lo(1)), mn(lo(2), lo(3)))
  if first and first < o then
    local shift = o - first
    o, y, g, gr = first, y - shift, g - shift, gr - shift
  end
  -- Then fit what was seen: orange below yellow, yellow below green, green below grey.
  y = clamp(math.max(y, o), mx(nil, hi(0) and hi(0) + 1), mn(mn(lo(1), lo(2)), lo(3)))
  g = clamp(math.max(g, y), mx(hi(0), hi(1)) and mx(hi(0), hi(1)) + 1, mn(lo(2), lo(3)))
  gr = clamp(math.max(gr, g), mx(mx(hi(0), hi(1)), hi(2)) and mx(mx(hi(0), hi(1)), hi(2)) + 1, lo(3))
  r[5], r[6], r[7], r[8] = o, y, g, gr
  r.corrected = (o ~= r.base[1] or y ~= r.base[2] or g ~= r.base[3] or gr ~= r.base[4]) or nil
end

local function recordSeen(id, d, s)
  if d == nil or s == nil or not ns.FindRecipe(id) then return end
  local S = DB.seen[id] or {}
  DB.seen[id] = S
  local e = S[d]
  if e then
    if s < e[1] then e[1] = s end
    if s > e[2] then e[2] = s end
  else
    S[d] = { s, s }
  end
end

-- ---------------------------------------------------------------- prices
local function AuctionatorAPI()
  return Auctionator and Auctionator.API and Auctionator.API.v1
end

local function ownAHPrice(id)
  local A = AuctionatorAPI()
  if A and A.GetAuctionPriceByItemID then
    local ok, p = pcall(A.GetAuctionPriceByItemID, CALLER, id)
    if ok and type(p) == "number" and p > 0 then return p end
  end
end

-- Auctionator's price for the item (shared prices from other add-ons arrive through Auctionator).
function ns.AHPrice(id)
  return ownAHPrice(id)
end

function ns.VendorPrice(id)
  local A = AuctionatorAPI()
  if A and A.GetVendorPriceByItemID then
    local ok, p = pcall(A.GetVendorPriceByItemID, CALLER, id)
    if ok and type(p) == "number" and p > 0 then return p end
  end
  local v = D.vendor[id]
  if v and v > 0 then return v end
end

function ns.SellPrice(id)
  local sell
  if C_Item and C_Item.GetItemInfo then sell = select(11, C_Item.GetItemInfo(id))
  elseif GetItemInfo then sell = select(11, GetItemInfo(id)) end
  if not sell or sell == 0 then sell = D.items[id] and D.items[id][3] or 0 end
  return sell
end

-- Which recipes produce which item (every profession's recipes + Mining smelts).
local MAKERS = {}
local function addMaker(id, r, kind)
  if r[2] > 0 then MAKERS[r[2]] = MAKERS[r[2]] or {}; table.insert(MAKERS[r[2]], { id = id, r = r, kind = kind }) end
end
-- Disenchant: free (you disenchant an item you already have), always first in the Enchanting list
-- while it can still give a point. WoW: Forever's odds aren't published; these are the Classic ones:
-- a point every time up to 20, less often from 40, none from 60.
ns.DISENCHANT = 13262
local function addDisenchant()
  local P = D.professions[333]
  if not P then return end
  local r = { "Disenchant", 0, 1, 1, 1, 20, 40, 60, "trainer", {} }
  r.pinned = true
  P.recipes[ns.DISENCHANT] = r
end

local function indexMakers()
  for line, P in pairs(D.professions) do for id, r in pairs(P.recipes) do addMaker(id, r, line) end end
  -- The Blacksmithing file's own smelt table is only a fallback for when Mining's data isn't loaded.
  if not D.professions[D.miningSkillLine] then
    for id, r in pairs(D.mining) do addMaker(id, r, "mining") end
  end
end

-- Can you make this intermediate yourself right now?
local function canMake(m)
  if m.kind == "mining" or m.kind == D.miningSkillLine then
    if not DB.reagents.smelt then return false end
    local P = ns.Prof(D.miningSkillLine)
    if P.known[m.id] then return true end
    local skill = P.skill or CDB.mining
    return skill ~= nil and skill >= m.r[5]
  end
  if not DB.reagents.craft then return false end
  local P = ns.Prof(m.kind)
  if P.known[m.id] then return true end
  return DB.includeUnlearned and m.r[9] == "trainer" and P.skill ~= nil and P.skill >= m.r[5]
end

local memo, visiting = {}, {}
local NOPRICE = { src = "none" }
function ns.ClearCache() memo = {}; visiting = {} end

-- Cheapest way to get one unit of an item. Returns { p = copper, src = "...", craft = recipe, craftID = id }.
function ns.UnitCost(id, depth)
  depth = depth or 0
  if memo[id] then return memo[id] end
  local best
  local ov = DB.overrides[id]
  if ov then
    best = { p = ov, src = "manual" }
  else
    local v = DB.reagents.vendor and ns.VendorPrice(id)
    if v then best = { p = v, src = "vendor" } end
    local a = DB.reagents.ah and ns.AHPrice(id)
    if a and (not best or a < best.p) then best = { p = a, src = "AH" } end
    if depth < 5 and not visiting[id] and MAKERS[id] then
      visiting[id] = true
      for _, m in ipairs(MAKERS[id]) do
        if canMake(m) then
          local cost, ok, reag = 0, true, m.r[10]
          for i = 1, #reag, 2 do
            local u = ns.UnitCost(reag[i], depth + 1)
            if not u.p then ok = false; break end
            cost = cost + u.p * reag[i + 1]
          end
          if ok then
            local per = cost / ns.Made(m.r)
            if not best or per < best.p then
              best = { p = per, src = ((m.kind == "mining" or m.kind == D.miningSkillLine) and "smelt" or "craft"), craft = m.r, craftID = m.id }
            end
          end
        end
      end
      visiting[id] = nil
    end
    if not best and DB.useWH then
      local it = D.items[id]
      if it and it[4] and it[4] > 0 then best = { p = it[4], src = "WH avg" } end
    end
  end
  best = best or NOPRICE
  memo[id] = best
  return best
end

-- true if the item binds on pickup (can't be sold on the AH)
function ns.IsBoP(id)
  if not id or id == 0 then return false end
  local bind
  if C_Item and C_Item.GetItemInfo then bind = select(14, C_Item.GetItemInfo(id))
  elseif GetItemInfo then bind = select(14, GetItemInfo(id)) end
  if bind == nil and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  return bind == 1
end

-- ---------------------------------------------------------------- disenchant value
-- Is disenchant value counted? Set by /bsu de, else on for characters with Enchanting.
function ns.UseDisenchant()
  if DB.disenchant ~= nil then return DB.disenchant end
  return ns.HasEnchanting()
end

local function matValue(id)
  local p = ns.AHPrice(id)
  if not p and DB.useWH and D.items[id] and D.items[id][4] > 0 then p = D.items[id][4] end
  if not p then return 0 end
  return p * (1 - DB.ahCut / 100) * (DB.ahSellThrough / 100)
end

local deWaiting = {}   -- items whose level/type we've asked the game for
local function itemBasics(id)
  local _, quality, ilvl, classID
  if C_Item and C_Item.GetItemInfo then
    local r = { C_Item.GetItemInfo(id) }
    quality, ilvl, classID = r[3], r[4], r[12]
  elseif GetItemInfo then
    local r = { GetItemInfo(id) }
    quality, ilvl, classID = r[3], r[4], r[12]
  end
  if not ilvl and C_Item and C_Item.RequestLoadItemDataByID then
    deWaiting[id] = true
    pcall(C_Item.RequestLoadItemDataByID, id)
  end
  return quality, ilvl, classID
end
function ns.OnItemInfo(id) if deWaiting[id] then deWaiting[id] = nil; return true end end

-- Items made by Enchanting (wands, rods, ...) can't be disenchanted.
local enchanterMade = { [11290] = true } -- Greater Mystic Wand (Classic ID)
local function indexEnchanterMade()
  local P = D.professions[333]
  if P then for _, r in pairs(P.recipes) do if r[2] > 0 then enchanterMade[r[2]] = true end end end
end

local function rowValue(rows, ilvl)
  for _, row in ipairs(rows) do
    if ilvl >= row[1] and ilvl <= row[2] then
      local v = 0
      for i = 3, #row do
        local chance, lo, hi, mat = row[i][1], row[i][2], row[i][3], row[i][4]
        v = v + chance / 100 * (lo + hi) / 2 * matValue(mat)
      end
      return v
    end
  end
  return 0
end

-- Expected AH value (after cut and sell-through) of disenchanting one of this item; 0 if it can't be.
function ns.DisenchantValue(id)
  if not id or id == 0 or enchanterMade[id] then return 0 end
  local quality, ilvl, classID = itemBasics(id)
  if not ilvl or (classID ~= 2 and classID ~= 4) or not quality or quality < 2 or quality > 4 then return 0 end
  local T = D.disenchant
  if quality == 2 then return rowValue(classID == 2 and T.weapon or T.armor, ilvl) end
  if quality == 4 and ilvl >= 40 then return rowValue(T.epic, ilvl) end
  return rowValue(T.rare, ilvl)   -- rare, and the few epics below item level 40
end

-- Has this character trained Enchanting?
function ns.HasEnchanting()
  return CDB ~= nil and CDB.profs[333] ~= nil and CDB.profs[333].skill ~= nil
end

-- Disenchant value counted for this item: the setting is on, and a bind-on-pickup item
-- only when this character can disenchant it itself (it can't be sent to an enchanter).
function ns.DisenchantCounts(id)
  if not ns.UseDisenchant() then return false end
  return ns.HasEnchanting() or not ns.IsBoP(id)
end

function ns.ResaleValue(id, mode)
  mode = mode or DB.resale
  if not id or id == 0 or mode == "none" then return 0, "" end
  if mode == "de" then return ns.DisenchantValue(id), "disenchant" end
  local de = mode ~= "ahonly" and ns.DisenchantCounts(id) and ns.DisenchantValue(id) or 0
  local vend = ns.SellPrice(id)
  if mode == "vendor" or ns.IsBoP(id) then
    if de > vend then return de, "disenchant" end
    return vend, "vendor"
  end
  local ah, src = ns.AHPrice(id), "AH"
  if not ah and DB.useWH and D.items[id] and D.items[id][4] > 0 then ah, src = D.items[id][4], "WH avg" end
  local net = ah and ah * (1 - DB.ahCut / 100) * (DB.ahSellThrough / 100) or 0
  if mode == "ahonly" then return net, ah and src or "none" end
  if de > net and de > vend then return de, "disenchant" end
  if net > vend then return net, src end
  return vend, "vendor"
end

function ns.RecipeCost(r, mode)
  local cost, missing, lines = 0, 0, {}
  local reag = r[10]
  for i = 1, #reag, 2 do
    local id, q = reag[i], reag[i + 1]
    local u = ns.UnitCost(id)
    if u.p then cost = cost + u.p * q else missing = missing + 1 end
    lines[#lines + 1] = { id = id, q = q, u = u }
  end
  local made = ns.Made(r)
  local each, rsrc = ns.ResaleValue(r[2], mode)
  local back = each * made
  return { cost = cost, back = back, each = each, rsrc = rsrc, net = cost - back, missing = missing, lines = lines, made = made }
end

-- ---------------------------------------------------------------- evaluation
function ns.IsKnown(id, line)
  local _, l = ns.FindRecipe(id)
  return ns.Prof(line or l).known[id] == true
end

-- Recipes you know always count (the data's learn level can be wrong); the source and
-- "unlearned" filters only decide which recipes you don't know yet are suggested.
local function usable(id, r, s, P)
  if P.known[id] or r.pinned then return true end
  if not DB.sources[r[9]] then return false end
  if s < r[5] then return false end
  if P.scanned and not DB.includeUnlearned then return false end
  return true
end
ns.Usable = usable

-- All recipes of a profession (default: the active one) that can give a point at skill s
-- (default: your skill in it), cheapest expected cost per point first.
function ns.Evaluate(s, line)
  line = line or ns.active
  local P, data = ns.Prof(line), D.professions[line]
  s = s or P.skill or 1
  local out = {}
  if not data then return out end
  for id, r in pairs(data.recipes) do
    if usable(id, r, s, P) then
      local p = ns.Chance(id, r, s, line)
      if p > 0 then
        local c = ns.RecipeCost(r)
        out[#out + 1] = { id = id, r = r, p = p, c = c, colour = ns.Colour(r, s),
          perPt = (c.missing > 0) and math.huge or (c.net / p), known = P.known[id] or r.pinned }
      end
    end
  end
  table.sort(out, function(a, b)
    if (a.r.pinned or false) ~= (b.r.pinned or false) then return a.r.pinned == true end
    if a.perPt ~= b.perPt then return a.perPt < b.perPt end
    if a.p ~= b.p then return a.p > b.p end
    return a.id < b.id
  end)
  return out
end

-- ---------------------------------------------------------------- skill & recipe scanning
local function readSkillLines()
  if GetProfessions and GetProfessionInfo then
    local idx = { GetProfessions() }
    for i = 1, 6 do
      local p = idx[i]
      if p then
        local _, _, rank, maxRank, _, _, line = GetProfessionInfo(p)
        if line == D.miningSkillLine then CDB.mining = rank end
        if D.professions[line] then local P = ns.Prof(line); P.skill, P.maxSkill = rank, maxRank end
      end
    end
  elseif GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank, _, _, maxRank = GetSkillLineInfo(i)
      if not header then
        if name == "Mining" then CDB.mining = rank end
        for line, P in pairs(D.professions) do
          if name == P.name then local st = ns.Prof(line); st.skill, st.maxSkill = rank, maxRank end
        end
      end
    end
  end
end

-- The open Professions window's skill line, if it's one we have data for.
local function openProfession()
  local T = C_TradeSkillUI
  if not T or not T.GetBaseProfessionInfo then return end
  local ok, info = pcall(T.GetBaseProfessionInfo)
  if not ok or not info then return end
  if D.professions[info.professionID] then return info.professionID, info end
  if D.professions[info.parentProfessionID] then return info.parentProfessionID, info end
end

function ns.ScanOpenProfession()
  local T = C_TradeSkillUI
  local line, info = openProfession()
  if not line then return false end
  if T.IsTradeSkillReady and not T.IsTradeSkillReady() then return false end
  if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then return false end   -- someone else's link
  ns.SetActive(line)
  local P = ns.Prof(line)
  if info.skillLevel and info.skillLevel > 0 then
    P.skill, P.maxSkill = info.skillLevel, info.maxSkillLevel
    if line == D.miningSkillLine then CDB.mining = info.skillLevel end
  end
  local ids = T.GetAllRecipeIDs and T.GetAllRecipeIDs()
  if not ids or #ids == 0 then return false end
  local known, diff, craftable = {}, {}, {}
  for _, id in ipairs(ids) do
    local ok, ri = pcall(T.GetRecipeInfo, id)
    if ok and ri then
      if ri.learned then known[id] = true end
      if ri.relativeDifficulty ~= nil then diff[id] = ri.relativeDifficulty end
      if ri.numAvailable then craftable[id] = ri.numAvailable end
    end
  end
  P.known, P.scanned = known, true
  ns.live.diff, ns.live.craftable, ns.live.at, ns.live.line = diff, craftable, P.skill, line
  if P.skill then
    for id, d in pairs(diff) do
      if known[id] then recordSeen(id, d, P.skill); ns.ApplySeen(id) end
    end
    ns.ClearCache()
  end
  return true
end

function ns.SelectRecipe(id)
  local T = C_TradeSkillUI
  if not T then return end
  local pf = ProfessionsFrame
  if pf and pf:IsShown() and pf.CraftingPage and pf.CraftingPage.RecipeList and pf.CraftingPage.RecipeList.SelectRecipe then
    local ok, ri = pcall(T.GetRecipeInfo, id)
    if ok and ri and pcall(pf.CraftingPage.RecipeList.SelectRecipe, pf.CraftingPage.RecipeList, ri, true) then return end
  end
  if T.OpenRecipe then pcall(T.OpenRecipe, id) end
end

-- ---------------------------------------------------------------- events
local f = CreateFrame("Frame")
local pending = false
function ns.Refresh(delay)
  if pending then return end
  pending = true
  C_Timer.After(delay or 0.2, function()
    pending = false
    ns.ClearCache()
    if ns.UI and ns.UI.Update then ns.UI.Update() end
    if ns.UpdateNative then ns.UpdateNative() end
  end)
end

local function safeRegister(ev) pcall(f.RegisterEvent, f, ev) end

f:SetScript("OnEvent", function(_, ev, arg1)
  if ev == "ADDON_LOADED" and arg1 == ADDON then
    BestSkillUpDB = BestSkillUpDB or {}
    BestSkillUpCharDB = BestSkillUpCharDB or {}
    copyDefaults(BestSkillUpDB, DEFAULTS)
    copyDefaults(BestSkillUpCharDB, CHAR_DEFAULTS)
    DB, CDB = BestSkillUpDB, BestSkillUpCharDB
    ns.DB, ns.CDB = DB, CDB
    migrate()
    -- Price syncing was removed in 0.7.0: drop its saved data.
    BestSkillUpDB.shared, BestSkillUpDB.partner, BestSkillUpDB.pushAuctionator = nil, nil, nil
    ns.active = pickActive()
    addDisenchant()
    for id in pairs(DB.seen) do ns.ApplySeen(id) end
    indexMakers()
    indexEnchanterMade()
  elseif ev == "PLAYER_LOGIN" then
    readSkillLines()
    ns.active = pickActive()
    local A = AuctionatorAPI()
    if A and A.RegisterForDBUpdate then pcall(A.RegisterForDBUpdate, CALLER, function() ns.Refresh(0.5) end) end
    if ns.UI then ns.UI.Init() end
  elseif ev == "TRADE_SKILL_SHOW" or ev == "TRADE_SKILL_LIST_UPDATE" or ev == "TRADE_SKILL_DATA_SOURCE_CHANGED" or ev == "NEW_RECIPE_LEARNED" then
    C_Timer.After(0.1, function()
      if ns.ScanOpenProfession() then
        if ns.UI then ns.UI.OnProfessionShown() end
        ns.Refresh()
      end
    end)
  elseif ev == "TRADE_SKILL_CLOSE" then
    if ns.UI then ns.UI.OnProfessionHidden() end
  elseif ev == "SKILL_LINES_CHANGED" or ev == "CHAT_MSG_SKILL" then
    readSkillLines()
    ns.Refresh(0.3)
  elseif ev == "BAG_UPDATE_DELAYED" or ev == "MERCHANT_SHOW" then
    ns.Refresh(0.5)
  end
end)
for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
  "NEW_RECIPE_LEARNED", "TRADE_SKILL_CLOSE", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "BAG_UPDATE_DELAYED", "MERCHANT_SHOW" }) do
  safeRegister(ev)
end

-- ---------------------------------------------------------------- slash
SLASH_BESTSKILLUP1 = "/bsu"
SLASH_BESTSKILLUP2 = "/bestskillup"
SlashCmdList.BESTSKILLUP = function(msg)
  local cmd, rest = (msg or ""):lower():match("^(%S*)%s*(.-)$")
  if cmd == "" or cmd == "show" or cmd == "toggle" then
    if ns.UI then ns.UI.Toggle() end
  elseif cmd == "prof" then
    ns.CycleActive(); ns.Print("Showing " .. ns.ProfName()); ns.Refresh(0)
  elseif cmd == "options" or cmd == "opt" then
    if ns.UI then ns.UI.ShowOptions() end
  elseif cmd == "resale" and (rest == "none" or rest == "vendor" or rest == "ah") then
    DB.resale = rest; ns.Print("Resale " .. rest); ns.Refresh(0)
  elseif cmd == "unlearned" then
    DB.includeUnlearned = not DB.includeUnlearned; ns.Print("Unlearned " .. (DB.includeUnlearned and "on" or "off")); ns.Refresh(0)
  elseif cmd == "source" and DB.sources[rest] ~= nil then
    DB.sources[rest] = not DB.sources[rest]; ns.Print(rest .. " " .. (DB.sources[rest] and "on" or "off")); ns.Refresh(0)
  elseif cmd == "de" then
    if rest == "auto" then DB.disenchant = nil else DB.disenchant = not ns.UseDisenchant() end
    ns.Print("Disenchant value " .. (ns.UseDisenchant() and "on" or "off") .. (DB.disenchant == nil and " (auto: on with Enchanting)" or ""))
    ns.Refresh(0)
  elseif cmd == "overtime" or cmd == "ot" then
    local n = tonumber(rest)
    if n then CDB.overtime = math.max(0, math.min(5, math.floor(n))) end
    ns.Print(("Working Overtime %d/5 (%d%% fewer failed skill-ups on yellow/green)"):format(ns.OvertimeRank(), ns.OvertimeBonus() * 100 + 0.5))
    ns.Refresh(0)
  elseif cmd == "wh" then
    DB.useWH = not DB.useWH; ns.Print("WH prices " .. (DB.useWH and "on" or "off")); ns.Refresh(0)
  elseif cmd == "price" then
    local id, copper = rest:match("(%d+)%s*(%d*)")
    id = tonumber(id)
    if id then
      DB.overrides[id] = tonumber(copper)
      ns.Print(ns.ItemName(id) .. " " .. (DB.overrides[id] and ns.Money(DB.overrides[id]) or "cleared"))
      ns.Refresh(0)
    end
  elseif cmd == "debug" then
    if ns.DebugNative then ns.DebugNative() else ns.Print("Native.lua not loaded - restart the game") end
  elseif cmd == "reset" then
    DB.point = nil; if ns.UI then ns.UI.ResetPosition() end
  else
    ns.Print("/bsu  prof  opt  resale none/vendor/ah  unlearned  source <type>  de [auto]  overtime <0-5>  wh  price <id> [c]  debug  reset")
  end
end
