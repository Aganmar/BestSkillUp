-- Shares Auctionator prices for the items BestSkillUp uses (all professions) between your characters over hidden addon whispers.
-- The side with the newer Auctionator scan sends; the other stores them in BestSkillUpDB.shared.
local _, ns = ...
local D = ns.Data
local PREFIX = "BSUSYNC1"
local CHUNK = 240

local function DB() return BestSkillUpDB end

-- ---------------------------------------------------------------- helpers
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
  n = math.floor(n)
  if n == 0 then return "0" end
  local s = ""
  while n > 0 do local d = n % 36; s = DIGITS:sub(d + 1, d + 1) .. s; n = math.floor(n / 36) end
  return s
end

function ns.OwnScanTime()
  return (AUCTIONATOR_SAVEDVARS and tonumber(AUCTIONATOR_SAVEDVARS.TimeOfLastBrowseScan)) or 0
end

local function sameName(a, b)
  if not a or not b then return false end
  return Ambiguate(a, "none"):lower() == Ambiguate(b, "none"):lower()
end

-- Hide "No player named X is currently playing" caused by our own pings.
local muteUntil = 0
local function muteNotFound() muteUntil = GetTime() + 5 end
if ChatFrame_AddMessageEventFilter then
  ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
    if GetTime() < muteUntil and ERR_CHAT_PLAYER_NOT_FOUND_S and DB() and DB().partner then
      local p = Ambiguate(DB().partner, "none")
      if msg == ERR_CHAT_PLAYER_NOT_FOUND_S:format(p) or msg == ERR_CHAT_PLAYER_NOT_FOUND_S:format(DB().partner) then return true end
    end
  end)
end

-- ---------------------------------------------------------------- send queue (throttle-aware)
local queue, ticker = {}, nil
local function pump()
  local m = queue[1]
  if not m then if ticker then ticker:Cancel(); ticker = nil end; return end
  muteNotFound()
  local r = C_ChatInfo.SendAddonMessage(PREFIX, m[1], "WHISPER", m[2])
  local ok = (r == nil) or (r == true) or (r == 0)
  if ok then table.remove(queue, 1) end
