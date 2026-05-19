local _, RWC = ...

local function Settings()
  RWC:EnsureDB()
  return RaidWaterCheckDB.settings
end

local function CreateText(parent, text, x, y, template)
  local label = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
  label:SetPoint("TOPLEFT", x, y)
  label:SetText(text)
  return label
end

local function CreateSection(parent, text, y)
  local title = CreateText(parent, text, 24, y, "GameFontNormalLarge")
  title:SetTextColor(1, 0.82, 0)

  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(1, 1, 1, 0.12)
  line:SetPoint("TOPLEFT", 24, y - 22)
  line:SetSize(672, 1)
end

local function FormatValue(value, suffix)
  if type(value) == "number" and value % 1 ~= 0 then
    return string.format("%.1f%s", value, suffix or "")
  end
  return tostring(value) .. (suffix or "")
end

local function HideSliderTemplateText(slider)
  if slider.Low then slider.Low:Hide() end
  if slider.High then slider.High:Hide() end
  if slider.Text then slider.Text:Hide() end

  local name = slider:GetName()
  if name then
    local low = _G[name .. "Low"]
    local high = _G[name .. "High"]
    local text = _G[name .. "Text"]
    if low then low:Hide() end
    if high then high:Hide() end
    if text then text:Hide() end
  end
end

local sliderIndex = 0

local function CreateCheckbox(page, label, key, x, y)
  local check = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
  check:SetPoint("TOPLEFT", x, y)
  check:SetSize(24, 24)

  local text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("LEFT", check, "RIGHT", 6, 0)
  text:SetWidth(280)
  text:SetJustifyH("LEFT")
  text:SetText(label)

  check:SetScript("OnClick", function(self)
    Settings()[key] = self:GetChecked() and true or false
  end)

  page.controls[#page.controls + 1] = {
    refresh = function()
      check:SetChecked(Settings()[key])
    end,
  }
end

local function CreateInlineCheckbox(page, label, key, x, y)
  local check = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
  check:SetPoint("TOPLEFT", x, y)
  check:SetSize(22, 22)

  local text = check:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("LEFT", check, "RIGHT", 4, 0)
  text:SetWidth(260)
  text:SetJustifyH("LEFT")
  text:SetText(label)
  text:SetTextColor(1, 0.82, 0)

  check:SetScript("OnClick", function(self)
    Settings()[key] = self:GetChecked() and true or false
  end)

  page.controls[#page.controls + 1] = {
    refresh = function()
      check:SetChecked(Settings()[key])
    end,
  }
end

local function CreateSlider(page, label, key, minValue, maxValue, step, x, y, suffix)
  local name = CreateText(page, label, x, y, "GameFontNormal")
  name:SetTextColor(1, 0.82, 0)

  local valueText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  valueText:SetPoint("TOPLEFT", page, "TOPLEFT", x + 250, y)
  valueText:SetWidth(110)
  valueText:SetJustifyH("LEFT")

  local low = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  low:SetPoint("TOPLEFT", page, "TOPLEFT", x, y - 54)
  low:SetText(tostring(minValue))

  local high = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  high:SetPoint("TOPRIGHT", page, "TOPLEFT", x + 620, y - 54)
  high:SetText(tostring(maxValue))

  sliderIndex = sliderIndex + 1
  local slider = CreateFrame("Slider", "RaidWaterCheckSettingsSlider" .. sliderIndex, page, "OptionsSliderTemplate")
  slider:SetPoint("TOPLEFT", x, y - 32)
  slider:SetWidth(620)
  slider:SetMinMaxValues(minValue, maxValue)
  slider:SetValueStep(step)
  HideSliderTemplateText(slider)
  if slider.SetObeyStepOnDrag then
    slider:SetObeyStepOnDrag(true)
  end

  slider:SetScript("OnValueChanged", function(_, value)
    local rounded = math.floor((value / step) + 0.5) * step
    if step >= 1 then
      rounded = math.floor(rounded + 0.5)
    end
    Settings()[key] = rounded
    valueText:SetText(FormatValue(rounded, suffix))
  end)

  page.controls[#page.controls + 1] = {
    refresh = function()
      local value = Settings()[key]
      slider:SetValue(value)
      valueText:SetText(FormatValue(value, suffix))
    end,
  }
end

local function CreatePage(frame, name)
  local page = CreateFrame("Frame", nil, frame)
  page:SetPoint("TOPLEFT", 14, -76)
  page:SetPoint("BOTTOMRIGHT", -14, 48)
  page.controls = {}
  page.name = name
  page:Hide()
  frame.pages[name] = page
  return page
end

function RWC:SelectSettingsPage(name)
  if not self.settingsFrame then
    return
  end

  for pageName, page in pairs(self.settingsFrame.pages) do
    if pageName == name then
      page:Show()
    else
      page:Hide()
    end
  end

  self.settingsFrame.basicTab:SetEnabled(name ~= "basic")
  self.settingsFrame.advancedTab:SetEnabled(name ~= "advanced")
  self.settingsFrame.weightsTab:SetEnabled(name ~= "weights")
  self:RefreshSettingsFrame()
end

