local _, ns = ...
local UI = {}
ns.UI = UI

local ROWS, ROW_H, W = 16, 16, 340
local TOP = 32
local COLOURS = { orange = "|cffff8040", yellow = "|cffffff00", green = "|cff40c040", grey = "|cff808080" }
local frame, rows, summary, optBtn, opts, unlearnedCB
local list, offset, listFor = {}, 0, nil   -- the ranked list, the first row shown, and which profession it is for
local scrollTrack, scrollThumb
local checks = {}
local skin                       -- EllesmereUI skin facade, if available
local skinFonts, skinBoxes = {}, {}
local function skinFont(fs) skinFonts[#skinFonts + 1] = fs; if skin then skin.Font(fs) end; return fs end
local openedBySlash, dismissed, showOpts = false, false, false

local function DB() return ns.DB end

-- ---------------------------------------------------------------- list
local itemTip, costTip
local function hideCompare(t)
  for _, st in ipairs(t.shoppingTooltips or {}) do
    if st:IsShown() and st:GetOwner() == t then st:Hide() end
  end
end

local function tip(name, item)
  local t = CreateFrame("GameTooltip", name, UIParent, "GameTooltipTemplate")
  t:SetFrameStrata("TOOLTIP")
  if item then
    -- No "Equipped" comparison unless Shift is held.
    t.supportsItemComparison = false
    t:HookScript("OnUpdate", function(self) if not IsShiftKeyDown() then hideCompare(self) end end)
  end
  return t
end

local function showRecipeTooltip(row)
  local x = row.x
  itemTip = itemTip or tip("BestSkillUpItemTip", true)
  costTip = costTip or tip("BestSkillUpCostTip")

  itemTip:SetOwner(frame, "ANCHOR_NONE")
  itemTip:ClearAllPoints()
  itemTip:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, 0)
  local out = x.r[2]
  if out and out > 0 then
    itemTip:SetHyperlink("item:" .. out)
    -- Auctionator only adds its price to GameTooltip, so add the line ourselves (for what one craft makes).
    local made = math.max(1, x.r[3] or 1)
    local ah = ns.AHPrice(out)
    itemTip:AddDoubleLine("Auction x" .. made, ah and ns.Money(ah * made) or "|cff808080no price|r", 0.4, 0.73, 1, 1, 1, 1)
  else
    itemTip:AddLine(x.r[1])
  end
  itemTip:Show()

  costTip:SetOwner(frame, "ANCHOR_NONE")
  costTip:ClearAllPoints()
  costTip:SetPoint("TOPLEFT", itemTip, "BOTTOMLEFT", 0, -2)
  costTip:AddLine(COLOURS[x.colour] .. x.r[1] .. "|r")
  costTip:AddDoubleLine(("%d%%  ·  %.2f crafts/pt"):format(x.p * 100, 1 / x.p), ns.Money(x.perPt) .. "/pt", 1, 1, 1)
  for _, l in ipairs(x.c.lines) do
    costTip:AddDoubleLine(l.q .. "x " .. ns.ItemColor(l.id) .. ns.ItemName(l.id) .. "|r",
      (l.u.p and ns.Money(l.u.p * l.q) or "?") .. " |cff808080" .. l.u.src .. "|r", 1, 1, 1)
  end
  if x.c.back > 0 then costTip:AddDoubleLine("Back", ns.Money(x.c.back) .. " |cff808080" .. x.c.rsrc .. "|r", 0.6, 0.6, 0.6) end
  costTip:AddDoubleLine("Net", ns.Money(x.c.net), 0.6, 0.6, 0.6)
  local o, y, g, gr = ns.Thresholds(x.r)
  costTip:AddLine(("|cffff8040%d|r |cffffff00%d|r |cff40c040%d|r |cff808080%d|r"):format(o, y, g, gr))
  if x.r.pinned then costTip:AddLine("Disenchant an item you already have. Odds estimated (Classic).", 0.6, 0.6, 0.6) end
  if not x.known and ns.Prof().scanned then costTip:AddLine("Not learned · " .. x.r[9], 1, 0.4, 0.4) end
  costTip:Show()
  UI.hovered = row
