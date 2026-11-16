-- BestSkillUp: ranks recipes by expected gold per skill point.
--   expected cost per point = (reagent cost - value of what you make) / chance to skill up
--   chance (Classic rule): orange 100%, grey 0%, yellow/green = (grey - skill) / (grey - yellow)
-- Reagents are costed at the cheapest of: vendor, Auctionator AH price, or crafting/smelting them (recursively).

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
  point = nil,                -- saved window position
  shown = true,
}
local CHAR_DEFAULTS = { known = {}, scanned = false, skill = nil, maxSkill = nil, mining = nil }

local DB, CDB
ns.live = { diff = {}, craftable = {}, at = nil }   -- live data from the open Professions window

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

function ns.Chance(id, r, s)
  local _, y, _, gr = r[5], r[6], r[7], r[8]
  local p
  if s >= gr then p = 0
  elseif s < y then p = 1
  elseif gr <= y then p = 0
  else p = (gr - s) / (gr - y) end
  if p < 0 then p = 0 elseif p > 1 then p = 1 end
  -- At your current skill the game's own colour wins if it disagrees with the data.
  local live = ns.live.diff[id]
  if live ~= nil and CDB and s == CDB.skill then
    if live == 3 then return 0 end
    if p == 0 then return LIVE_FALLBACK[live] or 0 end
    if live == 0 then return 1 end
  end
  return p
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

-- Own Auctionator price, or the synced one when it comes from a newer scan.
function ns.AHPrice(id)
  local own = ownAHPrice(id)
  local sh = DB.shared
  local shp = sh and sh.prices and sh.prices[id]
  if shp and (not own or (sh.time or 0) > (ns.OwnScanTime and ns.OwnScanTime() or 0)) then return shp end
  return own
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

-- Which recipes produce which item (Blacksmithing + Mining smelts).
local MAKERS = {}
local function indexMakers()
  for id, r in pairs(D.recipes) do if r[2] > 0 then MAKERS[r[2]] = MAKERS[r[2]] or {}; table.insert(MAKERS[r[2]], { id = id, r = r, kind = "bs" }) end end
  for id, r in pairs(D.mining) do if r[2] > 0 then MAKERS[r[2]] = MAKERS[r[2]] or {}; table.insert(MAKERS[r[2]], { id = id, r = r, kind = "mining" }) end end
end

-- Can you make this intermediate yourself right now?
local function canMake(m)
  if m.kind == "mining" then return DB.reagents.smelt and CDB.mining ~= nil and CDB.mining >= m.r[5] end
  if not DB.reagents.craft then return false end
  if CDB.known[m.id] then return true end
  return DB.includeUnlearned and m.r[9] == "trainer" and (CDB.skill or 1) >= m.r[5]
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
              best = { p = per, src = (m.kind == "mining" and "smelt" or "craft"), craft = m.r, craftID = m.id }
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

function ns.ResaleValue(id, mode)
  mode = mode or DB.resale
  if not id or id == 0 or mode == "none" then return 0, "" end
  local vend = ns.SellPrice(id)
  if mode == "vendor" or ns.IsBoP(id) then return vend, "vendor" end
  local ah, src = ns.AHPrice(id), "AH"
  if not ah and DB.useWH and D.items[id] and D.items[id][4] > 0 then ah, src = D.items[id][4], "WH avg" end
  local net = ah and ah * (1 - DB.ahCut / 100) * (DB.ahSellThrough / 100) or 0
  if mode == "ahonly" then return net, ah and src or "none" end
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
function ns.IsKnown(id) return CDB.known[id] == true end

local function usable(id, r, s)
  if not DB.sources[r[9]] then return false end
  if s < r[5] then return false end
  if CDB.scanned and not CDB.known[id] and not DB.includeUnlearned then return false end
  return true
end

-- All recipes that can give a point at skill s, cheapest expected cost per point first.
function ns.Evaluate(s)
  local out = {}
  for id, r in pairs(D.recipes) do
    if usable(id, r, s) then
      local p = ns.Chance(id, r, s)
      if p > 0 then
        local c = ns.RecipeCost(r)
        out[#out + 1] = { id = id, r = r, p = p, c = c, colour = ns.Colour(r, s),
          perPt = (c.missing > 0) and math.huge or (c.net / p), known = CDB.known[id] }
      end
    end
  end
  table.sort(out, function(a, b)
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
        if line == D.skillLine then CDB.skill, CDB.maxSkill = rank, maxRank
        elseif line == D.miningSkillLine then CDB.mining = rank end
      end
    end
  elseif GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank, _, _, maxRank = GetSkillLineInfo(i)
      if not header then
        if name == "Blacksmithing" then CDB.skill, CDB.maxSkill = rank, maxRank
        elseif name == "Mining" then CDB.mining = rank end
      end
    end
  end
end

local function isBlacksmithingOpen()
  local T = C_TradeSkillUI
  if not T or not T.GetBaseProfessionInfo then return false end
  local ok, info = pcall(T.GetBaseProfessionInfo)
  if not ok or not info then return false end
  if info.professionID == D.skillLine or info.parentProfessionID == D.skillLine then return true, info end
  return false
end

function ns.ScanOpenProfession()
  local T = C_TradeSkillUI
  local open, info = isBlacksmithingOpen()
  if not open then return false end
  if T.IsTradeSkillReady and not T.IsTradeSkillReady() then return false end
  if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then return false end   -- someone else's link
  if info.skillLevel and info.skillLevel > 0 then CDB.skill, CDB.maxSkill = info.skillLevel, info.maxSkillLevel end
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
  CDB.known, CDB.scanned = known, true
  ns.live.diff, ns.live.craftable, ns.live.at = diff, craftable, CDB.skill
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
    indexMakers()
  elseif ev == "PLAYER_LOGIN" then
    readSkillLines()
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
  elseif cmd == "options" or cmd == "opt" then
    if ns.UI then ns.UI.ShowOptions() end
  elseif cmd == "resale" and (rest == "none" or rest == "vendor" or rest == "ah") then
    DB.resale = rest; ns.Print("Resale " .. rest); ns.Refresh(0)
  elseif cmd == "unlearned" then
    DB.includeUnlearned = not DB.includeUnlearned; ns.Print("Unlearned " .. (DB.includeUnlearned and "on" or "off")); ns.Refresh(0)
  elseif cmd == "source" and DB.sources[rest] ~= nil then
    DB.sources[rest] = not DB.sources[rest]; ns.Print(rest .. " " .. (DB.sources[rest] and "on" or "off")); ns.Refresh(0)
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
  elseif cmd == "partner" then
    if ns.SetPartner then ns.SetPartner((msg or ""):match("^%S+%s+(%S+)")) end
  elseif cmd == "auctionator" then
    BestSkillUpDB.pushAuctionator = (BestSkillUpDB.pushAuctionator == false)
    ns.Print("Write synced prices to Auctionator " .. (BestSkillUpDB.pushAuctionator and "on" or "off"))
  elseif cmd == "sync" then
    if ns.SyncHello then ns.SyncHello(); ns.SyncStatus() end
  elseif cmd == "debug" then
    if ns.DebugNative then ns.DebugNative() else ns.Print("Native.lua not loaded - restart the game") end
  elseif cmd == "reset" then
    DB.point = nil; if ns.UI then ns.UI.ResetPosition() end
  else
    ns.Print("/bsu  opt  partner [name]  sync  auctionator  resale none/vendor/ah  unlearned  source <type>  wh  price <id> [c]  debug  reset")
  end
end
