local _, RWC = ...

local DAMAGE_EVENTS = {
  SWING_DAMAGE = true,
  RANGE_DAMAGE = true,
  SPELL_DAMAGE = true,
  SPELL_PERIODIC_DAMAGE = true,
  SPELL_BUILDING_DAMAGE = true,
  ENVIRONMENTAL_DAMAGE = true,
}

local HEAL_EVENTS = {
  SPELL_HEAL = true,
  SPELL_PERIODIC_HEAL = true,
}

local AURA_EVENTS = {
  SPELL_AURA_APPLIED = true,
  SPELL_AURA_REFRESH = true,
  SPELL_AURA_REMOVED = true,
}

local TAKEN_EVENTS = DAMAGE_EVENTS

local function ValueAt(info, index)
  local value = info[index]
  if type(value) == "number" then
    return value
  end
  return 0
end

local function DamageAmount(subevent, info)
  if subevent == "SWING_DAMAGE" then
    return ValueAt(info, 12)
  end
  if subevent == "ENVIRONMENTAL_DAMAGE" then
    return ValueAt(info, 13)
  end
  return ValueAt(info, 15)
end

local function HealAmount(info)
  local amount = ValueAt(info, 15)
  local overheal = ValueAt(info, 16)
  return math.max(0, amount - overheal)
end

local function SpellInfo(subevent, info)
  if subevent == "SWING_DAMAGE" then
    return 6603, "近战"
  end
  if subevent == "ENVIRONMENTAL_DAMAGE" then
    return nil, tostring(info[12] or "环境伤害")
  end
  return info[12], info[13]
end

local function SourceInfo(info)
  local name = info[5]
  if name and name ~= "" then
    return Ambiguate(name, "short")
  end
  return "未知来源"
end

local function AddMapAmount(map, key, amount, label)
  if not key then
    return
  end
  key = tostring(key)
  map[key] = map[key] or { id = key, name = label or key, amount = 0, count = 0 }
  map[key].amount = map[key].amount + (amount or 0)
  map[key].count = map[key].count + 1
  if label and label ~= "" then
    map[key].name = label
  end
end

function RWC:NewPlayer(guid, name)
  return {
    guid = guid,
    name = name or "Unknown",
    class = nil,
    role = "NONE",
    inGroup = false,
    damage = 0,
    healing = 0,
    casts = 0,
    interrupts = 0,
    dispels = 0,
    deaths = 0,
    damageTaken = 0,
    avoidableDamage = 0,
    avoidableHits = 0,
    auraEvents = 0,
    actions = 0,
    spellCasts = {},
    damageBySpell = {},
    healingBySpell = {},
    takenBySpell = {},
    avoidableBySpell = {},
    missingTracked = {},
    wclExcludedDamage = 0,
    wclExcludedHits = 0,
    wclWarnings = {},
    recentDamage = {},
    deathEvents = {},
    firstActionAt = nil,
    lastActionAt = nil,
    idleSeconds = 0,
    score = 100,
    reasons = {},
  }
end

function RWC:MarkRosterPresent(timestamp)
  for _, player in pairs(self.players) do
    if player.inGroup then
      player.firstActionAt = timestamp
      player.lastActionAt = timestamp
    end
  end
end

function RWC:AddAction(player, timestamp)
  local settings = RaidWaterCheckDB and RaidWaterCheckDB.settings or self.defaults
  local grace = settings.idleGraceSeconds or self.defaults.idleGraceSeconds

  if not player.firstActionAt then
    player.firstActionAt = timestamp
  end

  if player.lastActionAt then
    local gap = timestamp - player.lastActionAt
    if gap > grace then
      player.idleSeconds = player.idleSeconds + gap - grace
    end
  end

  player.lastActionAt = timestamp
  player.actions = player.actions + 1
end

function RWC:CloseIdleWindows(timestamp)
  local settings = RaidWaterCheckDB and RaidWaterCheckDB.settings or self.defaults
  local grace = settings.idleGraceSeconds or self.defaults.idleGraceSeconds
  for _, player in pairs(self.players) do
    if player.inGroup and player.lastActionAt then
      local gap = timestamp - player.lastActionAt
      if gap > grace then
        player.idleSeconds = player.idleSeconds + gap - grace
      end
    end
  end
end

