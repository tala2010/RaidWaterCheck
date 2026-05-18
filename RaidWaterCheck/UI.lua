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

  frame.rows = {}
  for i = 1, 12 do
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(944, 27)
    row:SetPoint("TOPLEFT", 18, -102 - (i * 29))
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
        RWC:ShowPlayerDetail(self.player)
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
  frame.announce:SetSize(100, 24)
  frame.announce:SetPoint("BOTTOMLEFT", 18, 12)
  frame.announce:SetText("通报异常")
  frame.announce:SetScript("OnClick", function()
    RWC:AnnounceReport(RWC.lastReport)
  end)

  frame.options = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.options:SetSize(80, 24)
  frame.options:SetPoint("LEFT", frame.announce, "RIGHT", 8, 0)
  frame.options:SetText("设置")
  frame.options:SetScript("OnClick", function()
    RWC:ShowSettings()
  end)

  frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.footer:SetPoint("BOTTOMLEFT", 214, 18)
  frame.footer:SetText("/rwc show 查看；/rwc options 设置；/rwc announce 通报。")

  self.reportFrame = frame
  return frame
end

function RWC:ShowReport(report)
  local frame = self:CreateReportFrame()
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
  frame.header:SetText(string.format("高疑似 %d 人，需复盘 %d 人。分数越低越需要结合机制分工和日志确认。", dangerCount, reviewCount))

  local maxRows = settings.maxRows or 12
  for i, row in ipairs(frame.rows) do
    local player = report.rows[i]
    if player and i <= maxRows then
      row:Show()
      row.fields[1]:SetText(player.name)
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
      row.tooltipTitle = player.name .. " · " .. player.score .. " 分"
      row.tooltipText = string.format(
        "伤害：%s\n治疗：%s\n承伤：%s\n可规避：%d 次，%s\n施法：%d\n打断：%d\n驱散：%d\n死亡：%d\n原因：%s\n\n左键打开个人详情",
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
  frame:SetSize(640, 520)
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
  frame.summary:SetWidth(600)
  frame.summary:SetJustifyH("LEFT")
  frame.summary:SetText("")

  local sections = {
    { key = "damage", title = "主要伤害技能", x = 18, y = -90 },
    { key = "healing", title = "主要治疗技能", x = 330, y = -90 },
    { key = "casts", title = "施法次数", x = 18, y = -230 },
    { key = "taken", title = "主要承伤来源", x = 330, y = -230 },
    { key = "avoidable", title = "可规避伤害", x = 18, y = -370 },
  }

  frame.sections = {}
  for _, section in ipairs(sections) do
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", section.x, section.y)
    title:SetText(section.title)

    local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", section.x, section.y - 24)
    body:SetWidth(280)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetText("")
    frame.sections[section.key] = body
  end

  self.detailFrame = frame
  return frame
end

function RWC:ShowPlayerDetail(player)
  if not player then
    return
  end

  local frame = self:CreatePlayerDetailFrame()
  frame.title:SetText(player.name .. " · " .. player.score .. " 分")
  frame.summary:SetText(string.format(
    "伤害 %s · 治疗 %s · 承伤 %s · 可规避 %d 次/%s · 施法 %d · 打断 %d · 驱散 %d · 死亡 %d\n原因：%s",
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