end

local function hideTooltips()
  UI.hovered = nil
  if itemTip then itemTip:Hide() end
  if costTip then costTip:Hide() end
end

-- Re-draw when item data arrives (first hover of an uncached item).
local loader = CreateFrame("Frame")
loader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
loader:SetScript("OnEvent", function(_, _, id)
  local row = UI.hovered
  if row and row.x and row.x.r[2] == id and row:IsMouseOver() then showRecipeTooltip(row) end
end)

local function makeRow(i)
  local b = CreateFrame("Button", nil, frame)
  b:SetSize(W - 24, ROW_H)
  b:SetPoint("TOPLEFT", 8, -TOP - (i - 1) * ROW_H)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  b.left = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.left:SetPoint("LEFT", 2, 0); b.left:SetWidth(190); b.left:SetJustifyH("LEFT"); b.left:SetWordWrap(false)
  b.mid = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.mid:SetPoint("LEFT", 194, 0); b.mid:SetWidth(36); b.mid:SetJustifyH("RIGHT")
  b.right = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.right:SetPoint("RIGHT", -2, 0); b.right:SetJustifyH("RIGHT")
  skinFont(b.left); skinFont(b.mid); skinFont(b.right)
  b:SetScript("OnEnter", function(self) if self.x then showRecipeTooltip(self) end end)
  b:SetScript("OnLeave", hideTooltips)
  b:SetScript("OnClick", function(self)
    if not self.x then return end
    if IsShiftKeyDown() then UI.ShowLink(self.x) else ns.SelectRecipe(self.x.id) end
  end)
  return b
end

-- ---------------------------------------------------------------- scrolling
local function maxOffset() return math.max(0, #list - ROWS) end

local function updateScrollbar()
  local n = #list
  if showOpts or n <= ROWS then scrollTrack:Hide(); return end
  scrollTrack:Show()
  local h = scrollTrack:GetHeight()
  local th = math.max(16, h * ROWS / n)
  scrollThumb:SetHeight(th)
  scrollThumb:ClearAllPoints()
  scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -(h - th) * offset / maxOffset())
end

local renderRows
local function scrollTo(o)
  o = math.max(0, math.min(maxOffset(), math.floor(o + 0.5)))
  if o == offset then return end
  offset = o
  hideTooltips()
  renderRows()
end

function renderRows()
  local scanned = ns.Prof().scanned
  local n = #list
  if n > ROWS then
    summary:SetText(("%d-%d of %d options"):format(offset + 1, math.min(offset + ROWS, n), n))
  else
    summary:SetText(n .. " options")
  end
  for i = 1, ROWS do
    local x, b = list[offset + i], rows[i]
    if x and not showOpts then
      b.x = x
      if x.r[2] > 0 and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, x.r[2]) end
      b.left:SetText(COLOURS[x.colour] .. x.r[1] .. "|r" .. ((not x.known and scanned) and " |cffff6060*|r" or ""))
      b.mid:SetText(("%d%%"):format(x.p * 100))
      b.right:SetText(ns.Money(x.perPt))
      b:Show()
    else
      b.x = nil; b:Hide()
    end
  end
  updateScrollbar()
end

local function fillList()
  list = ns.Evaluate()
  if listFor ~= ns.active then offset, listFor = 0, ns.active end   -- new profession: back to the top
  offset = math.min(offset, maxOffset())
  renderRows()
end

function UI.ScrollInfo() return offset, #list, ROWS end

