local ADDON_NAME, RWC = ...

RWC.addonName = ADDON_NAME
RWC.version = "1.0.0"
RWC.defaults = {
  idleGraceSeconds = 6,
  minFightSeconds = 20,
  autoReport = true,
  recordTrash = false,
  enableWclNaxxMode = false,
  maxRows = 25,
  warningScore = 80,
  reviewScore = 65,
  dangerScore = 45,
  idleLightPct = 12,
  idleMediumPct = 20,
  idleHeavyPct = 35,
  castLightPerMinute = 10,
  castHeavyPerMinute = 6,
  lowContributionPct = 4,
  veryLowContributionPct = 2.5,
  enableContributionPenalty = true,
  enableCastPenalty = true,
  enableDeathPenalty = true,
  enableTakenPenalty = true,
  enableAvoidablePenalty = true,
  enableTrackedPenalty = true,
  highTakenPct = 12,
  avoidableHitPenalty = 8,
  missingTrackedPenalty = 10,
  announceScore = 65,
  deathReplaySeconds = 8,
  deathReplayMaxHits = 12,
  deathReplayDisplayHits = 5,
  minimapAngle = 225,
  minimapVisible = true,
}
RWC.players = {}
RWC.combat = {
  active = false,
  startedAt = 0,
  endedAt = 0,
  name = "",
  source = "",
}
RWC.run = {
  active = false,
  instanceName = "",
  instanceType = "",
  startedAt = 0,
  endedAt = 0,
  reports = {},
}

local frame = CreateFrame("Frame")
RWC.frame = frame

local EVENTS = {
  "ADDON_LOADED",
  "PLAYER_LOGIN",
  "PLAYER_ENTERING_WORLD",
  "GROUP_ROSTER_UPDATE",
  "ENCOUNTER_START",
  "ENCOUNTER_END",
  "PLAYER_REGEN_DISABLED",
  "PLAYER_REGEN_ENABLED",
  "COMBAT_LOG_EVENT_UNFILTERED",
}

local function Print(message)
  DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[RWC]|r " .. tostring(message))
end

RWC.Print = Print

local function ApplyDefaults(target, defaults)
  for key, value in pairs(defaults) do
    if target[key] == nil then
      target[key] = value
    end
  end
end

function RWC:EnsureDB()
  RaidWaterCheckDB = RaidWaterCheckDB or {}
  RaidWaterCheckDB.settings = RaidWaterCheckDB.settings or {}
  RaidWaterCheckDB.rules = RaidWaterCheckDB.rules or {}
  RaidWaterCheckDB.rules.avoidableSpells = RaidWaterCheckDB.rules.avoidableSpells or {}
  RaidWaterCheckDB.rules.trackedSpells = RaidWaterCheckDB.rules.trackedSpells or {}
  ApplyDefaults(RaidWaterCheckDB.settings, self.defaults)

  RaidWaterCheckDB.settingsVersion = RaidWaterCheckDB.settingsVersion or 0

  if RaidWaterCheckDB.settingsVersion < 2 then
    RaidWaterCheckDB.settings.enableContributionPenalty = false
    RaidWaterCheckDB.settings.enableCastPenalty = false
    RaidWaterCheckDB.settings.enableDeathPenalty = false
    RaidWaterCheckDB.settings.enableTakenPenalty = false
    RaidWaterCheckDB.settings.enableAvoidablePenalty = false
    RaidWaterCheckDB.settings.enableTrackedPenalty = false
    RaidWaterCheckDB.settingsVersion = 2
  end

  if RaidWaterCheckDB.settingsVersion < 3 then
    if RaidWaterCheckDB.settings.maxRows == nil or RaidWaterCheckDB.settings.maxRows == 12 then
      RaidWaterCheckDB.settings.maxRows = 25
    end
    RaidWaterCheckDB.settingsVersion = 3
  end

  if RaidWaterCheckDB.settingsVersion < 4 then
    RaidWaterCheckDB.settings.enableWclNaxxMode = false
    RaidWaterCheckDB.settingsVersion = 4
  end

  if RaidWaterCheckDB.settingsVersion < 5 then
    RaidWaterCheckDB.settings.enableContributionPenalty = true
    RaidWaterCheckDB.settings.enableCastPenalty = true
    RaidWaterCheckDB.settings.enableDeathPenalty = true
    RaidWaterCheckDB.settings.enableTakenPenalty = true
    RaidWaterCheckDB.settings.enableAvoidablePenalty = true
    RaidWaterCheckDB.settings.enableTrackedPenalty = true
    RaidWaterCheckDB.settingsVersion = 5
  end
