local _, ns = ...

-- Adds "Skill-up % · Exp cost/pt" to the Blizzard Professions schematic, using the BestSkillUp settings.
local form, line, hooked

local function anchor()
  line:ClearAllPoints()
  local auc = AuctionatorCraftingInfoProfessionsFrame
  if auc and auc:IsShown() and auc.Total then
    line:SetPoint("TOPLEFT", auc.Total, "BOTTOMLEFT", 0, -2)
  elseif form.Reagents then
    line:SetPoint("TOPLEFT", form.Reagents, "BOTTOMLEFT", 0, -10)
  else
    line:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 20, 60)
  end
end

local function update()
  if not line then ns.HookNative() end
  if not line then return end
  local info = form.GetRecipeInfo and form:GetRecipeInfo()
  local id = info and info.recipeID
  local r, pline = ns.FindRecipe(id)
  if not r or not ns.CDB then line:Hide(); return end
  local P = ns.Prof(pline)
  local s = P.skill or 1
  local p = ns.Chance(id, r, s, pline)
  if (s < r[5] and not P.known[id]) or p <= 0 then line:Hide(); return end
  local text
  do
    local function per(mode)
      local c = ns.RecipeCost(r, mode)
      if c.missing > 0 then return "|cff808080no price|r" end
      if mode == "ahonly" and c.rsrc == "none" and r[2] > 0 then return "|cff808080no AH price|r" end
      return ns.Money(c.net / p)
    end
    local o, y, g, gr = ns.Thresholds(r)
    text = ("Skill-up: |cffffffff%d%%|r   |cffff8040%d|r |cffffff00%d|r |cff40c040%d|r |cff808080%d|r\nCost Per Point (Vendor): %s"):format(
      p * 100, o, y, g, gr, per("vendor"))
    if not ns.IsBoP(r[2]) then text = text .. "\nCost Per Point (AH): " .. per("ahonly") end
    if ns.DisenchantCounts(r[2]) and ns.DisenchantValue(r[2]) > 0 then text = text .. "\nCost Per Point (Disenchant): " .. per("de") end
  end
  line:SetText(text)
  anchor()
  line:Show()
end
ns.UpdateNative = update

local function hook()
  if hooked then return end
  form = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
  if not form or not form.Init then return end
  hooked = true
  line = form:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  line:SetJustifyH("LEFT"); line:SetSpacing(2)
  -- Run after Init so the recipe (and Auctionator's frame) is in place.
  hooksecurefunc(form, "Init", function() C_Timer.After(0, update) end)
  if EventRegistry and EventRegistry.RegisterCallback then
    pcall(EventRegistry.RegisterCallback, EventRegistry, "ProfessionsRecipeListMixin.Event.OnRecipeSelected", function() C_Timer.After(0, update) end, line)
  end
  if form.RegisterCallback and ProfessionsRecipeSchematicFormMixin and ProfessionsRecipeSchematicFormMixin.Event then
    pcall(form.RegisterCallback, form, ProfessionsRecipeSchematicFormMixin.Event.AllocationsModified, function() C_Timer.After(0, update) end, line)
  end
end
ns.HookNative = hook

function ns.DebugNative()
  local info = form and form.GetRecipeInfo and form:GetRecipeInfo()
  local id = info and info.recipeID
  local r, pline = ns.FindRecipe(id)
  local skill = r and ns.CDB and ns.Prof(pline).skill
  ns.Print(("native hooked=%s form=%s recipe=%s inData=%s prof=%s skill=%s chance=%s shown=%s"):format(
    tostring(hooked), tostring(form ~= nil), tostring(id), tostring(r ~= nil), r and ns.ProfName(pline) or "-", tostring(skill),
    r and ("%.2f"):format(ns.Chance(id, r, skill or 1, pline)) or "-", tostring(line and line:IsShown())))
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("TRADE_SKILL_SHOW")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
f:SetScript("OnEvent", function(_, ev, name)
  if ev == "GET_ITEM_INFO_RECEIVED" then
    if ns.OnItemInfo and ns.OnItemInfo(name) then ns.Refresh(0.5)
    elseif line and line:IsShown() then C_Timer.After(0, update) end
    return
  end
  if ev == "ADDON_LOADED" and name ~= "Blizzard_Professions" then return end
  if ev == "PLAYER_LOGIN" and not ProfessionsFrame then return end
  hook()
  if ev == "TRADE_SKILL_SHOW" then C_Timer.After(0.2, update) end
end)
