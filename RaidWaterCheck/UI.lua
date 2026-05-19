local _, RWC = ...

local function FormatNumber(value)
  value = value or 0
  if value >= 100000000 then
    return string.format("%.1f亿", value / 100000000)
  elseif value >= 10000 then
    return string.format("%.1f万", value / 10000)
  end
  return tostring(math.floor(value + 0.5))
end

local function FormatDuration(seconds)
  seconds = math.floor(seconds or 0)
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function StatusText(score)
  local settings = RaidWaterCheckDB and RaidWaterCheckDB.settings or RWC.defaults
  if score <= (settings.dangerScore or 45) then
    return "|cffff5555高疑似|r"
  elseif score <= (settings.reviewScore or 65) then
    return "|cffffaa33需复盘|r"
  elseif score <= (settings.warningScore or 80) then
    return "|cffffff55略异常|r"
  end
  return "|cff55ff88正常|r"
end

local function ClassColorText(name, class)
  local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if color and color.colorStr then
    return "|c" .. color.colorStr .. tostring(name or "") .. "|r"
  end
  return tostring(name or "")
end

local function JoinReasons(reasons)
  if not reasons or #reasons == 0 then
    return "无明显异常"
  end
  return table.concat(reasons, "；")
end

local function TopEntries(map, limit, mode)
  local rows = {}
  for _, item in pairs(map or {}) do
    rows[#rows + 1] = item
  end
  table.sort(rows, function(a, b)
    if mode == "count" then
      if a.count == b.count then
        return a.name < b.name
      end
      return a.count > b.count
    end
    if a.amount == b.amount then
      return a.name < b.name
    end
    return a.amount > b.amount
  end)

  local out = {}
  for i = 1, math.min(limit or 5, #rows) do
    local item = rows[i]
    if mode == "count" then
      out[#out + 1] = string.format("%s x%d", item.name, item.count)
    else
      out[#out + 1] = string.format("%s %s", item.name, FormatNumber(item.amount))
    end
  end
  if #out == 0 then
    return "无记录"
  end
  return table.concat(out, "\n")
end

local function TopReasonText(reasons)
  local rows = {}
  for reason, count in pairs(reasons or {}) do
    rows[#rows + 1] = { reason = reason, count = count }
  end
  table.sort(rows, function(a, b)
    if a.count == b.count then
      return a.reason < b.reason
    end
    return a.count > b.count
  end)

  local out = {}
  for i = 1, math.min(2, #rows) do
    out[#out + 1] = rows[i].reason .. "x" .. rows[i].count
  end
  if #out == 0 then
    return "无明显异常"
  end
  return table.concat(out, "；")
end

local function WclWarningText(player)
  local lines = {}
  if player and player.wclExcludedDamage and player.wclExcludedDamage > 0 then
    lines[#lines + 1] = string.format("可能不计入WCL目标伤害：%s，命中%d次", FormatNumber(player.wclExcludedDamage), player.wclExcludedHits or 0)
  end
  for key, warning in pairs((player and player.wclWarnings) or {}) do
    if type(key) == "number" then
      lines[#lines + 1] = warning
    else
      lines[#lines + 1] = tostring(key) .. (warning and warning > 1 and (" x" .. tostring(warning)) or "")
    end
  end
  if #lines == 0 then
    return "无WCL冲分提示"
  end
  return table.concat(lines, "\n")
end

local function SummaryReasonText(player, bossMode)
  if bossMode then
    return JoinReasons(player.reasons)
  end
  return TopReasonText(player.reasons)
end

local function DeathReplayText(deathEvents, limitDeaths)
  if not deathEvents or #deathEvents == 0 then
    return "无死亡记录"
  end

  local lines = {}
  local startIndex = math.max(1, #deathEvents - (limitDeaths or 2) + 1)
  for i = startIndex, #deathEvents do
    local death = deathEvents[i]
    local title = string.format("死亡 %d：", i)
    if death.killingBlow then
      title = title .. string.format(" 最后一击 %s %s", death.killingBlow.spellName or "未知技能", FormatNumber(death.killingBlow.amount or 0))
    end
    if death.maxHit then
      title = title .. string.format("，最大 %s %s", death.maxHit.spellName or "未知技能", FormatNumber(death.maxHit.amount or 0))
    end
    if (death.avoidableCount or 0) > 0 then
      title = title .. string.format("，可规避 %d 次", death.avoidableCount)
    end
    lines[#lines + 1] = title

    for _, hit in ipairs(death.hits or {}) do
      lines[#lines + 1] = string.format(
        "  - %.1fs前 %s %s %s%s",
        hit.secondsBeforeDeath or 0,
        hit.source or "未知来源",
        hit.spellName or "未知技能",
        FormatNumber(hit.amount or 0),
        hit.avoidable and " 可规避" or ""
      )
    end
  end

  return table.concat(lines, "\n")
end

function RWC:CreateMainFrame()
  if self.mainFrame then
    return self.mainFrame
  end

  local frame = CreateFrame("Frame", "RaidWaterCheckMainFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(360, 180)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetFrameLevel(215)
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:Hide()

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  frame.title:SetPoint("TOPLEFT", 16, -8)
  frame.title:SetText("团本划水检测")

  frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.status:SetPoint("TOPLEFT", 22, -42)
  frame.status:SetWidth(310)
  frame.status:SetJustifyH("LEFT")
  frame.status:SetText("")

  local function MakeButton(text, x, y, width, onClick)
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(width or 92, 26)
    button:SetPoint("TOPLEFT", x, y)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
  end

  MakeButton("单场报告", 22, -78, 96, function()
    if RWC.lastReport then
      RWC:ShowReport(RWC.lastReport)
    else
      RWC.Print("还没有单场报告。")
    end
  end)
  MakeButton("副本总结", 132, -78, 96, function()
    if RWC.lastRunSummary then
      RWC:ShowRunSummary(RWC.lastRunSummary)
    else
      RWC.Print("还没有副本总结。")
    end
  end)
  MakeButton("设置", 242, -78, 76, function()
    RWC:ShowSettings()
  end)
  MakeButton("清除记录", 22, -118, 96, function()
    RWC:ClearReports()
  end)
  MakeButton("使用说明", 132, -118, 96, function()
    RWC:ShowHelpFrame()
  end)

  self.mainFrame = frame
  return frame
end

function RWC:ShowMainFrame()
  local frame = self:CreateMainFrame()
  local reportText = self.lastReport and "有单场报告" or "无单场报告"
  local summaryText = self.lastRunSummary and "有副本总结" or "无副本总结"
  frame.status:SetText(reportText .. " · " .. summaryText)
  frame:Show()
  frame:Raise()
end

function RWC:CreateHelpFrame()
  if self.helpFrame then
    return self.helpFrame
  end

  local frame = CreateFrame("Frame", "RaidWaterCheckHelpFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(660, 560)
  frame:SetPoint("CENTER", 30, -30)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetFrameLevel(220)
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:Hide()

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  frame.title:SetPoint("TOPLEFT", 16, -8)
  frame.title:SetText("使用说明")

  frame.body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.body:SetPoint("TOPLEFT", 24, -44)
  frame.body:SetWidth(610)
  frame.body:SetJustifyH("LEFT")
  frame.body:SetJustifyV("TOP")
  frame.body:SetText(table.concat({
    "|cffffff00常用命令|r",
    "/rwc menu  打开操作面板",
    "/rwc show  查看最近一场单场报告",
    "/rwc summary  查看副本总结",
    "/rwc reset  清除当前报告和统计",
    "/rwc options  打开设置",
    "",
    "|cffffff00设置项说明|r",
    "战斗结束后自动弹出报告：Boss 结束后自动显示单场报告。",
    "也记录小怪/非Boss战：默认只记 Boss，勾选后普通战斗也会生成记录。",
    "NAXX/WCL 冲分参考：提示可能不计入 WCL 的目标伤害或特殊 Buff，只作参考。",
    "死亡次数扣分：死亡会降低复盘分，但仍要结合战术安排判断。",
    "施法频率扣分：施法/出手过少会扣分，适合发现长时间发呆。",
    "贡献占比扣分：伤害或有效治疗占比过低会扣分，工具人/机制位需人工判断。",
    "承伤占比扣分：承伤占比异常高会扣分，坦克或机制位可能天然更高。",
    "可规避伤害扣分：吃到你们配置的可规避技能会扣分。",
    "关键技能缺失扣分：没按规则交爆发、减伤、战复等关键技能会扣分。",
    "",
    "|cffffff00使用技巧|r",
    "1. 打完 Boss 后先看单场报告，点玩家行能看个人详情。",
    "2. 打完整个副本后看副本总结，点 Boss 按钮回溯单个 Boss。",
    "3. 副本总结里点玩家行，可以看这个人整场副本的汇总详情。",
    "4. NAXX/WCL 参考只提醒可能影响冲分的数据，最终仍以 WCL 上传结果为准。",
    "",
    "|cffffff00提醒|r",
    "这个插件是复盘辅助，不是判决书。低分可能来自机制分工、转火、跑位、死亡、装等、职业环境或团队策略。团长应结合分工和日志判断。"
  }, "\n"))

  self.helpFrame = frame
  return frame
end

function RWC:ShowHelpFrame()
  local frame = self:CreateHelpFrame()
  frame:Show()
  frame:Raise()
end

function RWC:CreateReportFrame()
  if self.reportFrame then
    return self.reportFrame
  end

  local frame = CreateFrame("Frame", "RaidWaterCheckReportFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(980, 520)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetFrameLevel(190)
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:Hide()

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  frame.title:SetPoint("TOPLEFT", 16, -8)
  frame.title:SetText("团本划水检测")

  frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.subtitle:SetPoint("TOPLEFT", 18, -36)
  frame.subtitle:SetText("")

  frame.header = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.header:SetPoint("TOPLEFT", 18, -68)
  frame.header:SetText("分数越低越需要复盘；这不是判决书，优先结合机制分工和日志看。")

  local columns = {
    { text = "玩家", x = 18, width = 110 },
    { text = "状态", x = 130, width = 70 },
    { text = "分数", x = 205, width = 45 },
    { text = "伤害", x = 255, width = 70 },
    { text = "治疗", x = 330, width = 70 },
    { text = "承伤", x = 405, width = 70 },
    { text = "可规避", x = 480, width = 60 },
    { text = "施法", x = 545, width = 45 },
    { text = "打断", x = 595, width = 45 },
    { text = "驱散", x = 645, width = 45 },
    { text = "死亡", x = 695, width = 45 },
    { text = "原因", x = 745, width = 210 },
  }

  for _, column in ipairs(columns) do
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", column.x, -96)
    text:SetWidth(column.width)
    text:SetJustifyH("LEFT")
    text:SetText(column.text)
  end

  frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  frame.scroll:SetPoint("TOPLEFT", 18, -126)
  frame.scroll:SetPoint("BOTTOMRIGHT", -36, 44)

  frame.scrollChild = CreateFrame("Frame", nil, frame.scroll)
  frame.scrollChild:SetSize(944, 25 * 29)
  frame.scroll:SetScrollChild(frame.scrollChild)

  frame.rows = {}
  for i = 1, 25 do
    local row = CreateFrame("Frame", nil, frame.scrollChild)
    row:SetSize(944, 27)
    row:SetPoint("TOPLEFT", 0, -((i - 1) * 29))
    row:EnableMouse(true)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0.08)
    row:SetScript("OnEnter", function(self)
      if not self.tooltipText then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.tooltipTitle or "详情", 1, 1, 1)
      GameTooltip:AddLine(self.tooltipText, nil, nil, nil, true)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnMouseUp", function(self, button)
      if button == "LeftButton" and self.player then
        RWC:ShowPlayerDetail(self.player, self.fightName)
      end
    end)

    row.fields = {}
    for key, column in ipairs(columns) do
      local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      text:SetPoint("LEFT", row, "LEFT", column.x - 18, 0)
      text:SetWidth(column.width)
      text:SetJustifyH("LEFT")
      text:SetWordWrap(false)
      row.fields[key] = text
    end

    frame.rows[i] = row
  end

  frame.announce = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.announce:SetSize(92, 24)
  frame.announce:SetPoint("BOTTOMLEFT", 18, 12)
  frame.announce:SetText("通报异常")
  frame.announce:SetScript("OnClick", function()
    RWC:AnnounceReport(RWC.lastReport)
  end)

  frame.options = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.options:SetSize(70, 24)
  frame.options:SetPoint("LEFT", frame.announce, "RIGHT", 8, 0)
  frame.options:SetText("设置")
  frame.options:SetScript("OnClick", function()
    RWC:ShowSettings()
  end)

  frame.summary = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.summary:SetSize(90, 24)
  frame.summary:SetPoint("LEFT", frame.options, "RIGHT", 8, 0)
  frame.summary:SetText("副本总结")
  frame.summary:SetScript("OnClick", function()
    if RWC.lastRunSummary then
      RWC:ShowRunSummary(RWC.lastRunSummary)
    else
      RWC.Print("还没有副本总结。")
    end
  end)

  frame.clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.clear:SetSize(88, 24)
  frame.clear:SetPoint("LEFT", frame.summary, "RIGHT", 8, 0)
  frame.clear:SetText("清除记录")
  frame.clear:SetScript("OnClick", function()
    RWC:ClearReports()
  end)

  frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.footer:SetPoint("BOTTOMLEFT", 484, 24)
  frame.footer:SetWidth(470)
  frame.footer:SetJustifyH("LEFT")
  frame.footer:SetText("")

  self.reportFrame = frame
  return frame
end

function RWC:CreateRunSummaryFrame()
  if self.runSummaryFrame then
    return self.runSummaryFrame
  end

  local frame = CreateFrame("Frame", "RaidWaterCheckRunSummaryFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(980, 620)
  frame:SetPoint("CENTER", 20, -20)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetFrameLevel(205)
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:Hide()

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  frame.title:SetPoint("TOPLEFT", 16, -8)
  frame.title:SetText("副本总结")

  frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.subtitle:SetPoint("TOPLEFT", 18, -36)
  frame.subtitle:SetText("")

  frame.bossesTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.bossesTitle:SetPoint("TOPLEFT", 18, -62)
  frame.bossesTitle:SetText("Boss 记录：")

  frame.bossPickerOpen = false

  frame.bossToggle = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.bossToggle:SetSize(120, 22)
  frame.bossToggle:SetPoint("TOPLEFT", 18, -84)
  frame.bossToggle:SetText("展开Boss列表")
  frame.bossToggle:SetScript("OnClick", function()
    frame.bossPickerOpen = not frame.bossPickerOpen
    RWC:ShowRunSummary(frame.summary)
  end)

  frame.currentBossText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.currentBossText:SetPoint("LEFT", frame.bossToggle, "RIGHT", 10, 0)
  frame.currentBossText:SetWidth(760)
  frame.currentBossText:SetJustifyH("LEFT")
  frame.currentBossText:SetText("")

  frame.bossButtons = {}
  frame.allBossButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.allBossButton:SetSize(72, 22)
  frame.allBossButton:SetPoint("TOPLEFT", 18, -112)
  frame.allBossButton:SetText("全副本")
  frame.allBossButton:Hide()
  frame.allBossButton:SetScript("OnClick", function()
    frame.expandedBossIndex = nil
    RWC:ShowRunSummary(frame.summary)
  end)

  for i = 1, 16 do
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(160, 22)
    local col = (i - 1) % 5
    local row = math.floor((i - 1) / 5)
    button:SetPoint("TOPLEFT", 96 + col * 164, -112 - row * 24)
    button:Hide()
    button:SetScript("OnEnter", function(self)
      if not self.tooltipText then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.tooltipText, 1, 1, 1)
      GameTooltip:AddLine("左键展开这个 Boss 的单场记录", nil, nil, nil, true)
      GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("OnClick", function(self)
      frame.expandedBossIndex = self.bossIndex
      RWC:ShowRunSummary(frame.summary)
    end)
    frame.bossButtons[i] = button
  end

  frame.viewTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.viewTitle:SetPoint("TOPLEFT", 18, -118)
  frame.viewTitle:SetWidth(930)
  frame.viewTitle:SetJustifyH("LEFT")
  frame.viewTitle:SetText("")

  local columns = {
    { text = "玩家", x = 18, width = 110 },
    { text = "Boss", x = 130, width = 45 },
    { text = "均分", x = 180, width = 45 },
    { text = "最低", x = 230, width = 45 },
    { text = "伤害", x = 280, width = 70 },
    { text = "治疗", x = 355, width = 70 },
    { text = "承伤", x = 430, width = 70 },
    { text = "可规避", x = 505, width = 55 },
    { text = "打断", x = 565, width = 45 },
    { text = "驱散", x = 615, width = 45 },
    { text = "死亡", x = 665, width = 45 },
    { text = "主要异常", x = 720, width = 230 },
  }

  frame.columnTexts = {}
  for index, column in ipairs(columns) do
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", column.x, -146)
    text:SetWidth(column.width)
    text:SetJustifyH("LEFT")
    text:SetText(column.text)
    text.summaryX = column.x
    frame.columnTexts[index] = text
  end

  frame.summaryScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  frame.summaryScroll:SetPoint("TOPLEFT", 18, -172)
  frame.summaryScroll:SetPoint("BOTTOMRIGHT", -36, 44)

  frame.summaryScrollChild = CreateFrame("Frame", nil, frame.summaryScroll)
  frame.summaryScrollChild:SetSize(944, 25 * 29)
  frame.summaryScroll:SetScrollChild(frame.summaryScrollChild)

  frame.rows = {}
  for i = 1, 25 do
    local row = CreateFrame("Frame", nil, frame.summaryScrollChild)
    row:SetSize(944, 27)
    row:SetPoint("TOPLEFT", 0, -((i - 1) * 29))
    row:EnableMouse(true)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row:SetScript("OnEnter", function(self)
      if not self.tooltipText then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.tooltipTitle or "详情", 1, 1, 1)
      GameTooltip:AddLine(self.tooltipText, nil, nil, nil, true)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnMouseUp", function(self, button)
      if button == "LeftButton" and self.player then
        if self.bossMode then
          RWC:ShowPlayerDetail(self.player, self.fightName)
        else
          RWC:ShowRunPlayerDetail(self.player)
        end
      end
    end)

    row.fields = {}
    for key, column in ipairs(columns) do
      local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      text:SetPoint("LEFT", row, "LEFT", column.x - 18, 0)
      text:SetWidth(column.width)
      text:SetJustifyH("LEFT")
      text:SetWordWrap(false)
      row.fields[key] = text
    end

    frame.rows[i] = row
  end

  frame.showReport = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.showReport:SetSize(88, 24)
  frame.showReport:SetPoint("BOTTOMLEFT", 18, 12)
  frame.showReport:SetText("单场报告")
  frame.showReport:SetScript("OnClick", function()
    if RWC.lastReport then
      RWC:ShowReport(RWC.lastReport)
    else
      RWC.Print("还没有单场报告。")
    end
  end)

  frame.options = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.options:SetSize(70, 24)
  frame.options:SetPoint("LEFT", frame.showReport, "RIGHT", 8, 0)
  frame.options:SetText("设置")
  frame.options:SetScript("OnClick", function()
    RWC:ShowSettings()
  end)

  frame.clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.clear:SetSize(88, 24)
  frame.clear:SetPoint("LEFT", frame.options, "RIGHT", 8, 0)
  frame.clear:SetText("清除记录")
  frame.clear:SetScript("OnClick", function()
    RWC:ClearReports()
  end)

  frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.footer:SetPoint("BOTTOMLEFT", 468, 24)
  frame.footer:SetWidth(486)
  frame.footer:SetJustifyH("LEFT")
  frame.footer:SetText("")

  self.runSummaryFrame = frame
  return frame
end

function RWC:FillRunSummaryRows(frame, rows, bossMode, bossName)
  if frame.columnTexts then
    frame.columnTexts[2]:SetText(bossMode and "状态" or "Boss")
    frame.columnTexts[3]:SetText(bossMode and "分数" or "均分")
    frame.columnTexts[4]:SetText(bossMode and "-" or "最低")
  end

  for i, row in ipairs(frame.rows) do
    local player = rows and rows[i]
    if player then
      row:Show()
      row.player = player
      row.bossMode = bossMode
      row.fightName = bossName
      row.tooltipTitle = player.name
      row.tooltipText = bossMode and "左键打开该 Boss 的个人详情" or "左键打开这个玩家的整场副本详情；点上方 Boss 按钮查看单场详情。"
      row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0.08)
      local score = bossMode and (player.score or 100) or (player.avgScore or 100)
      if score <= 45 then
        row.bg:SetColorTexture(1, 0.15, 0.15, 0.18)
      elseif score <= 65 then
        row.bg:SetColorTexture(1, 0.55, 0.1, 0.14)
      elseif score <= 80 then
        row.bg:SetColorTexture(1, 0.9, 0.15, 0.1)
      end

      row.fields[1]:SetText(ClassColorText(player.name, player.class))
      row.fields[2]:SetText(bossMode and StatusText(player.score or 100) or tostring(player.bosses or 0))
      row.fields[3]:SetText(tostring(bossMode and (player.score or 0) or (player.avgScore or 0)))
      row.fields[4]:SetText(tostring(bossMode and "-" or (player.worstScore or 0)))
      row.fields[5]:SetText(FormatNumber(player.damage))
      row.fields[6]:SetText(FormatNumber(player.healing))
      row.fields[7]:SetText(FormatNumber(player.damageTaken))
      row.fields[8]:SetText(tostring(player.avoidableHits or 0))
      row.fields[9]:SetText(tostring(player.interrupts or 0))
      row.fields[10]:SetText(tostring(player.dispels or 0))
      row.fields[11]:SetText(tostring(player.deaths or 0))
      row.fields[12]:SetText(SummaryReasonText(player, bossMode))
    else
      row.player = nil
      row.bossMode = nil
      row.fightName = nil
      row.tooltipTitle = nil
      row.tooltipText = nil
      row:Hide()
    end
  end
end

function RWC:ShowRunSummary(summary)
  if not summary then
    self.Print("还没有副本总结。")
    return
  end

  local frame = self:CreateRunSummaryFrame()
  frame.summary = summary
  if frame.summaryScroll then
    frame.summaryScroll:SetVerticalScroll(0)
  end
  frame.subtitle:SetText(string.format(
    "%s · Boss %d 个 · 总战斗时长 %s · %s",
    summary.instanceName or "未知副本",
    #(summary.bossRows or {}),
    FormatDuration(summary.totalDuration or 0),
    summary.generatedAt or ""
  ))

  for i, button in ipairs(frame.bossButtons) do
    local boss = summary.bossRows and summary.bossRows[i]
    if boss then
      button.bossIndex = i
      button:SetText(string.format("%d.%s", i, tostring(boss.name or ("Boss" .. i))))
      button.tooltipText = boss.name
      if frame.bossPickerOpen then
        button:Show()
      else
        button:Hide()
      end
      button:SetEnabled(frame.expandedBossIndex ~= i)
    else
      button.bossIndex = nil
      button:Hide()
    end
  end
  frame.allBossButton:SetShown(frame.bossPickerOpen == true)
  frame.allBossButton:SetEnabled(frame.expandedBossIndex ~= nil)
  frame.bossToggle:SetText(frame.bossPickerOpen and "收起Boss列表" or "展开Boss列表")

  local expandedBoss = frame.expandedBossIndex and summary.bossRows and summary.bossRows[frame.expandedBossIndex]
  if expandedBoss and expandedBoss.report then
    local result = expandedBoss.won == true and "击杀" or (expandedBoss.won == false and "灭团" or "结束")
    frame.currentBossText:SetText(string.format("当前：%s(%s)", expandedBoss.name or "未知Boss", result))
    frame.viewTitle:SetText(string.format("展开：%s · %s · 时长 %s。点击玩家行查看该 Boss 个人详情。", expandedBoss.name or "未知Boss", result, FormatDuration(expandedBoss.duration or 0)))
    self:FillRunSummaryRows(frame, expandedBoss.report.rows, true, expandedBoss.name)
  else
    frame.expandedBossIndex = nil
    frame.currentBossText:SetText("当前：全副本汇总")
    frame.viewTitle:SetText("全副本汇总。点击上方 Boss 按钮展开单个 Boss 记录。")
    self:FillRunSummaryRows(frame, summary.rows, false)
  end

  if frame.bossPickerOpen then
    frame.viewTitle:ClearAllPoints()
    frame.viewTitle:SetPoint("TOPLEFT", 18, -184)
    for _, text in ipairs(frame.columnTexts or {}) do
      text:ClearAllPoints()
      text:SetPoint("TOPLEFT", text.summaryX or 18, -212)
    end
  else
    frame.viewTitle:ClearAllPoints()
    frame.viewTitle:SetPoint("TOPLEFT", 18, -118)
    for _, text in ipairs(frame.columnTexts or {}) do
      text:ClearAllPoints()
      text:SetPoint("TOPLEFT", text.summaryX or 18, -146)
    end
  end
  frame.summaryScroll:ClearAllPoints()
  if frame.bossPickerOpen then
    frame.summaryScroll:SetPoint("TOPLEFT", 18, -238)
  else
    frame.summaryScroll:SetPoint("TOPLEFT", 18, -172)
  end
  frame.summaryScroll:SetPoint("BOTTOMRIGHT", -36, 44)

  frame:Show()
  frame:Raise()
end

function RWC:ShowReport(report)
  local frame = self:CreateReportFrame()
  if frame.scroll then
    frame.scroll:SetVerticalScroll(0)
  end
  local resultText = report.won == true and "击杀" or (report.won == false and "灭团" or "结束")
  frame.subtitle:SetText(string.format("%s · %s · 时长 %s · %s", report.fightName, resultText, FormatDuration(report.duration), report.generatedAt))

  local settings = RaidWaterCheckDB and RaidWaterCheckDB.settings or self.defaults
  local dangerCount, reviewCount = 0, 0
  for _, player in ipairs(report.rows) do
    if player.score <= (settings.dangerScore or 45) then
      dangerCount = dangerCount + 1
    elseif player.score <= (settings.reviewScore or 65) then
      reviewCount = reviewCount + 1
    end
  end
  if report.wclMode then
    frame.header:SetText(string.format("高疑似 %d 人，需复盘 %d 人，WCL提示 %d 人。%s 仅作冲分参考。", dangerCount, reviewCount, report.wclWarningCount or 0, report.wclRuleName or "WCL规则"))
  else
    frame.header:SetText(string.format("高疑似 %d 人，需复盘 %d 人。分数越低越需要结合机制分工和日志确认。", dangerCount, reviewCount))
  end

  local maxRows = settings.maxRows or 25
  for i, row in ipairs(frame.rows) do
    local player = report.rows[i]
    if player and i <= maxRows then
      row:Show()
      row.fields[1]:SetText(ClassColorText(player.name, player.class))
      row.fields[2]:SetText(StatusText(player.score))
      row.fields[3]:SetText(tostring(player.score))
      row.fields[4]:SetText(FormatNumber(player.damage))
      row.fields[5]:SetText(FormatNumber(player.healing))
      row.fields[6]:SetText(FormatNumber(player.damageTaken))
      row.fields[7]:SetText(player.avoidableHits > 0 and tostring(player.avoidableHits) or "-")
      row.fields[8]:SetText(tostring(player.casts))
      row.fields[9]:SetText(tostring(player.interrupts))
      row.fields[10]:SetText(tostring(player.dispels))
      row.fields[11]:SetText(tostring(player.deaths))
      row.fields[12]:SetText(JoinReasons(player.reasons))
      row.player = player
      row.fightName = report.fightName
      row.tooltipTitle = player.name .. " · " .. player.score .. " 分"
      row.tooltipText = string.format(
        "伤害：%s\n治疗：%s\n承伤：%s\n可规避：%d 次，%s\n施法：%d\n打断：%d\n驱散：%d\n死亡：%d\n原因：%s\n\nWCL：%s\n\n左键打开个人详情",
        FormatNumber(player.damage),
        FormatNumber(player.healing),
        FormatNumber(player.damageTaken),
        player.avoidableHits,
        FormatNumber(player.avoidableDamage),
        player.casts,
        player.interrupts,
        player.dispels,
        player.deaths,
        JoinReasons(player.reasons),
        WclWarningText(player)
      )
      if player.score <= (settings.dangerScore or 45) then
        row.bg:SetColorTexture(1, 0.15, 0.15, 0.18)
      elseif player.score <= (settings.reviewScore or 65) then
        row.bg:SetColorTexture(1, 0.55, 0.1, 0.14)
      elseif player.score <= (settings.warningScore or 80) then
        row.bg:SetColorTexture(1, 0.9, 0.15, 0.1)
      else
        row.bg:SetColorTexture(0.2, 1, 0.45, 0.07)
      end
    else
      row.tooltipTitle = nil
      row.tooltipText = nil
      row.player = nil
      row.fightName = nil
      row:Hide()
    end
  end

  frame:Show()
  frame:Raise()
end

function RWC:CreatePlayerDetailFrame()
  if self.detailFrame then
    return self.detailFrame
  end

  local frame = CreateFrame("Frame", "RaidWaterCheckDetailFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(820, 700)
  frame:SetPoint("CENTER", 40, -40)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetFrameLevel(210)
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:Hide()

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  frame.title:SetPoint("TOPLEFT", 16, -8)
  frame.title:SetText("个人详情")

  frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.summary:SetPoint("TOPLEFT", 18, -38)
  frame.summary:SetWidth(760)
  frame.summary:SetJustifyH("LEFT")
  frame.summary:SetText("")

  frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  frame.scroll:SetPoint("TOPLEFT", 18, -104)
  frame.scroll:SetPoint("BOTTOMRIGHT", -36, 18)

  frame.scrollChild = CreateFrame("Frame", nil, frame.scroll)
  frame.scrollChild:SetSize(744, 960)
  frame.scroll:SetScrollChild(frame.scrollChild)

  local sections = {
    { key = "damage", title = "主要伤害技能", x = 12, y = -8 },
    { key = "healing", title = "主要治疗技能", x = 390, y = -8 },
    { key = "casts", title = "施法次数", x = 12, y = -168 },
    { key = "taken", title = "主要承伤来源", x = 390, y = -168 },
    { key = "avoidable", title = "可规避伤害", x = 12, y = -328 },
    { key = "deaths", title = "死亡回放", x = 390, y = -328 },
    { key = "wcl", title = "WCL冲分提示", x = 12, y = -548 },
  }

  frame.sections = {}
  frame.sectionTitles = {}
  for _, section in ipairs(sections) do
    local title = frame.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", section.x, section.y)
    title:SetText(section.title)
    frame.sectionTitles[section.key] = title

    local body = frame.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", section.x, section.y - 24)
    body:SetWidth(section.key == "deaths" and 340 or 320)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetText("")
    frame.sections[section.key] = body
  end

  self.detailFrame = frame
  return frame
end

function RWC:ShowPlayerDetail(player, fightName)
  if not player then
    return
  end

  local frame = self:CreatePlayerDetailFrame()
  if frame.scroll then
    frame.scroll:SetVerticalScroll(0)
  end
  frame.sectionTitles.damage:SetText("主要伤害技能")
  frame.sectionTitles.healing:SetText("主要治疗技能")
  frame.sectionTitles.casts:SetText("施法次数")
  frame.sectionTitles.taken:SetText("主要承伤来源")
  frame.sectionTitles.avoidable:SetText("可规避伤害")
  frame.sectionTitles.deaths:SetText("死亡回放")
  frame.sectionTitles.wcl:SetText("WCL冲分提示")
  frame.title:SetText(string.format("%s · %s · %d 分", ClassColorText(player.name, player.class), fightName or "单场报告", player.score or 0))
  frame.summary:SetText(string.format(
    "伤害 %s · 治疗 %s · 承伤 %s · 可规避 %d次/%s\n施法 %d · 打断 %d · 驱散 %d · 死亡 %d · 原因：%s",
    FormatNumber(player.damage),
    FormatNumber(player.healing),
    FormatNumber(player.damageTaken),
    player.avoidableHits,
    FormatNumber(player.avoidableDamage),
    player.casts,
    player.interrupts,
    player.dispels,
    player.deaths,
    JoinReasons(player.reasons)
  ))
  frame.sections.damage:SetText(TopEntries(player.damageBySpell, 5, "amount"))
  frame.sections.healing:SetText(TopEntries(player.healingBySpell, 5, "amount"))
  frame.sections.casts:SetText(TopEntries(player.spellCasts, 8, "count"))
  frame.sections.taken:SetText(TopEntries(player.takenBySpell, 5, "amount"))
  frame.sections.avoidable:SetText(TopEntries(player.avoidableBySpell, 5, "amount"))
  frame.sections.deaths:SetText(DeathReplayText(player.deathEvents, 2))
  frame.sections.wcl:SetText(WclWarningText(player))
  frame:Show()
  frame:Raise()
end

function RWC:ShowRunPlayerDetail(player)
  if not player then
    return
  end

  local frame = self:CreatePlayerDetailFrame()
  if frame.scroll then
    frame.scroll:SetVerticalScroll(0)
  end
  frame.sectionTitles.damage:SetText("副本输出汇总")
  frame.sectionTitles.healing:SetText("副本治疗汇总")
  frame.sectionTitles.casts:SetText("副本行为汇总")
  frame.sectionTitles.taken:SetText("副本承伤汇总")
  frame.sectionTitles.avoidable:SetText("副本机制汇总")
  frame.sectionTitles.deaths:SetText("副本死亡回放")
  frame.sectionTitles.wcl:SetText("副本复盘提示")
  frame.title:SetText(ClassColorText(player.name, player.class) .. " · 副本汇总")
  frame.summary:SetText(string.format(
    "Boss %d 个 · 均分 %d · 最低 %d · 总伤害 %s · 总治疗 %s · 总承伤 %s\n可规避 %d次/%s · 施法 %d · 打断 %d · 驱散 %d · 死亡 %d",
    player.bosses or 0,
    player.avgScore or 0,
    player.worstScore or 0,
    FormatNumber(player.damage),
    FormatNumber(player.healing),
    FormatNumber(player.damageTaken),
    player.avoidableHits or 0,
    FormatNumber(player.avoidableDamage),
    player.casts or 0,
    player.interrupts or 0,
    player.dispels or 0,
    player.deaths or 0
  ))
  frame.sections.damage:SetText(string.format("总伤害：%s\n%s", FormatNumber(player.damage), TopEntries(player.damageBySpell, 5, "amount")))
  frame.sections.healing:SetText(string.format("总治疗：%s\n%s", FormatNumber(player.healing), TopEntries(player.healingBySpell, 5, "amount")))
  frame.sections.casts:SetText(string.format("施法：%d\n打断：%d\n驱散/偷取：%d\n%s", player.casts or 0, player.interrupts or 0, player.dispels or 0, TopEntries(player.spellCasts, 6, "count")))
  frame.sections.taken:SetText(string.format("总承伤：%s\n%s", FormatNumber(player.damageTaken), TopEntries(player.takenBySpell, 5, "amount")))
  frame.sections.avoidable:SetText(string.format("可规避：%d 次\n可规避伤害：%s\n%s", player.avoidableHits or 0, FormatNumber(player.avoidableDamage), TopEntries(player.avoidableBySpell, 5, "amount")))
  frame.sections.deaths:SetText(DeathReplayText(player.deathEvents, 4))
  if frame.sections.wcl then
    frame.sections.wcl:SetText(WclWarningText(player) .. "\n\n主要异常：\n" .. TopReasonText(player.reasons))
  end
  frame:Show()
  frame:Raise()
end

function RWC:HideReport()
  if self.reportFrame then
    self.reportFrame:Hide()
  end
end

function RWC:AnnounceReport(report)
  if not report or not report.rows then
    self.Print("还没有可通报的报告。")
    return
  end

  local channel
  if IsInRaid() then
    channel = "RAID"
  elseif IsInGroup() then
    channel = "PARTY"
  else
    self.Print("不在队伍或团队中，无法通报到团队频道。")
    return
  end

  local settings = RaidWaterCheckDB and RaidWaterCheckDB.settings or self.defaults
  local limit = settings.announceScore or 65
  local names = {}
  for _, player in ipairs(report.rows) do
    if player.score <= limit and player.reasons and #player.reasons > 0 then
      names[#names + 1] = string.format("%s(%d)", player.name, player.score)
    end
    if #names >= 5 then
      break
    end
  end

  if #names == 0 then
    SendChatMessage("[RWC] 本场没有达到通报条件的异常记录。", channel)
  else
    SendChatMessage("[RWC] " .. report.fightName .. " 需复盘：" .. table.concat(names, "；"), channel)
  end
end