end

local function Settings()
  RWC:EnsureDB()
  return RaidWaterCheckDB.settings
end

local function CurrentInstanceInfo()
  local inInstance, instanceType = IsInInstance()
  local name = GetInstanceInfo()
  return inInstance, instanceType or "none", name or "未知副本"
end

local function IsPlayerControlled(flags)
  return flags and bit.band(flags, COMBATLOG_OBJECT_TYPE_PLAYER) ~= 0
end

function RWC:IsKnownGroupGUID(guid)
  return guid and self.players[guid] ~= nil
end

function RWC:GetOrCreatePlayer(guid, name, flags)
  if not guid or not IsPlayerControlled(flags) then
    return nil
  end

  if not self.players[guid] then
    self.players[guid] = self:NewPlayer(guid, name or "Unknown")
  end

  local player = self.players[guid]
  if name and name ~= "" then
    player.name = Ambiguate(name, "short")
  end
  return player
end

function RWC:RefreshRoster()
  for _, player in pairs(self.players) do
    player.inGroup = false
  end

  local function AddUnit(unit)
    local guid = UnitGUID(unit)
    if not guid then return end

    local name = UnitName(unit)
    local player = self.players[guid] or self:NewPlayer(guid, name or unit)
    player.name = name or player.name
    player.class = select(2, UnitClass(unit)) or player.class
    player.role = UnitGroupRolesAssigned(unit) or player.role
    player.inGroup = true
    self.players[guid] = player
  end

  AddUnit("player")

  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      AddUnit("raid" .. i)
    end
  elseif IsInGroup() then
    for i = 1, GetNumSubgroupMembers() do
      AddUnit("party" .. i)
    end
  end
end

function RWC:ResetFight()
  for guid, player in pairs(self.players) do
    local name, class, role, inGroup = player.name, player.class, player.role, player.inGroup
    self.players[guid] = self:NewPlayer(guid, name)
    self.players[guid].class = class
    self.players[guid].role = role
    self.players[guid].inGroup = inGroup
  end
end

function RWC:StartFight(name, source, forceReset)
  if self.combat.active and not forceReset then
    return
  end

  self:RefreshRoster()
  self:ResetFight()

  local now = GetTime()
  self.combat.active = true
  self.combat.startedAt = now
  self.combat.endedAt = 0
  self.combat.name = name or "Unknown fight"
  self.combat.source = source or "combat"

  if source == "encounter" then
    self:StartRunIfNeeded()
  end

  self:MarkRosterPresent(now)
  Print("开始记录：" .. self.combat.name)
end

function RWC:FinishFight(won)
  if not self.combat.active then
    return
  end

  local now = GetTime()
  self.combat.active = false
  self.combat.endedAt = now

  self:CloseIdleWindows(now)

  local duration = now - self.combat.startedAt
  if duration < (Settings().minFightSeconds or 20) then
    Print("战斗太短，已忽略。")
    return
  end

  local report = self:BuildReport(duration, won)
  self.lastReport = report

  if report.source == "encounter" then
    self:AddReportToRun(report)
  end

  if RaidWaterCheckDB.settings.autoReport then
    self:ShowReport(report)
  else
    Print("战斗报告已生成，输入 /rwc show 查看。")
  end
end

