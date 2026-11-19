-- BestSkillUp_Dev: disenchant recording for measuring the Arcane Salvager. Development only, never released.
-- A separate add-on so that WowUp updating BestSkillUp doesn't remove it. Works on BestSkillUp's namespace
-- (BestSkillUpAPI) and saves into BestSkillUpDB.deLog.
local ns = BestSkillUpAPI
if not ns then
  -- BestSkillUp older than the version that exposes BestSkillUpAPI (e.g. a release installed over the local copy).
  local f = CreateFrame("Frame"); f:RegisterEvent("PLAYER_LOGIN")
  f:SetScript("OnEvent", function()
    DEFAULT_CHAT_FRAME:AddMessage("|cffe8c35aBestSkillUp Dev|r: |cffff8040not recording disenchants|r - this BestSkillUp is too old for the recorder (needs BestSkillUpAPI).")
  end)
  return
end

-- Records every Disenchant: the item (found as the bag item the cast locks), what dropped, and whether the
-- player had Boosted Disenchanting (spell 1283701, from time near an Arcane Salvager: "chance of bonus
-- disenchanting output is increased"), to measure the bonus against the disenchant tables.
local DE_LOG_MAX = 3000
local BOOST_ID, BOOST_NAME = 1283701, "Boosted Disenchanting"
local pendingDE

-- Only armour or weapons of uncommon to epic quality can be disenchanted: anything else a check finds (a
-- locked stack of cloth being mailed or listed, say) isn't the item.
local function disenchantable(link)
  if not link then return false end
  local r = { (C_Item and C_Item.GetItemInfo or GetItemInfo)(link) }
  local q, c = r[3], r[12]
  return (c == 2 or c == 4) and q ~= nil and q >= 2 and q <= 4
end

local function bagItemLocked()
  local C = C_Container
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local n = (C and C.GetContainerNumSlots and C.GetContainerNumSlots(bag)) or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
    for slot = 1, n do
      local locked, link
      local info = C and C.GetContainerItemInfo and C.GetContainerItemInfo(bag, slot)
      if type(info) == "table" then locked, link = info.isLocked, info.hyperlink
      elseif GetContainerItemInfo then local _, _, l, _, _, _, lk = GetContainerItemInfo(bag, slot); locked, link = l, lk end
      if locked and link and disenchantable(link) then return link end
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

-- Several ways to catch a disenchant, because the client may not do what Classic did:
--   cast:  UNIT_SPELLCAST_START/SENT/SUCCEEDED with Disenchant's spell ID, or any spell named "Disenchant"
--   item:  the bag item the cast locks; else the bag item last clicked while a spell was targeting;
--          else the bag item named as the cast's target (UNIT_SPELLCAST_SENT)
--   loot:  the loot window (LOOT_READY/LOOT_OPENED); else "You receive loot" chat lines in the next few seconds
-- `/bsu salvager debug` prints each step. A cast that can't be recorded always says so in chat.
local function dbg(msg) if ns.DB and ns.DB.deDebug then ns.Print("|cff888888[de]|r " .. msg) end end

local DE_NAME
local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end
local function isDisenchant(id)
  if not id then return false end
  if id == ns.DISENCHANT then return true end
  DE_NAME = DE_NAME or spellName(ns.DISENCHANT) or "Disenchant"
  local n = spellName(id)
  return n ~= nil and (n == DE_NAME or n == "Disenchant")
end

local function bagItemByName(name)
  if not name or name == "" then return end
  local C = C_Container
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local n = (C and C.GetContainerNumSlots and C.GetContainerNumSlots(bag)) or 0
    for slot = 1, n do
      local info = C.GetContainerItemInfo(bag, slot)
      local link = type(info) == "table" and info.hyperlink
      if link and link:find("[" .. name .. "]", 1, true) and disenchantable(link) then return link end
    end
  end
end

-- Bag item clicked while a spell is waiting for a target (how Disenchant is aimed).
local targeted
local function onUse(bag, slot)
  if not (SpellIsTargeting and SpellIsTargeting()) then return end
  local info = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
  local link = type(info) == "table" and info.hyperlink
  if link and disenchantable(link) then targeted = { link = link, t = GetTime() }; dbg("targeted " .. link) end
end
if hooksecurefunc then
  if C_Container and C_Container.UseContainerItem then pcall(hooksecurefunc, C_Container, "UseContainerItem", onUse) end
  if C_Container and C_Container.PickupContainerItem then pcall(hooksecurefunc, C_Container, "PickupContainerItem", onUse) end
end

-- Bag contents when the cast starts; the disenchanted item is the armour/weapon that's gone afterwards.
-- This works however the item was picked (bag add-ons, macros), which the other checks can miss.
local function bagSnapshot()
  local snap, C = {}, C_Container
  if not (C and C.GetContainerNumSlots) then return snap end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, C.GetContainerNumSlots(bag) or 0 do
      local info = C.GetContainerItemInfo(bag, slot)
      if type(info) == "table" and info.hyperlink then
        snap[info.hyperlink] = (snap[info.hyperlink] or 0) + (info.stackCount or 1)
      end
    end
  end
  return snap
end
-- The armour or weapon there's less of than when the cast started (counts per item, so bags re-sorting
-- themselves, or several of the same item, don't matter).
local function vanishedItem(snap)
  local now = bagSnapshot()
  for link, was in pairs(snap) do
    if (now[link] or 0) < was and disenchantable(link) then return link end
  end
end

local function startPending(castGUID, how, link)
  if link and not disenchantable(link) then link = nil end
  local id, ilvl, q, c
  if link then id, ilvl, q, c = itemFromLink(link) end
  local names, auraIDs, boost = playerAuras()
  pendingDE = { cast = castGUID, started = GetTime(), id = id, ilvl = ilvl, q = q, c = c, boost = boost, link = link,
    skill = ns.CDB and ns.CDB.profs[333] and ns.CDB.profs[333].skill, auras = names, auraIDs = auraIDs, loot = {}, parts = {}, snap = bagSnapshot() }
  dbg(("cast seen (%s): %s, %s"):format(how, link or "item unknown", boost and "Boosted" or "not boosted"))
end

local lastCast   -- castGUID of the last recorded disenchant (its SUCCEEDED can arrive after the loot)
local function finish(p, source)
  ns.DB.deLog = ns.DB.deLog or {}
  local log = ns.DB.deLog
  log[#log + 1] = { t = time(), id = p.id, ilvl = p.ilvl, q = p.q, c = p.c, boost = p.boost, skill = p.skill, loot = p.loot,
    auras = p.auras, auraIDs = p.auraIDs, via = source }
  while #log > DE_LOG_MAX do table.remove(log, 1) end
  ns.Print(("Disenchant #%d recorded (%s): %s%s"):format(#log, p.boost and "Boosted" or "not boosted", table.concat(p.parts, ", "),
    p.id and "" or " |cffff8040(item unknown)|r"))
end

local function commit(source)
  local p = pendingDE
  if not p or not next(p.loot) then return end
  pendingDE = nil
  lastCast = p.cast
  if p.id or not p.snap then finish(p, source); return end
  -- The item leaves the bags some time after the loot appears (when the loot window closes, on some
  -- clients): look every half second for up to 10 seconds.
  local tries = 0
  local function look()
    tries = tries + 1
    local link = vanishedItem(p.snap)
    if link then
      p.link = link; p.id, p.ilvl, p.q, p.c = itemFromLink(link)
      dbg("item from bag change: " .. link .. " after " .. tries * 0.5 .. "s")
      finish(p, source)
    elseif tries >= 20 then
      finish(p, source)
    else
      C_Timer.After(0.5, look)
    end
  end
  C_Timer.After(0.5, look)
end

local function fromLootWindow()
  local p = pendingDE
  local n = GetNumLootItems and GetNumLootItems() or 0
  dbg("loot window: " .. n .. " slot(s)")
  for i = 1, n do
    local link = GetLootSlotLink and GetLootSlotLink(i)
    local id = link and tonumber(link:match("item:(%d+)"))
    if id then
      local _, name, qty = GetLootSlotInfo(i)
      p.loot[id] = (p.loot[id] or 0) + (qty or 1)
      p.parts[#p.parts + 1] = (qty or 1) .. " " .. (name or ns.ItemName(id))
    end
  end
  if next(p.loot) then commit("loot") end
end

local function fromChat(msg)
  local p = pendingDE
  if not p or not p.succeeded or GetTime() - p.succeeded > 5 then return end
  local link = msg:match("|c%x+|Hitem:.-|h.-|h|r") or msg:match("|Hitem:.-|h.-|h")
  local id = link and tonumber(link:match("item:(%d+)"))
  if not id then return end
  local qty = tonumber(msg:match("|h|r?x(%d+)") or msg:match("x(%d+)%.?%s*$")) or 1
  p.loot[id] = (p.loot[id] or 0) + qty
  p.parts[#p.parts + 1] = qty .. " " .. ns.ItemName(id)
  p.viaChat = true
  dbg("chat loot: " .. qty .. " x " .. id)
end

local deFrame = CreateFrame("Frame")
deFrame:SetScript("OnEvent", function(_, ev, a1, a2, a3, a4)
  if ev == "UNIT_SPELLCAST_SENT" then              -- unit, target name, castGUID, spellID
    if a1 ~= "player" or not isDisenchant(a4) then return end
    local link = bagItemLocked() or (targeted and GetTime() - targeted.t < 10 and targeted.link) or bagItemByName(a2)
    startPending(a3, "sent", link)
  elseif ev == "UNIT_SPELLCAST_START" then         -- unit, castGUID, spellID
    if a1 ~= "player" or not isDisenchant(a3) then return end
    local link = bagItemLocked() or (targeted and GetTime() - targeted.t < 10 and targeted.link)
    if pendingDE and pendingDE.cast == a2 then
      if not pendingDE.link and link then
        pendingDE.link = link; pendingDE.id, pendingDE.ilvl, pendingDE.q, pendingDE.c = itemFromLink(link)
        dbg("item found at start: " .. link)
      end
    else
      startPending(a2, "start", link)
    end
  elseif ev == "UNIT_SPELLCAST_SUCCEEDED" then
    if a1 ~= "player" or not isDisenchant(a3) then return end
    if a2 ~= nil and a2 == lastCast then return end   -- already recorded from the loot window
    if not pendingDE then startPending(a2, "succeeded", targeted and GetTime() - targeted.t < 10 and targeted.link) end
    pendingDE.succeeded = GetTime()
    dbg("cast succeeded")
    local p = pendingDE
    C_Timer.After(4, function()
      if pendingDE ~= p then return end
      if next(p.loot) then commit("chat")
      else
        pendingDE = nil
        ns.Print("|cffff8040Disenchant seen but no loot was caught, so it wasn't recorded.|r Type /bsu salvager debug and try again.")
      end
    end)
  elseif ev == "UNIT_SPELLCAST_INTERRUPTED" or ev == "UNIT_SPELLCAST_FAILED" or ev == "UNIT_SPELLCAST_FAILED_QUIET" then
    if a1 == "player" and pendingDE and pendingDE.cast == a2 then pendingDE = nil; dbg("cast " .. ev:sub(16):lower()) end
  elseif ev == "LOOT_READY" or ev == "LOOT_OPENED" then
    if pendingDE then fromLootWindow() end
  elseif ev == "CHAT_MSG_LOOT" then
    if pendingDE then fromChat(a1 or "") end
  end
end)
for _, ev in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED",
  "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "LOOT_READY", "LOOT_OPENED", "CHAT_MSG_LOOT" }) do
  pcall(deFrame.RegisterEvent, deFrame, ev)
end

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
  -- Records without the item: compare each material with the most any disenchant table gives of it.
  local maxQty = {}
  for _, rows in pairs(ns.Data.disenchant) do
    for _, row in ipairs(rows) do
      for k = 3, #row do local m = row[k]; maxQty[m[4]] = math.max(maxQty[m[4]] or 0, m[3]) end
    end
  end
  local U = { [false] = { n = 0, over = 0 }, [true] = { n = 0, over = 0 } }
  for _, e in ipairs(ns.DB.deLog or {}) do
    if not (e.ilvl and e.q) then
      local u = U[boosted(e)]; u.n = u.n + 1
      for id, qty in pairs(e.loot or {}) do if maxQty[id] and qty > maxQty[id] then u.over = u.over + 1; break end end
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
  for _, b in ipairs({ false, true }) do
    local u = U[b]
    if u.n > 0 then
      ns.Print(("%s, item unknown: %d · above any table's maximum %d (%d%%)"):format(b and "Boosted" or "Not boosted", u.n, u.over, pct(u.over, u.n)))
    end
  end
  S.unknown = U
  return S
end

-- /bsu salvager [clear|debug]: report, clear the records, or toggle step-by-step output. Core calls this before its own commands.
function ns.DevSlash(cmd, rest)
  if cmd ~= "salvager" and cmd ~= "salv" then return false end
  if not ns.DB then return true end
  ns.DB.salvager = nil   -- old manual switch: Boosted Disenchanting is detected now
  if rest == "debug" then
    ns.DB.deDebug = not ns.DB.deDebug
    ns.Print("Disenchant recorder debug " .. (ns.DB.deDebug and "on" or "off")); return true
  elseif rest == "clear" then
    ns.DB.deLog = {}; ns.Print("Disenchant records cleared")
  else
    ns.SalvagerReport()
  end
  return true
end
ns.DevHelp = (ns.DevHelp or "") .. "salvager [clear|debug]  "