function RWC:RecordSourceEvent(player, subevent, info, timestamp)
  local spellId, spellName = SpellInfo(subevent, info)

  if DAMAGE_EVENTS[subevent] then
    local amount = DamageAmount(subevent, info)
    player.damage = player.damage + amount
    AddMapAmount(player.damageBySpell, spellId, amount, spellName)
    if self:IsWclExcludedDamageTarget(self.combat.name, info[9]) then
      player.wclExcludedDamage = player.wclExcludedDamage + amount
      player.wclExcludedHits = player.wclExcludedHits + 1
      self:AddWclWarning(player, "WCL可能排除目标伤害：" .. tostring(info[9] or "未知目标"))
    end
    self:AddAction(player, timestamp)
  elseif HEAL_EVENTS[subevent] then
    local amount = HealAmount(info)
    player.healing = player.healing + amount
    AddMapAmount(player.healingBySpell, spellId, amount, spellName)
    self:AddAction(player, timestamp)
  elseif subevent == "SPELL_CAST_SUCCESS" then
    player.casts = player.casts + 1
    AddMapAmount(player.spellCasts, spellId, 0, spellName)
    self:AddAction(player, timestamp)
  elseif subevent == "SPELL_INTERRUPT" then
    player.interrupts = player.interrupts + 1
    self:AddAction(player, timestamp)
  elseif subevent == "SPELL_DISPEL" or subevent == "SPELL_STOLEN" then
    player.dispels = player.dispels + 1
    self:AddAction(player, timestamp)
  elseif AURA_EVENTS[subevent] then
    player.auraEvents = player.auraEvents + 1
  end
end

function RWC:RecordDestEvent(player, subevent, info)
  if not TAKEN_EVENTS[subevent] then
    return
  end

  local amount = DamageAmount(subevent, info)
  local spellId, spellName = SpellInfo(subevent, info)
  local timestamp = GetTime()
  local sourceName = SourceInfo(info)
  local settings = RaidWaterCheckDB and RaidWaterCheckDB.settings or self.defaults
  local maxHits = settings.deathReplayMaxHits or 12
  local replaySeconds = settings.deathReplaySeconds or 8
  local avoidable = self:IsAvoidableSpell(spellId)

  player.damageTaken = player.damageTaken + amount
  AddMapAmount(player.takenBySpell, spellId, amount, spellName)

  player.recentDamage[#player.recentDamage + 1] = {
    time = timestamp,
    source = sourceName,
    spellId = spellId,
    spellName = spellName or "未知技能",
    amount = amount,
    avoidable = avoidable,
  }

  local keepAfter = timestamp - replaySeconds
  while #player.recentDamage > 0 and (player.recentDamage[1].time < keepAfter or #player.recentDamage > maxHits) do
    table.remove(player.recentDamage, 1)
  end

  if avoidable then
    player.avoidableDamage = player.avoidableDamage + amount
    player.avoidableHits = player.avoidableHits + 1
    AddMapAmount(player.avoidableBySpell, spellId, amount, self:GetAvoidableSpellName(spellId, spellName))
  end
end