-- Mouse wheel: 3 rows a notch, a page with Shift. The bar on the right can be dragged or clicked.
local function buildScroll()
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, delta)
    if showOpts then return end
    scrollTo(offset - delta * (IsShiftKeyDown() and ROWS or 3))
  end)
  scrollTrack = CreateFrame("Button", nil, frame)
  scrollTrack:SetPoint("TOPRIGHT", -6, -TOP)
  scrollTrack:SetSize(6, ROWS * ROW_H)
  local bg = scrollTrack:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.08)
  scrollThumb = CreateFrame("Frame", nil, scrollTrack)
  scrollThumb:SetWidth(6)
  local tex = scrollThumb:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints(); tex:SetColorTexture(0.91, 0.76, 0.35, 0.7)
  local function offsetAtCursor()
    local _, y = GetCursorPosition()
    y = y / scrollTrack:GetEffectiveScale()
    local top, h = scrollTrack:GetTop(), scrollTrack:GetHeight()
    local th = scrollThumb:GetHeight()
    local frac = (top - y - th / 2) / math.max(1, h - th)
    return frac * maxOffset()
  end
  scrollTrack:SetScript("OnMouseDown", function(self)
    scrollTo(offsetAtCursor())
    self:SetScript("OnUpdate", function() scrollTo(offsetAtCursor()) end)
  end)
  scrollTrack:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
  scrollTrack:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
  scrollTrack:Hide()
end

-- Addons can't open a browser: show the Wowhead URL ready to copy.
local linkFrame
function UI.ShowLink(x)
  local url = "https://www.wowhead.com/forever/spell=" .. x.id
  if not linkFrame then
    local f = CreateFrame("Frame", "BestSkillUpLinkFrame", UIParent, "BackdropTemplate")
    f:SetSize(380, 64); f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("DIALOG"); f:SetToplevel(true); f:EnableMouse(true)
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.06, 0.05, 0.04, 0.97); f:SetBackdropBorderColor(0.55, 0.45, 0.25, 1)
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("TOPLEFT", 10, -9)
    local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    eb:SetSize(350, 20); eb:SetPoint("BOTTOM", 2, 10); eb:SetAutoFocus(false)
    eb:SetScript("OnTextChanged", function(self, user) if user then self:SetText(f.url); self:HighlightText() end end)
    eb:SetScript("OnEnterPressed", function() f:Hide() end)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnEditFocusLost", function() f:Hide() end)
    eb:SetScript("OnKeyUp", function(_, key) if key == "C" and IsControlKeyDown() then C_Timer.After(0.05, function() f:Hide() end) end end)
    f.eb = eb
    linkFrame = f
    skinFont(f.label)
    if skin then f:SetBackdrop(nil); skin.Panel(f); skin.EditBox(eb) end
  end
  linkFrame.url = url
  linkFrame.label:SetText(x.r[1] .. "  ·  Ctrl+C")
  linkFrame:Show()
  linkFrame.eb:SetText(url)
  linkFrame.eb:SetFocus()
  linkFrame.eb:HighlightText()
end

