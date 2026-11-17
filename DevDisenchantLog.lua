-- Development only: disenchant recording for measuring the Arcane Salvager.
-- Loaded from the local AddOns copy; the release workflow leaves every Dev*.lua file (and its TOC line) out of the zip.
local _, ns = ...

-- Records every Disenchant: the item (found as the bag item the cast locks), what dropped, and whether
-- the Arcane Salvager switch was on, to measure the Salvager's bonus against the disenchant tables.
local DE_LOG_MAX = 3000
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

local function playerAuras()
  local names = {}
  for i = 1, 40 do
    local name
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL"); name = a and a.name
    elseif UnitBuff then name = UnitBuff("player", i) end
    if not name then break end
    names[#names + 1] = name
  end
  return names
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
  log[#log + 1] = { t = time(), id = p.id, ilvl = p.ilvl, q = p.q, c = p.c, sal = p.sal, skill = p.skill, loot = loot, auras = p.auras }
  while #log > DE_LOG_MAX do table.remove(log, 1) end
  ns.Print(("Disenchant #%d recorded (%s Salvager): %s"):format(#log, p.sal and "with" or "without", table.concat(parts, ", ")))
end

local deFrame = CreateFrame("Frame")
deFrame:SetScript("OnEvent", function(_, ev, unit, castGUID, spellID)
  if ev == "UNIT_SPELLCAST_START" then
    if unit ~= "player" or spellID ~= ns.DISENCHANT then return end
    local link = bagItemLocked()
    if not link then pendingDE = nil; return end
    local id, ilvl, q, c = itemFromLink(link)
    pendingDE = { cast = castGUID, started = GetTime(), id = id, ilvl = ilvl, q = q, c = c, sal = ns.DB.salvager and true or false,
      skill = ns.CDB and ns.CDB.profs[333] and ns.CDB.profs[333].skill, auras = playerAuras() }
  elseif ev == "UNIT_SPELLCAST_INTERRUPTED" or ev == "UNIT_SPELLCAST_FAILED" or ev == "UNIT_SPELLCAST_FAILED_QUIET" then
    if unit == "player" and pendingDE and pendingDE.cast == castGUID then pendingDE = nil end
  elseif ev == "LOOT_READY" or ev == "LOOT_OPENED" then
    if pendingDE then onDisenchantLoot() end
  end
end)
for _, ev in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET",
  "LOOT_READY", "LOOT_OPENED" }) do pcall(deFrame.RegisterEvent, deFrame, ev) end

-- Recorded results against the tables, with and without the Salvager.
function ns.SalvagerReport()
  local S = { [false] = { n = 0, got = 0, exp = 0, gotV = 0, expV = 0, up = 0, odd = 0 }, [true] = { n = 0, got = 0, exp = 0, gotV = 0, expV = 0, up = 0, odd = 0 } }
  local function price(id) return ns.AHPrice(id) or (ns.Data.items[id] and ns.Data.items[id][4]) or 0 end
  for _, e in ipairs(ns.DB.deLog or {}) do
    local row, rows, i
    if e.ilvl and e.q then row, rows, i = deRow(e.q, e.ilvl, e.c) end
    if row then
      local s = S[e.sal and true or false]
      s.n = s.n + 1
      local inRow, inNext = {}, {}
      for k = 3, #row do
        local m = row[k]; inRow[m[4]] = true
        local q = m[1] / 100 * (m[2] + m[3]) / 2
        s.exp = s.exp + q; s.expV = s.expV + q * price(m[4])
      end
      local nextRow = rows[i + 1]
      if nextRow then for k = 3, #nextRow do inNext[nextRow[k][4]] = true end end
      local up, odd = false, false
      for id, qty in pairs(e.loot) do
        s.gotV = s.gotV + qty * price(id)
        if inRow[id] then s.got = s.got + qty
        elseif inNext[id] then up = true
        else odd = true end
      end
      if up then s.up = s.up + 1 end
      if odd then s.odd = s.odd + 1 end
    end
  end
  ns.Print(("Arcane Salvager switch: %s. %d disenchants recorded."):format(ns.DB.salvager and "ON" or "off", #(ns.DB.deLog or {})))
  for _, sal in ipairs({ false, true }) do
    local s = S[sal]
    local label = sal and "With Salvager" or "Without Salvager"
    if s.n == 0 then ns.Print(label .. ": none yet")
    else
      ns.Print(("%s: %d · materials %.2fx expected · value %.2fx · higher bracket %d (%d%%)%s"):format(label, s.n,
        s.exp > 0 and s.got / s.exp or 0, s.expV > 0 and s.gotV / s.expV or 0, s.up, math.floor(100 * s.up / s.n + 0.5),
        s.odd > 0 and (" · other " .. s.odd) or ""))
    end
  end
  return S
end

-- /bsu salvager [on|off|clear]: switch, clear, or report. Core calls this before its own commands.
function ns.DevSlash(cmd, rest)
  if cmd ~= "salvager" and cmd ~= "salv" then return false end
  if not ns.DB then return true end
  if rest == "on" or rest == "off" then
    ns.DB.salvager = (rest == "on")
    ns.Print("Arcane Salvager switch " .. (ns.DB.salvager and "ON: disenchants are recorded as with the Salvager" or "off"))
    if ns.UI and ns.UI.SyncOptions then ns.UI.SyncOptions() end
  elseif rest == "clear" then
    ns.DB.deLog = {}; ns.Print("Disenchant records cleared")
  else
    ns.SalvagerReport()
  end
  return true
end