function RWC:StartRunIfNeeded()
  if self.run.active then
    return
  end

  local _, instanceType, instanceName = CurrentInstanceInfo()
  self.run.active = true
  self.run.instanceName = instanceName
  self.run.instanceType = instanceType
  self.run.startedAt = GetTime()
  self.run.endedAt = 0
  self.run.reports = {}
  Print("开始副本会话：" .. instanceName)
end

function RWC:AddReportToRun(report)
  if not self.run.active then
    self:StartRunIfNeeded()
  end

  local snapshot = {
    fightName = report.fightName,
    source = report.source,
    duration = report.duration,
    won = report.won,
    totalDamage = report.totalDamage or 0,
    totalHealing = report.totalHealing or 0,
    totalTaken = report.totalTaken or 0,
    wclMode = report.wclMode,
    wclWarningCount = report.wclWarningCount or 0,
    wclRuleName = report.wclRuleName,
    generatedAt = report.generatedAt,
    rows = {},
  }

  for _, player in ipairs(report.rows or {}) do
    snapshot.rows[#snapshot.rows + 1] = {
      name = player.name,
      class = player.class,
      role = player.role,
      score = player.score or 0,
      damage = player.damage or 0,
      healing = player.healing or 0,
      damageTaken = player.damageTaken or 0,
      avoidableHits = player.avoidableHits or 0,
      avoidableDamage = player.avoidableDamage or 0,
      casts = player.casts or 0,
      interrupts = player.interrupts or 0,
      dispels = player.dispels or 0,
      deaths = player.deaths or 0,
      wclExcludedDamage = player.wclExcludedDamage or 0,
      wclExcludedHits = player.wclExcludedHits or 0,
      wclWarnings = { unpack(player.wclWarnings or {}) },
      damageBySpell = player.damageBySpell or {},
      healingBySpell = player.healingBySpell or {},
      takenBySpell = player.takenBySpell or {},
      avoidableBySpell = player.avoidableBySpell or {},
      spellCasts = player.spellCasts or {},
      missingTracked = player.missingTracked or {},
      deathEvents = player.deathEvents or {},
      reasons = { unpack(player.reasons or {}) },
    }
  end

  self.run.reports[#self.run.reports + 1] = snapshot
  self.lastRunSummary = self:BuildRunSummary(self.run, false)
end

local function MergeMapAmount(target, source)
  for key, item in pairs(source or {}) do
    local id = tostring(key)
    target[id] = target[id] or {
      id = item.id or id,
      name = item.name or id,
      amount = 0,
      count = 0,
    }
    target[id].amount = target[id].amount + (item.amount or 0)
    target[id].count = target[id].count + (item.count or 0)
    if item.name and item.name ~= "" then
      target[id].name = item.name
    end
  end
end

function RWC:BuildRunSummary(run, finished)
  local players = {}
  local bossRows = {}
  local totalDuration = 0

  for _, report in ipairs(run.reports or {}) do
    totalDuration = totalDuration + (report.duration or 0)
    bossRows[#bossRows + 1] = {
      name = report.fightName,
      won = report.won,
      duration = report.duration or 0,
      report = report,
    }

    for _, row in ipairs(report.rows or {}) do
      local player = players[row.name]
      if not player then
        player = {
          name = row.name,
          class = row.class,
          role = row.role,
          bosses = 0,
          scoreSum = 0,
          worstScore = 100,
          damage = 0,
          healing = 0,
          damageTaken = 0,
          avoidableHits = 0,
          avoidableDamage = 0,
          casts = 0,
          interrupts = 0,
          dispels = 0,
          deaths = 0,
          wclExcludedDamage = 0,
          wclExcludedHits = 0,
          wclWarnings = {},
          deathEvents = {},
          damageBySpell = {},
          healingBySpell = {},
          takenBySpell = {},
          avoidableBySpell = {},
          spellCasts = {},
          reasons = {},
        }
        players[row.name] = player
      end

      player.bosses = player.bosses + 1
      player.scoreSum = player.scoreSum + (row.score or 0)
      player.worstScore = math.min(player.worstScore, row.score or 0)
      player.damage = player.damage + (row.damage or 0)
      player.healing = player.healing + (row.healing or 0)
      player.damageTaken = player.damageTaken + (row.damageTaken or 0)
      player.avoidableHits = player.avoidableHits + (row.avoidableHits or 0)
      player.avoidableDamage = player.avoidableDamage + (row.avoidableDamage or 0)
      player.casts = player.casts + (row.casts or 0)
      player.interrupts = player.interrupts + (row.interrupts or 0)
      player.dispels = player.dispels + (row.dispels or 0)
      player.deaths = player.deaths + (row.deaths or 0)
      player.wclExcludedDamage = player.wclExcludedDamage + (row.wclExcludedDamage or 0)
      player.wclExcludedHits = player.wclExcludedHits + (row.wclExcludedHits or 0)
      MergeMapAmount(player.damageBySpell, row.damageBySpell)
      MergeMapAmount(player.healingBySpell, row.healingBySpell)
      MergeMapAmount(player.takenBySpell, row.takenBySpell)
      MergeMapAmount(player.avoidableBySpell, row.avoidableBySpell)
      MergeMapAmount(player.spellCasts, row.spellCasts)
      for _, warning in ipairs(row.wclWarnings or {}) do
        player.wclWarnings[warning] = (player.wclWarnings[warning] or 0) + 1
      end
      for _, death in ipairs(row.deathEvents or {}) do
        player.deathEvents[#player.deathEvents + 1] = death
      end

      for _, reason in ipairs(row.reasons or {}) do
        player.reasons[reason] = (player.reasons[reason] or 0) + 1
      end
    end
  end

  local rows = {}
  for _, player in pairs(players) do
    player.avgScore = player.bosses > 0 and math.floor((player.scoreSum / player.bosses) + 0.5) or 0
    rows[#rows + 1] = player
  end

  table.sort(rows, function(a, b)
    if a.avgScore == b.avgScore then
      return a.worstScore < b.worstScore
    end
    return a.avgScore < b.avgScore
  end)

  return {
    instanceName = run.instanceName,
    instanceType = run.instanceType,
    startedAt = run.startedAt,
    endedAt = run.endedAt,
    totalDuration = totalDuration,
    finished = finished,
    bossRows = bossRows,
    rows = rows,
    generatedAt = date("%Y-%m-%d %H:%M:%S"),
  }
end

function RWC:FinishRun(reason, show)
  if not self.run.active and not self.lastRunSummary then
    self.Print("还没有副本总结。")
    return
  end

  if self.run.active then
    self.run.active = false
    self.run.endedAt = GetTime()
    self.lastRunSummary = self:BuildRunSummary(self.run, true)
    self.Print("副本会话结束：" .. tostring(reason or "手动结束"))
  end

  if show ~= false and self.lastRunSummary then
    self:ShowRunSummary(self.lastRunSummary)
  end
end

function RWC:ClearReports()
  self.lastReport = nil
  self.lastRunSummary = nil
  self.run.active = false
  self.run.endedAt = 0
  self.run.reports = {}
  self:ResetFight()
  if self.reportFrame then
    self.reportFrame:Hide()
  end
  if self.runSummaryFrame then
    self.runSummaryFrame:Hide()
  end
  if self.mainFrame then
    self.mainFrame:Hide()
  end
  Print("已清除报告和当前统计。")
end

function RWC:HandleCombatLog()
  if not self.combat.active then return end

  local info = { CombatLogGetCurrentEventInfo() }
  local timestamp = GetTime()
  local subevent = info[2]
  local sourceGUID = info[4]
  local sourceName = info[5]
  local sourceFlags = info[6]
  local destGUID = info[8]
  local destName = info[9]
  local destFlags = info[10]

  local source = self:GetOrCreatePlayer(sourceGUID, sourceName, sourceFlags)
  if source and (source.inGroup or self:IsKnownGroupGUID(sourceGUID)) then
    self:RecordSourceEvent(source, subevent, info, timestamp)
  end

  local dest = self:GetOrCreatePlayer(destGUID, destName, destFlags)
  if dest and (dest.inGroup or self:IsKnownGroupGUID(destGUID)) then
    self:RecordDestEvent(dest, subevent, info, timestamp)
    self:RecordWclAuraWarning(dest, subevent, info)
  end

  if subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
    if dest and (dest.inGroup or self:IsKnownGroupGUID(destGUID)) then
      dest.deaths = dest.deaths + 1
      dest.lastActionAt = timestamp
      self:RecordDeathSnapshot(dest, timestamp)
    end
  end
end

local function DemoSpell(id, name, amount, count)
  return { id = tostring(id), name = name, amount = amount or 0, count = count or 1 }
end

function RWC:CreateDemoPlayer(index, bossIndex)
  local names = {
    "地狱恶棍",
    "治疗很忙别催",
    "我真没划水",
    "冲榜小能手",
    "机制工具人",
    "站桩输出王",
    "断法机器人",
    "跑位慢半拍",
    "团长别看我",
    "可规避爱好者",
    "死亡回放样本",
    "超长名字测试玩家甲",
    "法夜不是我",
    "只会平砍",
    "满世界找门",
    "承伤异常样本",
    "关键技能忘交",
    "驱散小队长",
    "治疗刷榜中",
    "复盘重点对象",
    "眼神交流失败",
    "走位压线玩家",
    "火里洗澡",
    "冰箱忘带",
    "萨菲隆观察员",
  }

  local player = self:NewPlayer("DEMO-" .. tostring(bossIndex) .. "-" .. tostring(index), names[index] or ("演示玩家" .. index))
  local classes = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
  local score = 100 - ((index * 7 + bossIndex * 5) % 72)
  player.inGroup = true
  player.class = classes[((index - 1) % #classes) + 1]
  player.score = score
  player.damage = 180000 + index * 22000 + bossIndex * 35000
  player.healing = index % 5 == 0 and (90000 + index * 8000) or 0
  player.damageTaken = 25000 + ((index * 13000 + bossIndex * 9000) % 260000)
  player.avoidableHits = index % 4 == 0 and (1 + bossIndex) or 0
  player.avoidableDamage = player.avoidableHits * (18000 + index * 1200)
  player.casts = 35 + ((index * 3 + bossIndex) % 90)
  player.interrupts = index % 6 == 0 and (bossIndex + 1) or 0
  player.dispels = index % 7 == 0 and bossIndex or 0
  player.deaths = score < 55 and 1 or 0
  player.idlePct = ((index * 3) % 40) / 100
  player.castsPerMinute = player.casts / 4
  player.contribution = index / 500
  player.reasons = {}

  if score <= 80 then
    player.reasons[#player.reasons + 1] = string.format("无动作 %.0f%%", player.idlePct * 100)
  end
  if player.avoidableHits > 0 then
    player.reasons[#player.reasons + 1] = "可规避伤害 " .. tostring(player.avoidableHits) .. " 次"
  end
  if index % 9 == 0 then
    player.reasons[#player.reasons + 1] = "未使用关键技能 团队减伤/爆发技能"
  end
  if player.deaths > 0 then
    player.reasons[#player.reasons + 1] = "死亡 1 次"
  end
  if #player.reasons == 0 then
    player.reasons[#player.reasons + 1] = "无明显异常"
  end

  player.damageBySpell = {
    ["1"] = DemoSpell(1, "寒冰箭", player.damage * 0.42, 42),
    ["2"] = DemoSpell(2, "冰枪术", player.damage * 0.31, 36),
    ["3"] = DemoSpell(3, "暴风雪-用于测试较长技能名", player.damage * 0.16, 12),
  }
  player.healingBySpell = {
    ["4"] = DemoSpell(4, "快速治疗", player.healing, 18),
  }
  player.takenBySpell = {
    ["5"] = DemoSpell(5, "暗影裂隙", player.damageTaken * 0.45, 2),
    ["6"] = DemoSpell(6, "冰霜吐息", player.damageTaken * 0.32, 1),
  }
  player.avoidableBySpell = {
    ["7"] = DemoSpell(7, "可规避地面伤害", player.avoidableDamage, player.avoidableHits),
  }
  player.spellCasts = {
    ["8"] = DemoSpell(8, "主要输出技能", 0, player.casts),
    ["9"] = DemoSpell(9, "关键团队技能", 0, index % 9 == 0 and 0 or 1),
  }
  player.missingTracked = index % 9 == 0 and { "团队减伤/爆发技能" } or {}

  if player.deaths > 0 then
    player.deathEvents = {
      {
        time = GetTime(),
        killingBlow = { spellName = "冰霜吐息", amount = 46000 },
        maxHit = { spellName = "暗影裂隙", amount = 52000 },
        avoidableCount = player.avoidableHits,
        hits = {
          { secondsBeforeDeath = 7.4, source = "演示Boss", spellName = "暗影裂隙", amount = 52000, avoidable = true },
          { secondsBeforeDeath = 2.1, source = "演示Boss", spellName = "冰霜吐息", amount = 46000, avoidable = false },
        },
      },
    }
  end

  if index % 6 == 0 then
    player.wclExcludedDamage = 60000 + index * 3000
    player.wclExcludedHits = 3
    player.wclWarnings = { "WCL可能排除目标伤害：Zombie Chow" }
  end

  return player
end

function RWC:CreateDemoReport(bossName, bossIndex)
  local rows = {}
  local totalDamage, totalHealing, totalTaken = 0, 0, 0
  for i = 1, 25 do
    local player = self:CreateDemoPlayer(i, bossIndex)
    rows[#rows + 1] = player
    totalDamage = totalDamage + player.damage
    totalHealing = totalHealing + player.healing
    totalTaken = totalTaken + player.damageTaken
  end

  table.sort(rows, function(a, b)
    if a.score == b.score then
      return a.name < b.name
    end
    return a.score < b.score
  end)

  return {
    fightName = bossName,
    source = "demo",
    duration = 230 + bossIndex * 35,
    won = true,
    rows = rows,
    totalDamage = totalDamage,
    totalHealing = totalHealing,
    totalTaken = totalTaken,
    wclMode = true,
    wclWarningCount = 4,
    wclRuleName = "NAXX/WCL冲分参考",
    generatedAt = date("%Y-%m-%d %H:%M:%S"),
  }
end

function RWC:GenerateDemoData()
  local bosses = {
    "阿努布雷坎",
    "黑女巫法琳娜",
    "迈克斯纳",
    "瘟疫使者诺斯",
    "肮脏的希尔盖",
    "洛欧塞布",
    "教官拉苏维奥斯",
    "收割者戈提克",
    "天启四骑士",
    "帕奇维克",
    "格罗布鲁斯",
    "格拉斯",
    "塔迪乌斯",
    "萨菲隆",
    "克尔苏加德",
  }

  local run = {
    active = false,
    instanceName = "NAXX演示 - UI排版测试",
    instanceType = "raid",
    startedAt = GetTime() - 5400,
    endedAt = GetTime(),
    reports = {},
  }

  for i, bossName in ipairs(bosses) do
    run.reports[#run.reports + 1] = self:CreateDemoReport(bossName, i)
  end

  self.run = run
  self.lastReport = run.reports[#run.reports]
  self.lastRunSummary = self:BuildRunSummary(run, true)
  self:ShowRunSummary(self.lastRunSummary)
  Print("已生成演示记录：/rwc show 看单场，/rwc summary 看副本总结。")
end

local function SlashHandler(message)
  local rawMessage = message or ""
  message = rawMessage:lower()

  if message == "show" then
    if RWC.lastReport then
      RWC:ShowReport(RWC.lastReport)
    else
      Print("还没有报告。打一场团本或小怪战斗后再试。")
    end
  elseif message == "hide" then
    RWC:HideReport()
  elseif message == "reset" then
    RWC:ClearReports()
  elseif message == "auto" then
    local settings = Settings()
    settings.autoReport = not settings.autoReport
    Print("自动弹报告：" .. (settings.autoReport and "开" or "关"))
  elseif message == "trash" or message == "小怪" then
    local settings = Settings()
    settings.recordTrash = not settings.recordTrash
    Print("记录小怪/非Boss战：" .. (settings.recordTrash and "开" or "关"))
  elseif message == "options" or message == "config" or message == "settings" or message == "设置" then
    RWC:ShowSettings()
  elseif message == "menu" or message == "菜单" then
    RWC:ShowMainFrame()
  elseif message == "announce" then
    RWC:AnnounceReport(RWC.lastReport)
  elseif message == "summary" or message == "总览" then
    if RWC.lastRunSummary then
      RWC:ShowRunSummary(RWC.lastRunSummary)
    else
      Print("还没有副本总结。")
    end
  elseif message == "endrun" or message == "结束副本" then
    RWC:FinishRun("手动结束", true)
  elseif message == "demo" or message == "演示" then
    RWC:GenerateDemoData()
  elseif message == "rules" then
    RWC:PrintRules()
  elseif message == "minimap" then
    RWC:ToggleMinimapButton()
  elseif message:match("^avoid add ") then
    RWC:AddAvoidableSpell(rawMessage:match("^[Aa][Vv][Oo][Ii][Dd]%s+[Aa][Dd][Dd]%s+(.+)$"))
  elseif message:match("^avoid del ") then
    RWC:RemoveAvoidableSpell(rawMessage:match("^[Aa][Vv][Oo][Ii][Dd]%s+[Dd][Ee][Ll]%s+(.+)$"))
  elseif message:match("^track add ") then
    RWC:AddTrackedSpell(rawMessage:match("^[Tt][Rr][Aa][Cc][Kk]%s+[Aa][Dd][Dd]%s+(.+)$"))
  elseif message:match("^track del ") then
    RWC:RemoveTrackedSpell(rawMessage:match("^[Tt][Rr][Aa][Cc][Kk]%s+[Dd][Ee][Ll]%s+(.+)$"))
  elseif message == "start" then
    RWC:StartFight("Manual test", "manual")
  elseif message == "stop" then
    RWC:FinishFight(nil)
  else
    Print("/rwc menu 操作面板；/rwc show 单场；/rwc summary 副本总结；/rwc demo 演示数据；/rwc reset 清除。")
  end
end

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" and ... == ADDON_NAME then
    RWC:EnsureDB()
  elseif event == "PLAYER_LOGIN" then
    RWC:RefreshRoster()
    SLASH_RAIDWATERCHECK1 = "/rwc"
    SLASH_RAIDWATERCHECK2 = "/huashui"
    SlashCmdList.RAIDWATERCHECK = SlashHandler
    Print("已加载。输入 /rwc 查看命令。")
  elseif event == "PLAYER_ENTERING_WORLD" then
    local inInstance = CurrentInstanceInfo()
    if not inInstance and RWC.run.active and #(RWC.run.reports or {}) > 0 then
      RWC:FinishRun("离开副本", true)
    end
  elseif event == "GROUP_ROSTER_UPDATE" then
    RWC:RefreshRoster()
  elseif event == "ENCOUNTER_START" then
    local encounterID, encounterName = ...
    RWC:StartFight(encounterName or ("Encounter " .. tostring(encounterID)), "encounter", RWC.combat.source == "regen")
  elseif event == "ENCOUNTER_END" then
    local _, _, _, _, success = ...
    RWC:FinishFight(success == 1)
  elseif event == "PLAYER_REGEN_DISABLED" then
    if Settings().recordTrash and not RWC.combat.active then
      RWC:StartFight("Combat", "regen")
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if RWC.combat.active and RWC.combat.source == "regen" then
      RWC:FinishFight(nil)
    end
  elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
    RWC:HandleCombatLog()
  end
end)

for _, event in ipairs(EVENTS) do
  frame:RegisterEvent(event)
end
