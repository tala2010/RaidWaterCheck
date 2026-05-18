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