-- ---------------------------------------------------------------- options
local function header(parent, text, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", 4, y); fs:SetText(text)
  skinFont(fs)
end

local function check(parent, label, x, y, get, set)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(20, 20); cb:SetPoint("TOPLEFT", x, y)
  local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", cb, "RIGHT", 0, 1); fs:SetText(label)
  skinFont(fs)
  cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); UI.SyncOptions(); ns.Refresh(0) end)
  cb.get = get
  checks[#checks + 1] = cb
  return cb
end

local function numBox(parent, label, x, y, key)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", x, y - 4); fs:SetText(label)
  skinFont(fs)
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetSize(30, 16); eb:SetPoint("LEFT", fs, "RIGHT", 8, 0)
  eb:SetAutoFocus(false); eb:SetNumeric(true); eb:SetMaxLetters(3)
  skinBoxes[#skinBoxes + 1] = eb
  eb:SetScript("OnShow", function(self) self:SetText(tostring(DB()[key])) end)
  local function commit(self)
    local v = tonumber(self:GetText()); if v then DB()[key] = math.min(100, v) end
    self:SetText(tostring(DB()[key])); self:ClearFocus(); ns.Refresh(0)
  end
  eb:SetScript("OnEnterPressed", commit)
  eb:SetScript("OnEditFocusLost", commit)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
end

local function buildOptions()
  opts = CreateFrame("Frame", nil, frame)
  opts:SetPoint("TOPLEFT", 8, -TOP); opts:SetPoint("BOTTOMRIGHT", -8, 28)
  opts:Hide()
  local src, rg = DB().sources, DB().reagents
  local y = 0
  header(opts, "Recipe sources", y); y = y - 14
  local cols = { 0, 108, 216 }
  local items = { { "Trainer", "trainer" }, { "Vendor", "vendor" }, { "Drop", "drop" }, { "Quest", "quest" }, { "Other", "other" } }
  for i, it in ipairs(items) do
    local c, r = (i - 1) % 3, math.floor((i - 1) / 3)
    check(opts, it[1], cols[c + 1], y - r * 20, function() return DB().sources[it[2]] end, function(v) DB().sources[it[2]] = v end)
  end
  check(opts, "Unlearned", cols[3], y - 20, function() return DB().includeUnlearned end, function(v) DB().includeUnlearned = v end)
  y = y - 48

  header(opts, "Reagent sources", y); y = y - 14
  check(opts, "Vendor", cols[1], y, function() return DB().reagents.vendor end, function(v) DB().reagents.vendor = v end)
  check(opts, "Auction House", cols[2], y, function() return DB().reagents.ah end, function(v) DB().reagents.ah = v end)
  check(opts, "Wowhead avg", cols[3], y, function() return DB().useWH end, function(v) DB().useWH = v end)
  check(opts, "Craft", cols[1], y - 20, function() return DB().reagents.craft end, function(v) DB().reagents.craft = v end)
  check(opts, "Smelt (Mining)", cols[2], y - 20, function() return DB().reagents.smelt end, function(v) DB().reagents.smelt = v end)
  y = y - 48

  header(opts, "Value of crafted items", y); y = y - 14
  for i, it in ipairs({ { "Ignore", "none" }, { "Vendor", "vendor" }, { "AH or vendor", "ah" } }) do
    check(opts, it[1], cols[i], y, function() return DB().resale == it[2] end, function() DB().resale = it[2] end)
  end
  check(opts, "Disenchant", cols[1], y - 20, function() return ns.UseDisenchant() end, function(v) DB().disenchant = v end)
  y = y - 46
  numBox(opts, "AH cut %", 4, y, "ahCut")
  numBox(opts, "Sell-through %", 112, y, "ahSellThrough")
end

function UI.SyncOptions()
  for _, cb in ipairs(checks) do cb:SetChecked(cb.get() and true or false) end
  if unlearnedCB then unlearnedCB:SetChecked(DB().includeUnlearned) end
end

-- ---------------------------------------------------------------- frame
function UI.Update()
  if not frame or not frame:IsShown() then return end
  local c = ns.Prof()
  frame.title:SetText("BSU · " .. ns.ProfName() .. " " .. (c.skill and (c.skill .. "/" .. (c.maxSkill or "?")) or "?"))
  optBtn:SetText(showOpts and "Back" or "Options")
  opts:SetShown(showOpts)
  unlearnedCB:SetShown(not showOpts)
  UI.SyncOptions()
  fillList()
  if showOpts then summary:SetText("") end
end

local function anchor()
  frame:ClearAllPoints()
  local p = DB().point
  if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  elseif ProfessionsFrame and ProfessionsFrame:IsShown() then frame:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 2, 0)
  elseif TradeSkillFrame and TradeSkillFrame:IsShown() then frame:SetPoint("TOPLEFT", TradeSkillFrame, "TOPRIGHT", 2, 0)
  else frame:SetPoint("CENTER") end
end

local function build()
  frame = CreateFrame("Frame", "BestSkillUpFrame", UIParent, "BackdropTemplate")
  frame:SetSize(W, TOP + ROWS * ROW_H + 30)
  frame:SetFrameStrata("HIGH")
  frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  frame:SetBackdropColor(0.06, 0.05, 0.04, 0.95)
  frame:SetBackdropBorderColor(0.55, 0.45, 0.25, 1)
  frame:SetMovable(true); frame:EnableMouse(true); frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local a, _, b, x, y = self:GetPoint()
    DB().point = { a, b, x, y }
  end)
  frame:Hide()
  tinsert(UISpecialFrames, "BestSkillUpFrame")

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.title:SetPoint("TOPLEFT", 10, -10)
  -- Click the title to show the next profession.
  local switch = CreateFrame("Button", nil, frame)
  switch:SetPoint("TOPLEFT", frame.title, "TOPLEFT", -2, 2)
  switch:SetPoint("BOTTOMRIGHT", frame.title, "BOTTOMRIGHT", 2, -2)
  switch:SetScript("OnClick", function() ns.CycleActive(); ns.Refresh(0) end)
  switch:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Click to show the next profession", 1, 1, 1); GameTooltip:Show()
  end)
  switch:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  frame.close = close
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() frame:Hide(); openedBySlash = false; dismissed = true end)

  unlearnedCB = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  unlearnedCB:SetSize(20, 20); unlearnedCB:SetPoint("TOPRIGHT", -50, -6)
  local ul = unlearnedCB:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ul:SetPoint("LEFT", unlearnedCB, "RIGHT", 0, 1); ul:SetText("All")
  frame.unlearnedLabel = ul
  unlearnedCB:SetScript("OnClick", function(self) DB().includeUnlearned = self:GetChecked() and true or false; ns.Refresh(0) end)

  rows = {}
  for i = 1, ROWS do rows[i] = makeRow(i) end
  buildScroll()
  buildOptions()

  summary = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  summary:SetPoint("BOTTOMLEFT", 10, 10)

  optBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  optBtn:SetSize(70, 18); optBtn:SetPoint("BOTTOMRIGHT", -8, 7)
  optBtn:SetScript("OnClick", function() showOpts = not showOpts; UI.Update() end)

  frame:SetScript("OnShow", function() anchor(); ns.ClearCache(); UI.Update() end)
  if skin then UI.ApplySkin(skin) end