function RWC:RecordDeathSnapshot(player, timestamp)
  local settings = RaidWaterCheckDB and RaidWaterCheckDB.settings or self.defaults
  local replaySeconds = settings.deathReplaySeconds or 8
  local maxHits = settings.deathReplayDisplayHits or 5
  local since = timestamp - replaySeconds
  local hits = {}
  local killingBlow = nil
  local maxHit = nil
  local avoidableCount = 0

  for _, hit in ipairs(player.recentDamage or {}) do
    if hit.time >= since then
      local copy = {
        secondsBeforeDeath = math.max(0, timestamp - hit.time),
        source = hit.source,
        spellId = hit.spellId,
        spellName = hit.spellName,
        amount = hit.amount,
        avoidable = hit.avoidable,
      }
      hits[#hits + 1] = copy
      killingBlow = copy
      if not maxHit or copy.amount > maxHit.amount then
        maxHit = copy
      end
      if copy.avoidable then
        avoidableCount = avoidableCount + 1
      end
    end
  end

  while #hits > maxHits do
    table.remove(hits, 1)
  end

  player.deathEvents[#player.deathEvents + 1] = {
    time = timestamp,
    hits = hits,
    killingBlow = killingBlow,
    maxHit = maxHit,
    avoidableCount = avoidableCount,
  }
end

local function AddReason(player, text)
  table.insert(player.reasons, text)
end

local function ScorePlayer(player, duration, totalDamage, totalHealing, totalTaken)
  local settings = RaidWaterCheckDB and RaidWaterCheckDB.settings or RWC.defaults
  player.score = 100
  player.reasons = {}

  local minutes = math.max(duration / 60, 0.1)
  local idlePct = duration > 0 and player.idleSeconds / duration or 0
  local castsPerMinute = player.casts / minutes
  local contribution = 0
  local idleLight = (settings.idleLightPct or 12) / 100
  local idleMedium = (settings.idleMediumPct or 20) / 100
  local idleHeavy = (settings.idleHeavyPct or 35) / 100
  local castLight = settings.castLightPerMinute or 10
  local castHeavy = settings.castHeavyPerMinute or 6
  local lowContribution = (settings.lowContributionPct or 4) / 100
  local veryLowContribution = (settings.veryLowContributionPct or 2.5) / 100
  local highTaken = (settings.highTakenPct or 12) / 100

  idleMedium = math.max(idleMedium, idleLight)
  idleHeavy = math.max(idleHeavy, idleMedium)
  castLight = math.max(castLight, castHeavy)
  lowContribution = math.max(lowContribution, veryLowContribution)

  if totalDamage > 0 then
    contribution = math.max(contribution, player.damage / totalDamage)
  end
  if totalHealing > 0 then
    contribution = math.max(contribution, player.healing / totalHealing)
  end

  if settings.enableDeathPenalty and player.deaths > 0 then
    local penalty = math.min(35, player.deaths * 18)
    player.score = player.score - penalty
    AddReason(player, "死亡 " .. player.deaths .. " 次")
  end

  if idlePct >= idleHeavy then
    player.score = player.score - 35
    AddReason(player, string.format("无动作 %.0f%%", idlePct * 100))
  elseif idlePct >= idleMedium then
    player.score = player.score - 22
    AddReason(player, string.format("无动作 %.0f%%", idlePct * 100))
  elseif idlePct >= idleLight then
    player.score = player.score - 12
    AddReason(player, string.format("无动作 %.0f%%", idlePct * 100))
  end

  if settings.enableCastPenalty and player.damage + player.healing > 0 then
    if castsPerMinute < castHeavy then
      player.score = player.score - 15
      AddReason(player, string.format("施法频率偏低 %.1f/分钟", castsPerMinute))
    elseif castsPerMinute < castLight then
      player.score = player.score - 8
      AddReason(player, string.format("施法频率略低 %.1f/分钟", castsPerMinute))
    end
  end

  if settings.enableContributionPenalty and contribution > 0 and duration >= 60 then
    if contribution < veryLowContribution then
      player.score = player.score - 18
      AddReason(player, string.format("贡献占比低于 %.1f%%", settings.veryLowContributionPct or 2.5))
    elseif contribution < lowContribution then
      player.score = player.score - 9
      AddReason(player, string.format("贡献占比低于 %.1f%%", settings.lowContributionPct or 4))
    end
  end

  if settings.enableTakenPenalty and totalTaken > 0 then
    local takenPct = player.damageTaken / totalTaken
    if takenPct >= highTaken then
      player.score = player.score - 10
      AddReason(player, string.format("承伤占比 %.1f%%", takenPct * 100))
    end
    player.takenPct = takenPct
  else
    player.takenPct = 0
  end

  if settings.enableAvoidablePenalty and player.avoidableHits > 0 then
    local penalty = math.min(30, player.avoidableHits * (settings.avoidableHitPenalty or 8))
    player.score = player.score - penalty
    AddReason(player, string.format("可规避伤害 %d 次", player.avoidableHits))
  end

  player.missingTracked = {}
  if settings.enableTrackedPenalty then
    local tracked = RWC:GetTrackedRulesForPlayer(player)
    for _, rule in ipairs(tracked) do
      local cast = player.spellCasts[tostring(rule.id)]
      local count = cast and cast.count or 0
      if count < rule.minCasts then
        player.score = player.score - (settings.missingTrackedPenalty or 10)
        player.missingTracked[#player.missingTracked + 1] = rule.name
        AddReason(player, "未使用关键技能 " .. rule.name)
      end
    end
  end

  if player.actions == 0 then
    player.score = 0
    AddReason(player, "整场没有可记录动作")
  end

  player.score = math.max(0, math.min(100, math.floor(player.score + 0.5)))
  player.idlePct = idlePct
  player.castsPerMinute = castsPerMinute
  player.contribution = contribution
end

function RWC:BuildReport(duration, won)
  local totalDamage, totalHealing, totalTaken = 0, 0, 0
  local rows = {}
  local wclWarningCount = 0

  for _, player in pairs(self.players) do
    if player.inGroup then
      totalDamage = totalDamage + player.damage
      totalHealing = totalHealing + player.healing
      totalTaken = totalTaken + player.damageTaken
    end
  end

  for _, player in pairs(self.players) do
    if player.inGroup then
      ScorePlayer(player, duration, totalDamage, totalHealing, totalTaken)
      if player.wclExcludedDamage and player.wclExcludedDamage > 0 then
        wclWarningCount = wclWarningCount + 1
      elseif player.wclWarnings and #player.wclWarnings > 0 then
        wclWarningCount = wclWarningCount + 1
      end
      table.insert(rows, player)
    end
  end

  table.sort(rows, function(a, b)
    if a.score == b.score then
      return a.name < b.name
    end
    return a.score < b.score
  end)

  return {
    fightName = self.combat.name,
    source = self.combat.source,
    duration = duration,
    won = won,
    rows = rows,
    totalDamage = totalDamage,
    totalHealing = totalHealing,
    totalTaken = totalTaken,
    wclMode = self:IsWclNaxxEnabled(),
    wclWarningCount = wclWarningCount,
    wclRuleName = self:GetWclRuleName(self.combat.name),
    generatedAt = date("%Y-%m-%d %H:%M:%S"),
  }
end