end
local function send(msg, target)
  if not target then return end
  queue[#queue + 1] = { msg, target }
  if not ticker then pump(); if queue[1] then ticker = C_Timer.NewTicker(0.35, pump) end end
end

-- ---------------------------------------------------------------- protocol
-- H:<scanTime>  hello (initiate)      A:<scanTime>  answer to hello
-- R             request prices         P<id:price,...>  price chunk (base36)
-- E:<scanTime>:<count>  end of prices
local peers = {}         -- names that talked to us this session
local incoming = nil     -- { from, prices, count, started }

local function sharedTime() local s = DB().shared; return s and s.time or 0 end
local function effectiveTime() return math.max(ns.OwnScanTime(), sharedTime()) end

local function sendPrices(target)
  local A = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (A and A.GetAuctionPriceByItemID) then return end
  local parts, n, buf = {}, 0, ""
  for id in pairs(D.items) do
    local ok, p = pcall(A.GetAuctionPriceByItemID, ns.CALLER, id)
    if ok and type(p) == "number" and p > 0 then
      local pair = b36(id) .. ":" .. b36(p)
      if #buf + #pair + 2 > CHUNK then parts[#parts + 1] = buf; buf = "" end
      buf = (buf == "" and pair) or (buf .. "," .. pair)
      n = n + 1
    end
  end
  if buf ~= "" then parts[#parts + 1] = buf end
  for _, chunk in ipairs(parts) do send("P" .. chunk, target) end
  send(("E:%d:%d"):format(ns.OwnScanTime(), n), target)
end

-- Write synced prices into Auctionator's own database (its internal SetPrice, as a scan would),
-- only when they come from a newer scan than this account's. Returns how many were written.
function ns.PushToAuctionator(prices, scanTime)
  if DB().pushAuctionator == false then return 0 end
  local db = Auctionator and Auctionator.Database
  if not (db and db.SetPrice) or scanTime <= ns.OwnScanTime() then return 0 end
  local n = 0
  for id, p in pairs(prices) do
    if pcall(db.SetPrice, db, tostring(id), p) then n = n + 1 end
  end
  return n
end

function ns.SyncHello(target, answer)
  target = target or DB().partner
  if target then send((answer and "A:" or "H:") .. ns.OwnScanTime(), target) end
end

local function onMessage(msg, sender)
  local kind = msg:sub(1, 1)
  if kind == "H" or kind == "A" then
    peers[Ambiguate(sender, "none")] = sender
    local their = tonumber(msg:match("^%a:(%d+)")) or 0
    if kind == "H" then ns.SyncHello(sender, true) end
    if their > effectiveTime() then
      incoming = { from = sender, prices = {}, count = 0, started = GetTime() }
      send("R", sender)
    end
  elseif kind == "R" then
    sendPrices(sender)
  elseif kind == "P" then
    if not (incoming and sameName(incoming.from, sender)) then return end
    for k, v in msg:sub(2):gmatch("(%w+):(%w+)") do
      incoming.prices[tonumber(k, 36)] = tonumber(v, 36); incoming.count = incoming.count + 1
    end
  elseif kind == "E" then
    if not (incoming and sameName(incoming.from, sender)) then return end
    local t, n = msg:match("^E:(%d+):(%d+)")
    t, n = tonumber(t), tonumber(n)
    if t and incoming.count > 0 and incoming.count >= (n or 0) * 0.9 then
      DB().shared = { time = t, from = Ambiguate(sender, "none"), prices = incoming.prices, received = time() }
      local pushed = ns.PushToAuctionator(incoming.prices, t)
      ns.Print(("Prices synced from %s (%d)%s"):format(Ambiguate(sender, "none"), incoming.count,
        pushed > 0 and " + Auctionator" or ""))
      ns.Refresh(0)
    end
    incoming = nil
  end
end

-- ---------------------------------------------------------------- events
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, ev, prefix, msg, channel, sender)
  if ev == "PLAYER_LOGIN" then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    C_Timer.After(8, function() ns.SyncHello() end)
    local A = Auctionator and Auctionator.API and Auctionator.API.v1
    if A and A.RegisterForDBUpdate then
      -- After a scan here, tell the partner and anyone who has talked to us.
      pcall(A.RegisterForDBUpdate, ns.CALLER .. "Sync", function()
        C_Timer.After(3, function()
          local sent = {}
          if DB().partner then ns.SyncHello(); sent[Ambiguate(DB().partner, "none"):lower()] = true end
          for short, full in pairs(peers) do if not sent[short:lower()] then ns.SyncHello(full) end end
        end)
      end)
    end
  elseif ev == "CHAT_MSG_ADDON" and prefix == PREFIX and channel == "WHISPER" then
    onMessage(msg, sender)
  end
end)

-- ---------------------------------------------------------------- slash helpers (called from Core)
function ns.SetPartner(name)
  if (not name or name == "") and UnitExists("target") and UnitIsPlayer("target") then
    local n, realm = UnitName("target")
    name = (realm and realm ~= "") and (n .. "-" .. realm) or n
  end
  if not name or name == "" then ns.Print("Target your other character, then /bsu partner"); return end
  DB().partner = name
  ns.Print("Partner " .. name)
  ns.SyncHello()
end

function ns.SyncStatus()
  local s = DB().shared
  local function age(t) if not t or t == 0 then return "never" end; local m = math.floor((time() - t) / 60); return m < 60 and (m .. "m ago") or (math.floor(m / 60) .. "h ago") end
  ns.Print(("partner %s · own scan %s · shared %s%s"):format(DB().partner or "none", age(ns.OwnScanTime()),
    s and age(s.time) or "none", s and (" from " .. s.from) or ""))
end
