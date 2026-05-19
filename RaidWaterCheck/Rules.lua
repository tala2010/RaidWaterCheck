local _, RWC = ...

local function Rules()
  RWC:EnsureDB()
  return RaidWaterCheckDB.rules
end

local function ParseIdAndName(text)
  local id, name = tostring(text or ""):match("^(%d+)%s*(.*)$")
  if not id then
    return nil, nil
  end
  id = tonumber(id)
  if name == "" then
    name = nil
  end
  return id, name
end

function RWC:IsAvoidableSpell(spellId)
  if not spellId then
    return false
  end
  return Rules().avoidableSpells[tostring(spellId)] ~= nil
end

function RWC:GetAvoidableSpellName(spellId, fallback)
  if not spellId then
    return fallback or "Unknown"
  end
  return Rules().avoidableSpells[tostring(spellId)] or fallback or ("Spell " .. tostring(spellId))
end

function RWC:AddAvoidableSpell(text)
  local id, name = ParseIdAndName(text)
  if not id then
    self.Print("格式：/rwc avoid add 技能ID 技能名，例如 /rwc avoid add 123456 地板火")
    return
  end

  Rules().avoidableSpells[tostring(id)] = name or ("Spell " .. tostring(id))
  self.Print("已加入可规避伤害：" .. tostring(id) .. " " .. Rules().avoidableSpells[tostring(id)])
end

function RWC:RemoveAvoidableSpell(text)
  local id = tonumber(tostring(text or ""):match("^(%d+)"))
  if not id then
    self.Print("格式：/rwc avoid del 技能ID")
    return
  end

  Rules().avoidableSpells[tostring(id)] = nil
  self.Print("已移除可规避伤害：" .. tostring(id))
end

function RWC:AddTrackedSpell(text)
  local id, rest = ParseIdAndName(text)
  if not id then
    self.Print("格式：/rwc track add 技能ID 技能名 [职业英文] [最低次数]")
    return
  end

  local name, class, minCasts = tostring(rest or ""):match("^(.-)%s+([A-Z]+)%s+(%d+)$")
  if not name then
    name = rest
  end
  if name == "" or not name then
    name = "Spell " .. tostring(id)
  end

  Rules().trackedSpells[tostring(id)] = {
    name = name,
    class = class,
    minCasts = tonumber(minCasts) or 1,
  }
  self.Print("已追踪关键技能：" .. tostring(id) .. " " .. name)
end

function RWC:RemoveTrackedSpell(text)
  local id = tonumber(tostring(text or ""):match("^(%d+)"))
  if not id then
    self.Print("格式：/rwc track del 技能ID")
    return
  end

  Rules().trackedSpells[tostring(id)] = nil
  self.Print("已移除关键技能：" .. tostring(id))
end

function RWC:GetTrackedRulesForPlayer(player)
  local out = {}
  for id, rule in pairs(Rules().trackedSpells) do
    if not rule.class or rule.class == player.class then
      out[#out + 1] = {
        id = tostring(id),
        name = rule.name or ("Spell " .. tostring(id)),
        minCasts = rule.minCasts or 1,
      }
    end
  end
  return out
end

local WCL_NAXX_EXCLUDED_TARGETS = {
  ["格罗布鲁斯"] = { "Fallout Slime", "辐射软泥", "软泥" },
  ["Grobbulus"] = { "Fallout Slime" },
  ["格拉斯"] = { "Zombie Chow", "僵尸" },
  ["Gluth"] = { "Zombie Chow", "僵尸" },
  ["肮脏的希尔盖"] = { "Eye Stalk", "眼柄", "Plague Beast", "瘟疫兽" },
  ["Heigan"] = { "Eye Stalk", "Plague Beast" },
  ["瘟疫使者诺斯"] = { "Plagued Champion", "Plagued Guardian", "Plagued Warrior", "瘟疫勇士", "瘟疫卫士", "瘟疫战士" },
  ["Noth"] = { "Plagued Champion", "Plagued Guardian", "Plagued Warrior" },
  ["阿努布雷坎"] = { "Crypt Guard", "Corpse Scarab", "地穴卫士", "尸甲虫" },
  ["Anub'Rekhan"] = { "Crypt Guard", "Corpse Scarab" },
  ["黑女巫法琳娜"] = { "Naxxramas Follower", "Naxxramas Worshipper", "纳克萨玛斯追随者", "纳克萨玛斯膜拜者" },
  ["Faerlina"] = { "Naxxramas Follower", "Naxxramas Worshipper" },
  ["迈克斯纳"] = { "Maexxna Spiderling", "迈克斯纳的小蜘蛛", "小蜘蛛" },
  ["Maexxna"] = { "Maexxna Spiderling" },
  ["教官拉苏维奥斯"] = { "Deathknight Understudy", "死亡骑士学员" },
  ["Razuvious"] = { "Deathknight Understudy" },
  ["收割者戈提克"] = { "Spectral", "Unrelenting", "鬼灵", "无情" },
  ["Gothik"] = { "Spectral", "Unrelenting" },
  ["克尔苏加德"] = { "Soldier of the Frozen Wastes", "Unstoppable Abomination", "Soul Weaver", "Guardian of Icecrown", "冰冠卫士", "冰冻废土的士兵", "不可阻挡的憎恶", "灵魂编织者" },
  ["Kel'Thuzad"] = { "Soldier of the Frozen Wastes", "Unstoppable Abomination", "Soul Weaver", "Guardian of Icecrown" },
}