end

-- EllesmereUI theme (its public skinning API). Safe to call more than once.
function UI.ApplySkin(S)
  skin = S
  if not frame then return end
  frame:SetBackdrop(nil)
  S.Shell(frame)
  S.CloseButton(frame.close)
  S.Button(optBtn)
  S.Checkbox(unlearnedCB)
  for _, cb in ipairs(checks) do S.Checkbox(cb) end
  for _, eb in ipairs(skinBoxes) do S.EditBox(eb) end
  S.Font(frame.title); S.Font(summary); S.Font(frame.unlearnedLabel)
  for _, fs in ipairs(skinFonts) do S.Font(fs) end
  if linkFrame then linkFrame:SetBackdrop(nil); S.Panel(linkFrame); S.EditBox(linkFrame.eb) end
end

if EllesmereUI and EllesmereUI.RegisterSkin then
  EllesmereUI.RegisterSkin("BestSkillUp", function(S) UI.ApplySkin(S) end)
end

function UI.Init() if not frame then build() end end
function UI.Toggle()
  UI.Init()
  if frame:IsShown() then frame:Hide(); openedBySlash = false else openedBySlash = true; frame:Show() end
end
function UI.ShowOptions()
  UI.Init(); showOpts = true
  if not frame:IsShown() then openedBySlash = true; frame:Show() else UI.Update() end
end
function UI.OnProfessionShown()
  UI.Init()
  if DB().shown and not dismissed and not frame:IsShown() then frame:Show() end
end
function UI.OnProfessionHidden()
  dismissed = false
  if frame and frame:IsShown() and not openedBySlash then frame:Hide() end
end
function UI.ResetPosition() if frame then anchor() end end