function RWC:CreateSettingsFrame()
  if self.settingsFrame then
    return self.settingsFrame
  end

  local frame = CreateFrame("Frame", "RaidWaterCheckSettingsFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(820, 760)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetFrameLevel(200)
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame.pages = {}
  frame:Hide()

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  frame.title:SetPoint("TOPLEFT", 16, -8)
  frame.title:SetText("团本划水检测 - 设置")

  frame.basicTab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.basicTab:SetSize(120, 26)
  frame.basicTab:SetPoint("TOPLEFT", 24, -42)
  frame.basicTab:SetText("基础设置")
  frame.basicTab:SetScript("OnClick", function() RWC:SelectSettingsPage("basic") end)

  frame.advancedTab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.advancedTab:SetSize(120, 26)
  frame.advancedTab:SetPoint("LEFT", frame.basicTab, "RIGHT", 8, 0)
  frame.advancedTab:SetText("高级设置")
  frame.advancedTab:SetScript("OnClick", function() RWC:SelectSettingsPage("advanced") end)

  frame.weightsTab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.weightsTab:SetSize(120, 26)
  frame.weightsTab:SetPoint("LEFT", frame.advancedTab, "RIGHT", 8, 0)
  frame.weightsTab:SetText("权重设置")
  frame.weightsTab:SetScript("OnClick", function() RWC:SelectSettingsPage("weights") end)

  local basic = CreatePage(frame, "basic")
  CreateSection(basic, "记录与报告", -8)
  CreateCheckbox(basic, "战斗结束后自动弹出报告", "autoReport", 20, -44)
  CreateCheckbox(basic, "也记录小怪/非Boss战", "recordTrash", 400, -44)
  CreateSlider(basic, "最短记录战斗时长", "minFightSeconds", 5, 120, 5, 58, -98, " 秒")
  CreateSlider(basic, "报告显示人数", "maxRows", 5, 25, 1, 58, -180, " 人")
  CreateSlider(basic, "通报分数线", "announceScore", 0, 100, 5, 58, -262, " 分")
  CreateSection(basic, "WCL参考", -344)
  CreateCheckbox(basic, "启用 NAXX/WCL 冲分参考提示", "enableWclNaxxMode", 20, -380)

  local advanced = CreatePage(frame, "advanced")
  CreateSection(advanced, "无动作阈值", -8)
  CreateSlider(advanced, "无动作宽限时间", "idleGraceSeconds", 2, 20, 1, 58, -50, " 秒")
  CreateSlider(advanced, "轻度无动作阈值", "idleLightPct", 5, 30, 1, 58, -132, "%")
  CreateSlider(advanced, "中度无动作阈值", "idleMediumPct", 10, 45, 1, 58, -214, "%")
  CreateSlider(advanced, "重度无动作阈值", "idleHeavyPct", 20, 70, 1, 58, -296, "%")

  CreateSection(advanced, "死亡回放", -388)
  CreateInlineCheckbox(advanced, "启用死亡次数扣分", "enableDeathPenalty", 58, -424)
  CreateSlider(advanced, "死亡回溯秒数", "deathReplaySeconds", 4, 15, 1, 58, -470, " 秒")

  local weights = CreatePage(frame, "weights")
  CreateSection(weights, "贡献与施法", -8)
  CreateInlineCheckbox(weights, "启用施法频率扣分", "enableCastPenalty", 58, -44)
  CreateInlineCheckbox(weights, "启用贡献占比扣分", "enableContributionPenalty", 400, -44)

  CreateSection(weights, "承伤与机制", -104)
  CreateInlineCheckbox(weights, "启用承伤占比扣分", "enableTakenPenalty", 58, -140)
  CreateSlider(weights, "高承伤占比阈值", "highTakenPct", 5, 35, 1, 58, -184, "%")
  CreateInlineCheckbox(weights, "启用可规避伤害扣分", "enableAvoidablePenalty", 58, -266)
  CreateSlider(weights, "每次可规避伤害扣分", "avoidableHitPenalty", 2, 15, 1, 58, -310, " 分")

  CreateSection(weights, "关键技能", -402)
  CreateInlineCheckbox(weights, "启用关键技能缺失扣分", "enableTrackedPenalty", 58, -438)
  CreateSlider(weights, "缺失关键技能扣分", "missingTrackedPenalty", 2, 20, 1, 58, -482, " 分")

  local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  reset:SetSize(110, 24)
  reset:SetPoint("BOTTOMLEFT", 24, 16)
  reset:SetText("恢复默认")
  reset:SetScript("OnClick", function()
    RaidWaterCheckDB.settings = {}
    RWC:EnsureDB()
    RWC:RefreshSettingsFrame()
    RWC.Print("设置已恢复默认。")
  end)

  local show = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  show:SetSize(110, 24)
  show:SetPoint("LEFT", reset, "RIGHT", 10, 0)
  show:SetText("查看报告")
  show:SetScript("OnClick", function()
    if RWC.lastReport then
      RWC:ShowReport(RWC.lastReport)
    else
      RWC.Print("还没有报告。")
    end
  end)

  self.settingsFrame = frame
  self:SelectSettingsPage("basic")
  return frame
end

function RWC:RefreshSettingsFrame()
  if not self.settingsFrame then
    return
  end

  for _, page in pairs(self.settingsFrame.pages) do
    for _, control in ipairs(page.controls) do
      control.refresh()
    end
  end
end

function RWC:ShowSettings()
  local frame = self:CreateSettingsFrame()
  self:RefreshSettingsFrame()
  frame:Raise()
  frame:Show()
end
