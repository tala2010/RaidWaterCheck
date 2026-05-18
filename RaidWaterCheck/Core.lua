local ADDON_NAME, RWC = ...

RWC.addonName = ADDON_NAME
RWC.version = "0.1.0"
RWC.defaults = {
  idleGraceSeconds = 6,
  minFightSeconds = 20,
  autoReport = true,
  recordTrash = false,
  maxRows = 12,
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
  enableTakenPenalty = true,
  enableAvoidablePenalty = true,
  enableTrackedPenalty = true,
  highTakenPct = 12,
  avoidableHitPenalty = 8,
  missingTrackedPenalty = 10,
  announceScore = 65,
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

local frame = CreateFrame("Frame")
RWC.frame = frame

local EVENTS = {
  "ADDON_LOADED",
  "PLAYER_LOGIN",
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
end

local function Settings()
  RWC:EnsureDB()
  return RaidWaterCheckDB.settings
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

  if RaidWaterCheckDB.settings.autoReport then
    self:ShowReport(report)
  else
    Print("战斗报告已生成，输入 /rwc show 查看。")
  end
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
  end

  if subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
    if dest and (dest.inGroup or self:IsKnownGroupGUID(destGUID)) then
      dest.deaths = dest.deaths + 1
      dest.lastActionAt = timestamp
    end
  end
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
    RWC.lastReport = nil
    RWC:ResetFight()
    Print("已重置当前统计。")
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
  elseif message == "announce" then
    RWC:AnnounceReport(RWC.lastReport)
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
    Print("/rwc show 报告；/rwc options 设置；/rwc announce 通报；/rwc trash 小怪记录；/rwc rules 规则。")
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
