-- Development only: disenchant recording for measuring the Arcane Salvager.
-- Loaded from the local AddOns copy; the release workflow leaves every Dev*.lua file (and its TOC line) out of the zip.
local _, ns = ...

-- Records every Disenchant: the item (found as the bag item the cast locks), what dropped, and whether the
-- player had Boosted Disenchanting (spell 1283701, from time near an Arcane Salvager: "chance of bonus
-- disenchanting output is increased"), to measure the bonus against the disenchant tables.
local DE_LOG_MAX = 3000
local BOOST_ID, BOOST_NAME = 1283701, "Boosted Disenchanting"
local pendingDE

local function bagItemLocked()
  local C = C_Container
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local n = (C and C.GetContainerNumSlots and C.GetContainerNumSlots(bag)) or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
    for slot = 1, n do
      local locked, link
      local info = C and C.GetContainerItemInfo and C.GetContainerItemInfo(bag, slot)
      if type(info) == "table" then locked, link = info.isLocked, info.hyperlink
      elseif GetContainerItemInfo then local _, _, l, _, _, _, lk = GetContainerItemInfo(bag, slot); locked, link = l, lk end
      if locked and link then return link end
    end
  end
end

-- Buff names and spell IDs, and whether Boosted Disenchanting is one of them.
local function playerAuras()
  local names, ids, boost = {}, {}, false
  for i = 1, 40 do
    local name, id
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL"); name, id = a and a.name, a and a.spellId
    elseif UnitBuff then local r = { UnitBuff("player", i) }; name, id = r[1], r[10] end
    if not name then break end
    names[#names + 1] = name; ids[#ids + 1] = id or 0
    if id == BOOST_ID or name == BOOST_NAME then boost = true end
  end
  if not boost and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
    boost = C_UnitAuras.GetPlayerAuraBySpellID(BOOST_ID) ~= nil
  end
  return names, ids, boost
end

-- Records made before the buff was detected only have buff names: go by those (the old manual switch is ignored).
local function boosted(e)
  if e.boost ~= nil then return e.boost end
  for _, n in ipairs(e.auras or {}) do if n == BOOST_NAME then return true end end
  return false
end

local function itemFromLink(link)
  local id = tonumber(link:match("item:(%d+)"))
  local r = { (C_Item and C_Item.GetItemInfo or GetItemInfo)(link) }
  local lvlFn = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
  local ilvl = (lvlFn and lvlFn(link)) or r[4]
  return id, ilvl, r[3], r[12]
end

-- The disenchant table row an item uses, its table, and the row's position.
local function deRow(q, ilvl, cls)
  local T = ns.Data.disenchant
  local rows = (q == 2 and (cls == 2 and T.weapon or T.armor)) or (q == 4 and ilvl >= 40 and T.epic) or T.rare
  for i, row in ipairs(rows) do if ilvl >= row[1] and ilvl <= row[2] then return row, rows, i end end
end

local function onDisenchantLoot()
  local p = pendingDE
  if not p or GetTime() - p.started > 15 then pendingDE = nil; return end
  local loot, parts = {}, {}
  for i = 1, (GetNumLootItems and GetNumLootItems() or 0) do
    local link = GetLootSlotLink and GetLootSlotLink(i)
    local id = link and tonumber(link:match("item:(%d+)"))
    if id then
      local _, name, qty = GetLootSlotInfo(i)
      loot[id] = (loot[id] or 0) + (qty or 1)
      parts[#parts + 1] = (qty or 1) .. " " .. (name or ns.ItemName(id))
    end
  end
  if not next(loot) then return end   -- not the disenchant loot (yet)
  pendingDE = nil
  ns.DB.deLog = ns.DB.deLog or {}
  local log = ns.DB.deLog
  log[#log + 1] = { t = time(), id = p.id, ilvl = p.ilvl, q = p.q, c = p.c, boost = p.boost, skill = p.skill, loot = loot,
    auras = p.auras, auraIDs = p.auraIDs }
  while #log > DE_LOG_MAX do table.remove(log, 1) end
  ns.Print(("Disenchant #%d recorded (%s): %s"):format(#log, p.boost and "Boosted" or "not boosted", table.concat(parts, ", ")))
end

local deFrame = CreateFrame("Frame")
deFrame:SetScript("OnEvent", function(_, ev, unit, castGUID, spellID)
  if ev == "UNIT_SPELLCAST_START" then
    if unit ~= "player" or spellID ~= ns.DISENCHANT then return end
    local link = bagItemLocked()
    if not link then pendingDE = nil; return end
    local id, ilvl, q, c = itemFromLink(link)
    local names, auraIDs, boost = playerAuras()
    pendingDE = { cast = castGUID, started = GetTime(), id = id, ilvl = ilvl, q = q, c = c, boost = boost,
      skill = ns.CDB and ns.CDB.profs[333] and ns.CDB.profs[333].skill, auras = names, auraIDs = auraIDs }
  elseif ev == "UNIT_SPELLCAST_INTERRUPTED" or ev == "UNIT_SPELLCAST_FAILED" or ev == "UNIT_SPELLCAST_FAILED_QUIET" then
    if unit == "player" and pendingDE and pendingDE.cast == castGUID then pendingDE = nil end
  elseif ev == "LOOT_READY" or ev == "LOOT_OPENED" then
    if pendingDE then onDisenchantLoot() end
  end
end)
for _, ev in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET",
  "LOOT_READY", "LOOT_OPENED" }) do pcall(deFrame.RegisterEvent, deFrame, ev) end

-- Recorded results against the tables, with and without Boosted Disenchanting.
--   materials: row materials received / the row's expected amount (chance x average quantity)
--   2+ kinds:  disenchants that gave more than one of the row's materials (normally you get one)
--   over max:  disenchants where a material's quantity was above the row's maximum
function ns.SalvagerReport()
  local function new() return { n = 0, got = 0, exp = 0, gotV = 0, expV = 0, up = 0, odd = 0, multi = 0, over = 0 } end
  local S = { [false] = new(), [true] = new() }
  local function price(id) return ns.AHPrice(id) or (ns.Data.items[id] and ns.Data.items[id][4]) or 0 end
  for _, e in ipairs(ns.DB.deLog or {}) do
    local row, rows, i
    if e.ilvl and e.q then row, rows, i = deRow(e.q, e.ilvl, e.c) end
    if row then
      local s = S[boosted(e)]
      s.n = s.n + 1
      local inRow, hi, inNext = {}, {}, {}
      for k = 3, #row do
        local m = row[k]; inRow[m[4]] = true; hi[m[4]] = m[3]
        local q = m[1] / 100 * (m[2] + m[3]) / 2
        s.exp = s.exp + q; s.expV = s.expV + q * price(m[4])
      end
      local nextRow = rows[i + 1]
      if nextRow then for k = 3, #nextRow do inNext[nextRow[k][4]] = true end end
      local up, odd, kinds, over = false, false, 0, false
      for id, qty in pairs(e.loot) do
        s.gotV = s.gotV + qty * price(id)
        if inRow[id] then
          s.got = s.got + qty; kinds = kinds + 1
          if qty > hi[id] then over = true end
        elseif inNext[id] then up = true
        else odd = true end
      end
      if up then s.up = s.up + 1 end
      if odd then s.odd = s.odd + 1 end
      if kinds > 1 then s.multi = s.multi + 1 end
      if over then s.over = s.over + 1 end
    end
  end
  local function pct(x, n) return math.floor(100 * x / n + 0.5) end
  ns.Print(("%d disenchants recorded."):format(#(ns.DB.deLog or {})))
  for _, b in ipairs({ false, true }) do
    local s = S[b]
    local label = b and "Boosted" or "Not boosted"
    if s.n == 0 then ns.Print(label .. ": none yet")
    else
      ns.Print(("%s: %d · materials %.2fx expected (%.2f per DE) · value %.2fx · 2+ kinds %d%% · over max %d%% · higher bracket %d%%%s"):format(
        label, s.n, s.exp > 0 and s.got / s.exp or 0, s.got / s.n, s.expV > 0 and s.gotV / s.expV or 0,
        pct(s.multi, s.n), pct(s.over, s.n), pct(s.up, s.n), s.odd > 0 and (" · other " .. s.odd) or ""))
    end
  end
  return S
end

-- /bsu salvager [clear]: report, or clear the records. Core calls this before its own commands.
function ns.DevSlash(cmd, rest)
  if cmd ~= "salvager" and cmd ~= "salv" then return false end
  if not ns.DB then return true end
  ns.DB.salvager = nil   -- old manual switch: Boosted Disenchanting is detected now
  if rest == "clear" then
    ns.DB.deLog = {}; ns.Print("Disenchant records cleared")
  else
    ns.SalvagerReport()
  end
  return true
end
