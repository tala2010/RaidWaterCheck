local _, RWC = ...

local BUTTON_RADIUS = 80

local function Settings()
  RWC:EnsureDB()
  return RaidWaterCheckDB.settings
end

local function Atan2(y, x)
  if math.atan2 then
    return math.atan2(y, x)
  end
  if x > 0 then
    return math.atan(y / x)
  elseif x < 0 and y >= 0 then
    return math.atan(y / x) + math.pi
  elseif x < 0 and y < 0 then
    return math.atan(y / x) - math.pi
  elseif y > 0 then
    return math.pi / 2
  elseif y < 0 then
    return -math.pi / 2
  end
  return 0
end

local function PositionButton(button)
  local angle = math.rad(Settings().minimapAngle or 225)
  local x = math.cos(angle) * BUTTON_RADIUS
  local y = math.sin(angle) * BUTTON_RADIUS
  button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function UpdateButtonPosition(button)
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  px, py = px / scale, py / scale

  local angle = math.deg(Atan2(py - my, px - mx))
  if angle < 0 then
    angle = angle + 360
  end
  Settings().minimapAngle = angle
  PositionButton(button)
end

function RWC:CreateMinimapButton()
  if self.minimapButton then
    return self.minimapButton
  end

  local button = CreateFrame("Button", "RaidWaterCheckMinimapButton", Minimap)
  button:SetSize(32, 32)
  button:SetFrameStrata("MEDIUM")
  button:SetMovable(true)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")

  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetSize(20, 20)
  button.icon:SetPoint("CENTER")
  button.icon:SetTexture("Interface\\Icons\\Ability_Rogue_FindWeakness")

  button.border = button:CreateTexture(nil, "OVERLAY")
  button.border:SetSize(54, 54)
  button.border:SetPoint("CENTER")
  button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("团本划水检测", 1, 1, 1)
    GameTooltip:AddLine("左键：打开操作面板", 0.8, 0.9, 1)
    GameTooltip:AddLine("右键：打开设置", 0.8, 0.9, 1)
    GameTooltip:AddLine("拖动：移动图标", 0.8, 0.9, 1)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", GameTooltip_Hide)

  button:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then
      RWC:ShowSettings()
    else
      RWC:ShowMainFrame()
    end
  end)

  button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", UpdateButtonPosition)
  end)
  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    PositionButton(self)
  end)

  self.minimapButton = button
  PositionButton(button)
  return button
end

function RWC:RefreshMinimapButton()
  local button = self:CreateMinimapButton()
  if Settings().minimapVisible then
    button:Show()
    PositionButton(button)
  else
    button:Hide()
  end
end

function RWC:ToggleMinimapButton()
  local settings = Settings()
  settings.minimapVisible = not settings.minimapVisible
  self:RefreshMinimapButton()
  self.Print("小地图按钮：" .. (settings.minimapVisible and "显示" or "隐藏"))
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
  RWC:RefreshMinimapButton()
end)

function RaidWaterCheck_OnAddonCompartmentClick(_, mouseButton)
  if mouseButton == "RightButton" then
    RWC:ShowSettings()
  else
    RWC:ShowMainFrame()
  end
end

function RaidWaterCheck_OnAddonCompartmentEnter(addonName, button)
  local owner = button or addonName
  if type(owner) ~= "table" or not owner.GetObjectType then
    owner = UIParent
  end

  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  GameTooltip:SetText("团本划水检测", 1, 1, 1)
  GameTooltip:AddLine("左键：打开操作面板", 0.8, 0.9, 1)
  GameTooltip:AddLine("右键：打开设置", 0.8, 0.9, 1)
  GameTooltip:Show()
end

function RaidWaterCheck_OnAddonCompartmentLeave()
  GameTooltip:Hide()
end