local WCL_NAXX_AURA_WARNINGS = {
  [23060] = { text = "WCL冲分提示：Battle Squawk/鸡叫类加速 Buff 可能影响排名有效性" },
  [29534] = { text = "WCL冲分提示：Silithyst/希利苏斯搬沙 Buff 可能影响排名有效性" },
  [29232] = { text = "WCL冲分提示：Fungal Bloom 在非洛欧塞布/萨菲隆战斗中可能导致排名无效", allowed = { "洛欧塞布", "Loatheb", "萨菲隆", "Sapphiron" } },
  [28059] = { text = "WCL冲分提示：塔迪乌斯极性 Buff 在非塔迪乌斯/萨菲隆战斗中可能导致排名无效", allowed = { "塔迪乌斯", "Thaddius", "萨菲隆", "Sapphiron" } },
  [28084] = { text = "WCL冲分提示：塔迪乌斯极性 Buff 在非塔迪乌斯/萨菲隆战斗中可能导致排名无效", allowed = { "塔迪乌斯", "Thaddius", "萨菲隆", "Sapphiron" } },
}

local function ContainsAny(text, needles)
  if not text or not needles then
    return false
  end
  text = tostring(text)
  for _, needle in ipairs(needles) do
    if text:find(needle, 1, true) then
      return true
    end
  end
  return false
end

local function IsAllowedFight(fightName, allowed)
  if not allowed then
    return false
  end
  return ContainsAny(fightName or "", allowed)
end

function RWC:IsWclNaxxEnabled()
  local settings = RaidWaterCheckDB and RaidWaterCheckDB.settings or self.defaults
  return settings.enableWclNaxxMode == true
end

function RWC:GetWclRuleName(fightName)
  if not self:IsWclNaxxEnabled() then
    return nil
  end
  if not fightName or fightName == "" then
    return "NAXX/WCL冲分参考"
  end
  for bossName in pairs(WCL_NAXX_EXCLUDED_TARGETS) do
    if tostring(fightName):find(bossName, 1, true) then
      return "NAXX/WCL冲分参考"
    end
  end
  return "NAXX/WCL冲分参考"
end

function RWC:IsWclExcludedDamageTarget(fightName, destName)
  if not self:IsWclNaxxEnabled() or not fightName or not destName then
    return false
  end

  for bossName, targets in pairs(WCL_NAXX_EXCLUDED_TARGETS) do
    if tostring(fightName):find(bossName, 1, true) then
      return ContainsAny(destName, targets)
    end
  end
  return false
end

function RWC:AddWclWarning(player, text)
  if not player or not text or text == "" then
    return
  end
  player.wclWarnings = player.wclWarnings or {}
  for _, existing in ipairs(player.wclWarnings) do
    if existing == text then
      return
    end
  end
  player.wclWarnings[#player.wclWarnings + 1] = text
end

function RWC:RecordWclAuraWarning(player, subevent, info)
  if not self:IsWclNaxxEnabled() or not player then
    return
  end
  if subevent ~= "SPELL_AURA_APPLIED" and subevent ~= "SPELL_AURA_REFRESH" then
    return
  end

  local spellId = info and info[12]
  local warning = WCL_NAXX_AURA_WARNINGS[spellId]
  if warning and not IsAllowedFight(self.combat and self.combat.name, warning.allowed) then
    self:AddWclWarning(player, warning.text)
  end
end

function RWC:PrintRules()
  local rules = Rules()
  local count = 0
  for id, name in pairs(rules.avoidableSpells) do
    count = count + 1
    self.Print("可规避：" .. id .. " " .. tostring(name))
  end

  if count == 0 then
    self.Print("还没有可规避技能。用 /rwc avoid add 技能ID 技能名 添加。")
  end

  count = 0
  for id, rule in pairs(rules.trackedSpells) do
    count = count + 1
    self.Print("关键技能：" .. id .. " " .. tostring(rule.name) .. " " .. tostring(rule.class or "ALL") .. " x" .. tostring(rule.minCasts or 1))
  end

  if count == 0 then
    self.Print("还没有关键技能规则。用 /rwc track add 技能ID 技能名 [职业英文] [最低次数] 添加。")
  end
end
