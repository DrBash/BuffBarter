local ADDON, ns = ...
local L = ns.L

local function Print(msg) print("|cff33ccffBuffBarter|r: " .. tostring(msg)) end

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------
local DEFAULTS = {
  enabled = true,
  strangers = true,          -- also show buttons for players outside group/guild
  size = 28,
  offset = 0,
  expireMins = 5,
  campCountsAsBuffed = false,
  campIDs = {},              -- [spellID] = FAMILY, added via /barter camp
  bindKey = nil,             -- key for the smart button (mouseover, else target)
  debug = false,
  -- asking for a buff back
  askBack = false,           -- whisper after buffing someone (opt in)
  askOnlyIfMissing = true,   -- only ask for buffs you do not have
  askCampCounts = false,     -- your own camp buff counts as having it
  myLang = (GetLocale() == "deDE") and "de" or "en", -- default whisper language
  useLinks = true,
  oneClick = true,
  askMaxBelow = 5,
  askRemainMin = 15,         -- a buff with less time left counts as missing for asking
  showQueue = true,          -- stationary buff list
  queueLocked = false,
  queueCollapsed = false,    -- list folded down to its title bar
  queuePos = nil,
  nextKey = nil,
  plateIcons = true,         -- icons on nameplates (off: only the buff list)
  dispel = true,
  thank = true,              -- thank players who buff you
  msgToGroup = false,        -- automatic whispers (thanks, ask back) also to group members
  thankMode = "whisper",     -- "whisper" (own text) or "emote" (/thank)
  offInDungeon = false,      -- switch BuffBarter off in 5-player instances
  offInRaid = false,
  offInPvP = false,          -- battlegrounds and arenas
  offInCities = true,        -- capital cities are too crowded             -- show diseases, poisons, curses, magic you can remove
  acceptRequests = true,     -- popup when another BuffBarter user asks you for a buff
  minimap = true,            -- minimap icon
  minimapAngle = 210,             -- key that buffs the first player of the list           -- only ask players at most this many levels below you           -- icon click targets the player by name, casts, retargets
  pvpMode = "warn",          -- PvP flagged targets: "warn" or "block"           -- {buff} and {ask} as clickable spell links
  playerLang = {},           -- ["First-Last"] = "de"|"en", via /barter lang
  templates = {},            -- [lang][CLASS] = text, overrides defaults
}
local db

-- Capital cities: map IDs (Classic and modern client) plus zone names as a
-- fallback in case Forever uses its own map IDs.
local CITY_MAPS = {
  [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true,
  [84] = true, [85] = true, [87] = true, [88] = true, [89] = true, [90] = true,
}
local CITY_NAMES = {
  ["Stormwind City"] = true, ["Sturmwind"] = true, ["Ironforge"] = true, ["Eisenschmiede"] = true,
  ["Darnassus"] = true, ["Orgrimmar"] = true, ["Thunder Bluff"] = true, ["Donnerfels"] = true,
  ["Undercity"] = true, ["Unterstadt"] = true,
}
local function InCity()
  local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  if mapID and CITY_MAPS[mapID] then return true end
  local zone = GetRealZoneText and GetRealZoneText()
  return zone and CITY_NAMES[zone] or false
end
ns.InCity = InCity

-- City mode: no icons above heads, list folded until you unfold it.
local cityFolded = true      -- per visit; reset when you enter a city
local cityIcons = false      -- icons above heads switched on for this visit
local cityAsk = false        -- "ask" icons switched on for this visit
local wasInCity = false
local function CityMode()
  return db and db.offInCities and InCity() or false
end
local function CheckCityChange()
  local now = CityMode()
  if now and not wasInCity then cityFolded, cityIcons, cityAsk = true, false, false end
  wasInCity = now
end
-- Effective switches: in a city the per-visit choice counts.
local function IconsOn()
  if CityMode() then return cityIcons end
  return db.plateIcons
end
local function AskOn()
  if CityMode() then return cityAsk end
  return db.showRequest
end

-- Is BuffBarter switched on here? (master switch plus per-zone options)
local function Active()
  if not db or not db.enabled then return false end

  local inInstance, kind = IsInInstance()
  if not inInstance then return true end
  if kind == "party" and db.offInDungeon then return false end
  if kind == "raid" and db.offInRaid then return false end
  if (kind == "pvp" or kind == "arena") and db.offInPvP then return false end
  return true
end

local function InitDB()
  BuffBarterDB = BuffBarterDB or {}
  for k, v in pairs(DEFAULTS) do
    if BuffBarterDB[k] == nil then
      BuffBarterDB[k] = type(v) == "table" and {} or v
    end
  end
  db = BuffBarterDB
  if db.showRequest == nil then
    local _, myClass = UnitClass("player")
    db.showRequest = (myClass ~= "PALADIN") -- non-buffers ask others by default
  end
  if db.thankMode == "emote" and not db.thankModeChosen then db.thankMode = "whisper" end
  if not db.askBackChosen then db.askBack = false end
  if (db.schema or 1) < 2 then db.debug = false; db.offset = 0; db.schema = 2 end
end

------------------------------------------------------------------------
-- API compatibility (Forever runs the modern client, keep fallbacks)
------------------------------------------------------------------------
local function SpellInfo(spell)
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(spell)
    if i then return i.name, i.iconID, i.spellID end
    return
  end
  if GetSpellInfo then
    local name, _, icon, _, _, _, id = GetSpellInfo(spell)
    return name, icon, id
  end
end

local function IsKnown(id)
  if IsPlayerSpell and IsPlayerSpell(id) then return true end
  if IsSpellKnown and IsSpellKnown(id) then return true end
  if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id) then return true end
  return false
end

local function InRange(spell, unit)
  local f = (C_Spell and C_Spell.IsSpellInRange) or IsSpellInRange
  if not f then return true end
  local ok, r = pcall(f, spell, unit)
  if not ok then return true end
  return r == nil or r == true or r == 1
end

local function ForEachBuff(unit, fn)
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    for i = 1, 40 do
      local a = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
      if not a then break end
      fn(a.name, a.spellId, a.sourceUnit, a.expirationTime)
    end
  elseif UnitAura then
    for i = 1, 40 do
      local name, _, _, _, _, exp, src, _, _, id = UnitAura(unit, i, "HELPFUL")
      if not name then break end
      fn(name, id, src, exp)
    end
  end
end

------------------------------------------------------------------------
-- Spell data
------------------------------------------------------------------------
local known = {}        -- FAMILY -> { name, icon }
local idToFamily = {}   -- spellID -> FAMILY (all ranks + greater)
local nameToFamily = {} -- localized name -> FAMILY

local otherIdToFam, otherNameToFam = {}, {}

local function RankLevel(id)
  local lvl
  if C_Spell and C_Spell.GetSpellLevelLearned then lvl = C_Spell.GetSpellLevelLearned(id)
  elseif GetSpellLevelLearned then lvl = GetSpellLevelLearned(id) end
  if not lvl or lvl <= 0 then lvl = ns.RANK_LEVELS[id] end
  return lvl or 1
end

local function RankText(id)
  local sub
  if C_Spell and C_Spell.GetSpellSubtext then sub = C_Spell.GetSpellSubtext(id)
  elseif GetSpellSubtext then sub = GetSpellSubtext(id) end
  if sub and sub ~= "" then return sub end
end

local dispels = {}   -- my removal spells: { name, icon, types }

local function BuildDispels()
  wipe(dispels)
  local _, myClass = UnitClass("player")
  for _, d in ipairs(ns.DISPELS[myClass] or {}) do
    for _, id in ipairs(d.ids) do
      if IsKnown(id) then
        local n, icon = SpellInfo(id)
        if n then dispels[#dispels + 1] = { name = n, icon = icon, types = d.types } end
        break
      end
    end
  end
end

local function BuildSpells()
  BuildDispels()
  wipe(known); wipe(idToFamily); wipe(nameToFamily)
  wipe(otherIdToFam); wipe(otherNameToFam)
  for fam, d in pairs(ns.BUFFS) do
    for _, list in ipairs({ d.ids, d.greater or {} }) do
      for _, id in ipairs(list) do
        idToFamily[id] = fam
        local n = SpellInfo(id)
        if n then nameToFamily[n] = fam end
      end
    end
    -- known ranks, highest first; the first one is the default
    for _, id in ipairs(d.ids) do
      if IsKnown(id) then
        local n, icon = SpellInfo(id)
        if n then
          if not known[fam] then known[fam] = { name = n, icon = icon, id = id, ranks = {} } end
          table.insert(known[fam].ranks, { id = id, level = RankLevel(id), sub = RankText(id) })
        end
      end
    end
    -- fallback: look the spell up by its name (only returns spells you know)
    if not known[fam] then
      local baseName = SpellInfo(d.ids[#d.ids])
      if baseName then
        local n, icon, id = SpellInfo(baseName)
        if n and id then
          known[fam] = { name = n, icon = icon, id = id }
          idToFamily[id] = fam
        end
      end
    end
  end
end

-- Spell text for /cast: the highest rank the target may receive
-- (rank learn level minus 10 must not exceed the target's level).
local function CastName(fam, targetLevel)
  local k = known[fam]
  if not k then return end
  local ranks = k.ranks
  if not ranks or #ranks <= 1 or not targetLevel or targetLevel <= 0 then return k.name end
  for i, r in ipairs(ranks) do
    if r.level - 10 <= targetLevel then
      if i == 1 or not r.sub then return k.name end
      return k.name .. "(" .. r.sub .. ")"
    end
  end
  local low = ranks[#ranks]
  return low.sub and (k.name .. "(" .. low.sub .. ")") or k.name
end
ns.CastName = CastName

-- First debuff on the unit that one of my spells removes.
-- Returns { spell, debuff, debuffIcon, dtype } or nil.
local function FindDispel(unit)
  if not db.dispel or #dispels == 0 then return end
  local found
  pcall(function()
    for i = 1, 40 do
      local name, icon, dtype
      if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local a = C_UnitAuras.GetAuraDataByIndex(unit, i, "HARMFUL")
        if not a then break end
        name, icon, dtype = a.name, a.icon, a.dispelName
      else
        name, icon, _, dtype = UnitAura(unit, i, "HARMFUL")
        if not name then break end
      end
      if dtype and dtype ~= "" then
        for _, d in ipairs(dispels) do
          if d.types[dtype] then
            found = { spell = d.name, debuff = name, debuffIcon = icon, dtype = dtype }
            return
          end
        end
      end
    end
  end)
  return found
end

-- The modern client may not have DebuffTypeColor any more.
local DISPEL_RGB = {
  Magic   = { 0.2, 0.6, 1 },
  Curse   = { 0.6, 0, 1 },
  Disease = { 0.6, 0.4, 0 },
  Poison  = { 0, 0.6, 0 },
}
local function DispelColor(dtype)
  local c = DebuffTypeColor and DebuffTypeColor[dtype]
  if c then return c.r, c.g, c.b end
  c = DISPEL_RGB[dtype]
  if c then return c[1], c[2], c[3] end
  return 0.6, 0.2, 1
end

local function CampFamily(id)
  return id and (db.campIDs[id] or ns.CAMP_IDS[id])
end

------------------------------------------------------------------------
-- Decision logic
------------------------------------------------------------------------
-- Returns per family: { own = secondsLeft, other = true, camp = true }
-- plus the family of my own blessing on that unit (one per paladin).
local function ReadUnit(unit)
  local st, myFam, myLeft = {}, nil, nil
  local now = GetTime()
  ForEachBuff(unit, function(name, id, src, exp)
    local fam = (id and idToFamily[id]) or (name and nameToFamily[name])
    if fam then
      local s = st[fam] or {}; st[fam] = s
      if src and UnitIsUnit(src, "player") then
        local left = (exp and exp > 0) and (exp - now) or 3600
        s.own = left
        if ns.BUFFS[fam].blessing then myFam, myLeft = fam, left end
      else
        s.other = true
      end
      return
    end
    local cf = CampFamily(id)
    if cf then
      st[cf] = st[cf] or {}
      st[cf].camp = true
    end
  end)
  return st, myFam, myLeft
end

-- Returns FAMILY, STATE, myFam, myLeft or nil when nothing to do.
-- STATE: MISSING, CAMP, EXPIRING, SWAP
-- Priests, mages, druids: offer the first of your buffs the target lacks.
local function DecideGeneric(unit, order, class, role)
  local ok, st = pcall(ReadUnit, unit)
  if not ok then return end
  for _, fam in ipairs(order) do
    local w = ns.WANTS[fam]
    local wanted = known[fam]
      and not (w and w.notFor and w.notFor[class])
      and not (w and w.tankOnly and role ~= "TANK")
    if wanted then
      local s = st[fam]
      if s and s.own then
        if s.own <= db.expireMins * 60 then return fam, "EXPIRING", nil, s.own end
      elseif not (s and s.other) then
        local camp = s and s.camp
        if not (camp and db.campCountsAsBuffed) then
          return fam, camp and "CAMP" or "MISSING"
        end
      end
    end
  end
end

local function Decide(unit)
  local _, class = UnitClass(unit)
  local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
  local _, myClass = UnitClass("player")
  if ns.CLASS_ORDER[myClass] then
    return DecideGeneric(unit, ns.CLASS_ORDER[myClass], class, role)
  end
  local prio = (role == "TANK" and ns.PRIO.TANK) or ns.PRIO[class]
  if not prio then return end

  local ok, st, myFam, myLeft = pcall(ReadUnit, unit)
  if not ok then return end -- aura data not readable (restricted)

  local allowed = {}
  for _, f in ipairs(prio) do allowed[f] = true end

  if myFam and allowed[myFam] then
    if known[myFam] and myLeft <= db.expireMins * 60 then
      return myFam, "EXPIRING", myFam, myLeft
    end
    return
  end

  for _, fam in ipairs(prio) do
    local s = st[fam]
    if known[fam] and not (s and (s.own or s.other)) then
      local camp = s and s.camp
      if not (camp and db.campCountsAsBuffed) then
        local state = myFam and "SWAP" or (camp and "CAMP" or "MISSING")
        return fam, state, myFam, myLeft
      end
    end
  end
end

------------------------------------------------------------------------
-- Buttons
------------------------------------------------------------------------
-- Secure parent: hidden in combat by a state driver (works in lockdown).
local holder = CreateFrame("Frame", "BuffBarterHolder", UIParent, "SecureHandlerStateTemplate")
holder:SetAllPoints(UIParent)
RegisterStateDriver(holder, "visibility", "[combat] hide; show")

local pool, active = {}, {}   -- active[unitToken] = button
local pendingRebuild = false

-- PvP flagged players need an explicit second click: the first click only
-- unlocks the button for a few seconds.
local armed = {}       -- ["First Last"] = time until which a click casts
local ARM_TIME = 6
local function ArmKey(unit)
  local first, last = UnitName(unit)
  if not first then return end
  return (last and last ~= "") and (first .. " " .. last) or first
end
local function IsArmed(unit)
  local k = ArmKey(unit)
  return k and armed[k] and armed[k] > GetTime() or false
end
local function Arm(unit)
  local k = ArmKey(unit)
  if k then armed[k] = GetTime() + ARM_TIME end
  Print("|cffff4040" .. L.PVP_ARMED:format(k or "?", ARM_TIME) .. "|r")
end
-- The click edge (down or up) on which secure buttons actually cast.
local function ActionEdge(down)
  return (down and true or false) == (GetCVarBool("ActionButtonUseKeyDown") and true or false)
end

local STATE_COLOR = {
  MISSING  = { 0, 0, 0 },
  CAMP     = { 1, 0.5, 0 },
  EXPIRING = { 1, 0.85, 0 },
  SWAP     = { 0.7, 0.3, 1 },
}

local function OnEnter(self)
  if self.disp then
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(self.disp.debuff or "?", DispelColor(self.disp.dtype))
    GameTooltip:AddLine(UnitName(self.unit) or "?", 1, 1, 1)
    GameTooltip:AddLine(L.STATE_DISPEL:format(self.disp.spell), 0.5, 1, 0.5)
    if self.pvpFlag then GameTooltip:AddLine(L.PVP_WARN, 1, 0.25, 0.25, true) end
    GameTooltip:Show()
    return
  end
  if not self.fam or not known[self.fam] then return end
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:AddLine(known[self.fam].name)
  GameTooltip:AddLine(UnitName(self.unit) or "?", 1, 1, 1)
  if self.state == "SWAP" then
    local mine = known[self.myFam] and known[self.myFam].name or self.myFam
    GameTooltip:AddLine(L.STATE_SWAP:format(mine or "?"), 0.7, 0.3, 1)
  elseif self.state == "CAMP" then
    GameTooltip:AddLine(L.STATE_CAMP, 1, 0.5, 0)
  elseif self.state == "EXPIRING" then
    GameTooltip:AddLine(L.STATE_EXPIRING, 1, 0.85, 0)
  else
    GameTooltip:AddLine(L.STATE_MISSING, 0.8, 0.8, 0.8)
  end
  if self.pvpBlocked then
    GameTooltip:AddLine(L.PVP_BLOCKED, 1, 0.25, 0.25, true)
  else
    if self.pvpFlag then GameTooltip:AddLine(self.needsArm and L.PVP_ARM_TIP or L.PVP_WARN, 1, 0.25, 0.25, true) end
    if not self.needsArm then GameTooltip:AddLine(L.CLICK_TO_CAST, 0.5, 1, 0.5) end
  end
  GameTooltip:Show()
end

-- Forever only lets addon buttons cast on your current target. So the icon
-- sits on the nameplate: while the player is not your target the icon lets
-- clicks through (the click lands on the plate and targets the player);
-- once he is your target the icon takes the click and casts the blessing.
local function NewButton()
  local b = CreateFrame("Button", nil, holder, "SecureActionButtonTemplate")
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "macro")
  b:SetSize(db.size, db.size)
  b:SetFrameStrata("MEDIUM")

  b.border = b:CreateTexture(nil, "BACKGROUND")
  b.border:SetPoint("TOPLEFT", -2, 2)
  b.border:SetPoint("BOTTOMRIGHT", 2, -2)
  b.border:SetColorTexture(0, 0, 0, 0.9)

  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)

  -- PvP warning: faction emblem over the top right corner
  b.pvp = b:CreateTexture(nil, "OVERLAY", nil, 7)
  b.pvp:SetSize(math.floor(db.size * 0.9), math.floor(db.size * 0.9))
  b.pvp:SetPoint("CENTER", b, "TOPRIGHT", -2, -2)
  b.pvp:SetTexCoord(0, 0.62, 0, 0.62)
  b.pvp:Hide()

  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetHitRectInsets(-10, -10, -10, -10) -- easier to hit on moving players
  b:SetScript("OnEnter", OnEnter)
  b:SetScript("OnLeave", GameTooltip_Hide)
  b:HookScript("PostClick", function(self, mouse, down)
    if not ActionEdge(down) or not self.unit then return end
    if self.needsArm then
      Arm(self.unit)
      if ns.RefreshUnit then ns.RefreshUnit(self.unit) end
      if ns.UpdateQueue then ns.UpdateQueue() end
      return
    end
    if ns.Remember and self.clickable then ns.Remember(self.unit, self.fam) end
    if self.clickable and self.pvpFlag then
      Print("|cffff4040" .. L.PVP_CHAT:format(UnitName(self.unit) or "?") .. "|r")
    end
  end)
  b:EnableMouse(false) -- after SetScript, which can switch the mouse on
  return b
end

local function Release(unit)
  local b = active[unit]
  if not b then return end
  active[unit] = nil
  b:Hide()
  b:ClearAllPoints()
  b:SetAttribute("macrotext", nil)
  b:EnableMouse(false)
  b.unit, b.fam, b.state, b.myFam, b.clickable = nil, nil, nil, nil, nil
  table.insert(pool, b)
end

local function Eligible(unit)
  if not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return false end
  if not UnitCanAssist("player", unit) or UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then return false end
  if db.strangers then return true end
  return UnitInParty(unit) or UnitInRaid(unit) or (UnitIsInMyGuild and UnitIsInMyGuild(unit))
end

-- True when buffing this unit would flag me for PvP.
local function WouldFlag(unit)
  local ok, res = pcall(function()
    return (UnitIsPVP(unit) or UnitIsPVPFreeForAll(unit)) and not UnitIsPVP("player")
  end)
  return ok and res and true or false
end

local function PvPTexture(unit)
  if UnitIsPVPFreeForAll(unit) then return "Interface\\TargetingFrame\\UI-PVP-FFA" end
  local faction = UnitFactionGroup(unit)
  if faction == "Horde" then return "Interface\\TargetingFrame\\UI-PVP-Horde" end
  return "Interface\\TargetingFrame\\UI-PVP-Alliance"
end

local function RefreshBuff(unit)
  if InCombatLockdown() then pendingRebuild = true return end
  if not unit or not unit:match("^nameplate%d+$") then return end

  local plate = C_NamePlate.GetNamePlateForUnit(unit)
  if not Active() or not plate or (plate.IsForbidden and plate:IsForbidden()) or not Eligible(unit) then
    Release(unit); return
  end

  local disp = FindDispel(unit)
  local fam, state, myFam, myLeft
  if disp then
    state = "DISPEL"
  else
    fam, state, myFam, myLeft = Decide(unit)
    if not fam then Release(unit); return end
  end

  local b = active[unit]
  if not b then
    b = table.remove(pool) or NewButton()
    active[unit] = b
    b:ClearAllPoints()
    b:SetPoint("CENTER", plate, "CENTER", 0, db.offset)
  end

  local spell = disp and disp.spell or CastName(fam, UnitLevel(unit))
  local spellName = disp and disp.spell or known[fam].name
  local isTarget = UnitExists("target") and UnitIsUnit("target", unit)
  local pvpFlag = WouldFlag(unit)
  local blocked = pvpFlag and db.pvpMode == "block"
  b.pvpFlag, b.pvpBlocked = pvpFlag, blocked
  if pvpFlag then b.pvp:SetTexture(PvPTexture(unit)); b.pvp:Show() else b.pvp:Hide() end
  -- Forever does not let addons cast on nameplate units, but a secure macro
  -- may target a player by full name ("First Last"), cast, and switch back.
  local first, last = UnitName(unit)
  local tarName = first and ((last and last ~= "") and (first .. " " .. last) or first)
  local clickable = false
  local needsArm = pvpFlag and not blocked and not IsArmed(unit)
  b.needsArm = needsArm
  if blocked then
    b:SetAttribute("macrotext", nil)
  elseif needsArm then
    b:SetAttribute("macrotext", nil) -- first click only unlocks
    clickable = true
  elseif isTarget then
    b:SetAttribute("macrotext", "/cast [@target,help,nodead] " .. spell)
    clickable = true
  elseif db.oneClick and tarName then
    b:SetAttribute("macrotext", "/tar " .. tarName .. "\n/cast [@target,help,nodead] " .. spell .. "\n/targetlasttarget")
    clickable = true
  else
    b:SetAttribute("macrotext", nil)
  end
  b:EnableMouse(clickable)
  b.clickable = clickable
  b.isTarget = isTarget
  b.unit, b.fam, b.state, b.myFam, b.myLeft = unit, fam, state, myFam, myLeft
  b.disp = disp
  b.icon:SetTexture(disp and disp.debuffIcon or known[fam].icon)
  local c = pvpFlag and { 1, 0.1, 0.1 } or (disp and { DispelColor(disp.dtype) }) or STATE_COLOR[state]
  b.border:SetColorTexture(c[1], c[2], c[3], 0.9)

  if pvpFlag then
    b.label:SetText(needsArm and L.PVP_LABEL or L.PVP_CONFIRM); b.label:SetTextColor(1, 0.25, 0.25)
  elseif disp then
    b.label:SetText(L["DISPEL_" .. disp.dtype] or disp.dtype); b.label:SetTextColor(DispelColor(disp.dtype))
  elseif state == "CAMP" then
    b.label:SetText(L.CAMP); b.label:SetTextColor(1, 0.5, 0)
  elseif state == "EXPIRING" then
    b.label:SetText(("%dm"):format(math.max(0, math.floor(myLeft / 60)))); b.label:SetTextColor(1, 0.85, 0)
  elseif state == "SWAP" then
    b.label:SetText(L.SWAP); b.label:SetTextColor(0.7, 0.3, 1)
  else
    b.label:SetText("")
  end

  b:SetAlpha(InRange(spellName, unit) and (clickable and 1 or 0.6) or 0.3)
  -- With nameplate icons switched off the button stays invisible but keeps
  -- its data, which feeds the buff list.
  if IconsOn() then
    b:Show()
  else
    b:EnableMouse(false)
    b:Hide()
  end
end

-- Blessing icon plus request icon (the latter is defined further down).
local function Refresh(unit)
  RefreshBuff(unit)
  if ns.RefreshReq then ns.RefreshReq(unit) end
end

ns.RefreshUnit = Refresh

local function ReleaseBoth(unit)
  Release(unit)
  if ns.ReleaseReq then ns.ReleaseReq(unit) end
end

local function PlateUnit(plate)
  return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

local function RebuildAll()
  if InCombatLockdown() then pendingRebuild = true return end
  pendingRebuild = false
  for unit in pairs(active) do Release(unit) end
  if ns.ReleaseAllReq then ns.ReleaseAllReq() end
  if not Active() then return end
  for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
    local unit = PlateUnit(plate)
    if unit then Refresh(unit) end
  end
end

local function RefreshAll()
  if InCombatLockdown() then return end
  -- drop buttons whose plate vanished, then update existing plates
  for unit in pairs(active) do
    if not C_NamePlate.GetNamePlateForUnit(unit) then Release(unit) end
  end
  if ns.PruneReq then ns.PruneReq() end
  for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
    local unit = PlateUnit(plate)
    if unit then Refresh(unit) end
  end
end

------------------------------------------------------------------------
-- Smart button: one key buffs the player under the mouse (else your target)
------------------------------------------------------------------------
local smart = CreateFrame("Button", "BuffBarterSmartButton", UIParent, "SecureActionButtonTemplate")
smart:RegisterForClicks("AnyUp", "AnyDown")
smart:SetSize(1, 1)
smart:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
smart:SetAlpha(0)
smart:EnableMouse(false)
smart:SetAttribute("type", "macro")
smart:SetScript("PostClick", function(self, mouse, down)
  if ns.Remember and self.unit and self.fam then ns.Remember(self.unit, self.fam) end
  if db and db.debug then
    Print(("key down=%s unit=%s mouseover=%s target=%s  macrotext=%s"):format(tostring(down), tostring(self.unit),
      tostring(UnitName("mouseover")), tostring(UnitName("target")), tostring(self:GetAttribute("macrotext"))))
  end
end)

local function SmartEligible(u)
  return UnitExists(u) and UnitIsPlayer(u) and UnitCanAssist("player", u)
    and not UnitIsDeadOrGhost(u) and UnitIsConnected(u)
end

local function UpdateSmart()
  if not db or InCombatLockdown() then return end
  local unit = (SmartEligible("mouseover") and "mouseover") or (SmartEligible("target") and "target") or nil
  local text, sfam
  if unit and Active() and not (db.pvpMode == "block" and WouldFlag(unit)) then
    local disp = FindDispel(unit)
    local fam = not disp and Decide(unit)
    if disp then
      text = "/cast [@" .. unit .. ",help,nodead] " .. disp.spell
    elseif fam and known[fam] then
      text = "/cast [@" .. unit .. ",help,nodead] " .. CastName(fam, UnitLevel(unit))
      sfam = fam
    end
  end
  smart.fam = sfam
  -- nothing to buff: behave like a normal left click and target the player
  if not text and unit == "mouseover" then text = "/target [@mouseover,exists]" end
  smart:SetAttribute("macrotext", text)
  smart.unit = unit
end

------------------------------------------------------------------------
-- Buff list: a fixed panel with everybody nearby who needs a buff.
-- Rows do not move like nameplates do, and the "next" key buffs row one.
------------------------------------------------------------------------
local QUEUE_ROWS = 8
local ROW_H = 24
local STATE_ORDER = { DISPEL = 0, MISSING = 1, CAMP = 2, EXPIRING = 3, SWAP = 4 }

local queueHolder = CreateFrame("Frame", "BuffBarterQueueHolder", UIParent, "SecureHandlerStateTemplate")
queueHolder:SetAllPoints(UIParent)
RegisterStateDriver(queueHolder, "visibility", "[combat] hide; show")

local queue = CreateFrame("Frame", "BuffBarterQueue", queueHolder)
queue:SetSize(210, 44)
queue:SetPoint("LEFT", UIParent, "LEFT", 40, 80)
queue:SetClampedToScreen(true)
queue:SetMovable(true)
queue:EnableMouse(true)
queue:RegisterForDrag("LeftButton")
queue:SetScript("OnDragStart", function(self)
  if not db.queueLocked and not InCombatLockdown() then self:StartMoving() end
end)
queue:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local p, _, rp, x, y = self:GetPoint()
  db.queuePos = { p, rp, x, y }
end)
queue.bg = queue:CreateTexture(nil, "BACKGROUND")
queue.bg:SetAllPoints()
queue.bg:SetColorTexture(0.05, 0.07, 0.1, 0.75)
queue.edge = queue:CreateTexture(nil, "BORDER")
queue.edge:SetPoint("TOPLEFT"); queue.edge:SetPoint("TOPRIGHT"); queue.edge:SetHeight(2)
queue.edge:SetColorTexture(0.95, 0.75, 0.25, 0.9)
queue.title = queue:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
queue.title:SetPoint("TOPLEFT", 8, -6)
queue.title:SetText("BuffBarter")
queue.toggle = CreateFrame("Button", nil, queue)
queue.toggle:SetSize(16, 16)
queue.toggle:SetPoint("TOPRIGHT", -4, -2)
queue.toggle:SetScript("OnClick", function()
  if InCombatLockdown() then return end
  if CityMode() then cityFolded = not cityFolded else db.queueCollapsed = not db.queueCollapsed end
  if ns.UpdateQueue then ns.UpdateQueue() end
end)
queue.toggle:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  local folded = CityMode() and cityFolded or (not CityMode() and db.queueCollapsed)
  GameTooltip:AddLine(folded and L.QUEUE_EXPAND or L.QUEUE_COLLAPSE)
  if CityMode() then GameTooltip:AddLine(L.QUEUE_CITY, 0.7, 0.7, 0.7, true) end
  GameTooltip:Show()
end)
queue.toggle:SetScript("OnLeave", GameTooltip_Hide)
-- eye button: icons above players on/off
queue.eye = CreateFrame("Button", nil, queue)
queue.eye:SetSize(16, 16)
queue.eye:SetPoint("RIGHT", queue.toggle, "LEFT", -4, 0)
queue.eye.tex = queue.eye:CreateTexture(nil, "ARTWORK")
queue.eye.tex:SetAllPoints()
queue.eye.tex:SetTexture("Interface\\Icons\\INV_Misc_Eye_01")
queue.eye.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
queue.eye:SetScript("OnClick", function()
  if InCombatLockdown() then return end
  if CityMode() then cityIcons = not cityIcons else db.plateIcons = not db.plateIcons end
  RebuildAll()
  if ns.UpdateQueue then ns.UpdateQueue() end
end)
queue.eye:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(IconsOn() and L.EYE_HIDE or L.EYE_SHOW)
  if CityMode() then GameTooltip:AddLine(L.CITY_VISIT, 0.7, 0.7, 0.7, true) end
  GameTooltip:Show()
end)
queue.eye:SetScript("OnLeave", GameTooltip_Hide)
-- speech bubble button: request ("ask") icons on/off
queue.ask = CreateFrame("Button", nil, queue)
queue.ask:SetSize(16, 16)
queue.ask:SetPoint("RIGHT", queue.eye, "LEFT", -4, 0)
queue.ask.tex = queue.ask:CreateTexture(nil, "ARTWORK")
queue.ask.tex:SetAllPoints()
queue.ask.tex:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
queue.ask:SetScript("OnClick", function()
  if InCombatLockdown() then return end
  if CityMode() then cityAsk = not cityAsk else db.showRequest = not db.showRequest end
  RebuildAll()
  if ns.UpdateQueue then ns.UpdateQueue() end
end)
queue.ask:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(AskOn() and L.ASK_HIDE or L.ASK_SHOW)
  if CityMode() then GameTooltip:AddLine(L.CITY_VISIT, 0.7, 0.7, 0.7, true) end
  GameTooltip:Show()
end)
queue.ask:SetScript("OnLeave", GameTooltip_Hide)
queue.empty = queue:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
queue.empty:SetPoint("TOPLEFT", 8, -24)
queue.rows = {}

local function ClassRGB(class)
  local col = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if col then return col.r, col.g, col.b end
  return 0.9, 0.9, 0.9
end

local function RowOnEnter(self)
  if self.unit and self.disp then
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.disp.debuff or "?", DispelColor(self.disp.dtype))
    GameTooltip:AddLine(self.unit == "player" and L.QUEUE_YOU or (UnitName(self.unit) or "?"), 1, 1, 1)
    GameTooltip:AddLine(L.STATE_DISPEL:format(self.disp.spell), 0.5, 1, 0.5)
    GameTooltip:Show()
    return
  end
  if not self.unit or not self.fam or not known[self.fam] then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(CastName(self.fam, UnitLevel(self.unit)) or known[self.fam].name)
  GameTooltip:AddLine(self.unit == "player" and L.QUEUE_YOU or (UnitName(self.unit) or "?"), 1, 1, 1)
  if self.pvpFlag then GameTooltip:AddLine(self.needsArm and L.PVP_ARM_TIP or L.PVP_WARN, 1, 0.25, 0.25, true) end
  if not self.needsArm then GameTooltip:AddLine(L.CLICK_TO_CAST, 0.5, 1, 0.5) end
  GameTooltip:Show()
end

for i = 1, QUEUE_ROWS do
  local r = CreateFrame("Button", "BuffBarterQueueRow" .. i, queue, "SecureActionButtonTemplate")
  r:RegisterForClicks("AnyUp", "AnyDown")
  r:SetAttribute("type", "macro")
  r:SetSize(196, ROW_H - 2)
  r:SetPoint("TOPLEFT", 7, -20 - (i - 1) * ROW_H)
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints()
  r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.05 or 0.02)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(20, 20)
  r.icon:SetPoint("LEFT", 1, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.name:SetWidth(122)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  r.tag:SetPoint("RIGHT", -4, 0)
  r:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  r:SetScript("OnEnter", RowOnEnter)
  r:SetScript("OnLeave", GameTooltip_Hide)
  r:HookScript("PostClick", function(self, mouse, down)
    if not ActionEdge(down) or not self.unit then return end
    if self.needsArm then
      Arm(self.unit)
      if ns.UpdateQueue then ns.UpdateQueue() end
      if ns.RefreshUnit then ns.RefreshUnit(self.unit) end
      return
    end
    if ns.Remember and self.unit ~= "player" and self.fam then ns.Remember(self.unit, self.fam) end
  end)
  r:Hide()
  queue.rows[i] = r
end

-- invisible button behind the "next" key
local nextBtn = CreateFrame("Button", "BuffBarterNextButton", UIParent, "SecureActionButtonTemplate")
nextBtn:RegisterForClicks("AnyUp", "AnyDown")
nextBtn:SetSize(1, 1)
nextBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
nextBtn:SetAlpha(0)
nextBtn:EnableMouse(false)
nextBtn:SetAttribute("type", "macro")
nextBtn:HookScript("PostClick", function(self)
  if ns.Remember and self.unit and self.unit ~= "player" and self.fam then ns.Remember(self.unit, self.fam) end
end)

local function QueueMacro(unit, fam, spellOverride)
  local spell = spellOverride or CastName(fam, UnitLevel(unit))
  if not spell then return end
  if unit == "player" then return "/cast [@player] " .. spell end
  local first, last = UnitName(unit)
  if not first then return end
  local tar = (last and last ~= "") and (first .. " " .. last) or first
  return "/tar " .. tar .. "\n/cast [@target,help,nodead] " .. spell .. "\n/targetlasttarget"
end

local function RestoreQueuePosition()
  if InCombatLockdown() or not db.queuePos then return end
  local p = db.queuePos
  queue:ClearAllPoints()
  queue:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local function UpdateQueue()
  if not db or InCombatLockdown() or ns.demo then return end
  if not Active() or not db.showQueue then
    queue:Hide()
    nextBtn:SetAttribute("macrotext", nil)
    return
  end
  local list = {}
  -- yourself first (you have no nameplate)
  local selfDisp = FindDispel("player")
  local ok, fam, state, _, left = pcall(Decide, "player")
  if selfDisp then
    list[#list + 1] = { unit = "player", disp = selfDisp, state = "DISPEL", inRange = true, me = true }
  elseif ok and fam and known[fam] then
    list[#list + 1] = { unit = "player", fam = fam, state = state, left = left, inRange = true, me = true }
  end
  for unit, b in pairs(active) do
    if b.disp and UnitExists(unit) then
      list[#list + 1] = { unit = unit, disp = b.disp, state = "DISPEL",
                          inRange = InRange(b.disp.spell, unit), pvp = b.pvpFlag }
    elseif b.fam and known[b.fam] and UnitExists(unit) then
      list[#list + 1] = { unit = unit, fam = b.fam, state = b.state, left = b.myLeft,
                          inRange = InRange(known[b.fam].name, unit), pvp = b.pvpFlag }
    end
  end
  table.sort(list, function(x, y)
    if (x.me and 1 or 0) ~= (y.me and 1 or 0) then return x.me and true or false end
    if (x.inRange and 1 or 0) ~= (y.inRange and 1 or 0) then return x.inRange and true or false end
    return (STATE_ORDER[x.state] or 9) < (STATE_ORDER[y.state] or 9)
  end)

  local nextSet = false
  for i = 1, QUEUE_ROWS do
    local r, e = queue.rows[i], list[i]
    local text = e and QueueMacro(e.unit, e.fam, e.disp and e.disp.spell)
    if e and text then
      local _, class = UnitClass(e.unit)
      local needsArm = e.pvp and not IsArmed(e.unit)
      r:SetAttribute("macrotext", (not needsArm) and text or nil)
      r.needsArm = needsArm
      r.bg:SetColorTexture(e.pvp and 0.6 or 1, e.pvp and 0.05 or 1, e.pvp and 0.05 or 1,
        e.pvp and 0.25 or ((i % 2 == 0) and 0.05 or 0.02))
      r.unit, r.fam, r.pvpFlag, r.disp = e.unit, e.fam, e.pvp, e.disp
      r.icon:SetTexture(e.disp and e.disp.debuffIcon or known[e.fam].icon)
      r.name:SetText((e.me and L.QUEUE_YOU or (UnitName(e.unit) or "?")) .. "  |cff8a8a8a" .. (UnitLevel(e.unit) or "") .. "|r")
      r.name:SetTextColor(ClassRGB(class))
      if e.pvp then
        r.tag:SetText(needsArm and L.PVP_ARM or L.PVP_CONFIRM)
        r.tag:SetTextColor(1, needsArm and 0.25 or 0.8, 0.25)
      elseif e.disp then
        r.tag:SetText(L["DISPEL_" .. e.disp.dtype] or e.disp.dtype); r.tag:SetTextColor(DispelColor(e.disp.dtype))
      elseif e.state == "CAMP" then
        r.tag:SetText(L.CAMP); r.tag:SetTextColor(1, 0.5, 0)
      elseif e.state == "EXPIRING" and e.left then
        r.tag:SetText(("%dm"):format(math.max(0, math.floor(e.left / 60)))); r.tag:SetTextColor(1, 0.85, 0)
      elseif e.state == "SWAP" then
        r.tag:SetText(L.SWAP); r.tag:SetTextColor(0.7, 0.3, 1)
      else
        r.tag:SetText("")
      end
      r:SetAlpha(e.inRange and 1 or 0.4)
      r:Show()
      if not nextSet and e.inRange and not e.pvp then
        nextBtn:SetAttribute("macrotext", text)
        nextBtn.unit, nextBtn.fam = e.unit, (not e.disp) and e.fam or nil
        nextSet = true
      end
    else
      r:Hide()
      r:SetAttribute("macrotext", nil)
      r.unit, r.fam, r.disp = nil, nil, nil
    end
  end
  if not nextSet then
    nextBtn:SetAttribute("macrotext", nil)
    nextBtn.unit, nextBtn.fam = nil, nil
  end

  local n = math.min(#list, QUEUE_ROWS)
  CheckCityChange()
  local city = CityMode()
  local folded = (city and cityFolded) or (not city and db.queueCollapsed)
  queue.title:SetText((#list > 0 and ("BuffBarter  |cffffffff" .. #list .. "|r") or "BuffBarter")
    .. (city and ("  |cff8a8a8a" .. L.QUEUE_CITY_TAG .. "|r") or ""))
  local tex = folded and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up"
  queue.toggle:SetNormalTexture(tex)
  queue.eye.tex:SetDesaturated(not IconsOn())
  queue.eye:SetAlpha(IconsOn() and 1 or 0.5)
  queue.ask.tex:SetDesaturated(not AskOn())
  queue.ask:SetAlpha(AskOn() and 1 or 0.5)
  if folded then
    for i = 1, QUEUE_ROWS do queue.rows[i]:Hide() end -- the next key keeps working
    queue.empty:SetText("")
    queue:SetHeight(20)
  else
    queue.empty:SetText(n == 0 and L.QUEUE_EMPTY or "")
    queue:SetHeight(26 + math.max(n, 1) * ROW_H)
  end
  queue:Show()
end
ns.UpdateQueue = UpdateQueue

------------------------------------------------------------------------
-- Asking for a buff back
------------------------------------------------------------------------
local pending          -- { full, class, fam, t } of the last blessing click
local askedAt = {}     -- ["Name-Realm"] = GetTime(), one ask per 30 minutes
local ASK_COOLDOWN = 30 * 60

local function FullName(unit)
  local n, realm = UnitName(unit)
  if not n then return end
  return (realm and realm ~= "") and (n .. "-" .. realm) or n, n, realm
end

-- "class", "camp" or nil: do I have this buff family myself?
-- "class" or "camp" (or nil) plus the longest time left of the class version.
local function PlayerHas(fam)
  local res, left
  local now = GetTime()
  pcall(ForEachBuff, "player", function(name, id, src, exp)
    local f = (id and (otherIdToFam[id] or idToFamily[id])) or (name and (otherNameToFam[name] or nameToFamily[name]))
    if f == fam then
      res = "class"
      local l = (exp and exp > 0) and (exp - now) or 3600
      left = math.max(left or 0, l)
    end
    if not res and CampFamily(id) == fam then res = "camp" end
  end)
  return res, left
end

-- Did this player already give me a blessing? (One blessing per paladin:
-- asking for another one would only replace it.)
local function HasBlessingFrom(unit)
  if not unit or not UnitExists(unit) then return false end
  local found = false
  pcall(ForEachBuff, "player", function(name, id, src, exp)
    local f = (id and idToFamily[id]) or (name and nameToFamily[name])
    if f and ns.BUFFS[f].blessing and src and UnitIsUnit(src, unit) then
      local left = (exp and exp > 0) and (exp - GetTime()) or 3600
      -- running out soon: asking the same paladin again is fine
      if left >= db.askRemainMin * 60 then found = true end
    end
  end)
  return found
end

local function Lacking(fam)
  local has, left = PlayerHas(fam)
  if has == "class" then return (left or 3600) < db.askRemainMin * 60 end
  if has == "camp" and db.askCampCounts then return false end
  return true
end

-- Level at which a family's first rank is learned (Might 4, Kings 20, ...).
local function FamMinLevel(fam)
  local d = ns.BUFFS[fam]
  if not d then return 1 end
  return ns.RANK_LEVELS[d.ids[#d.ids]] or 1
end

-- Can a player of giverLevel cast this buff at all, and can it land on you?
-- Low level players simply do not have the spell yet (no Kings before 20).
-- Unknown levels (0, nil, or -1 for "??") are treated as fine.
-- Level 1 spells still have to be bought from the trainer, and brand new
-- characters often have not been there yet: nobody below 4 is asked.
local ASK_GIVER_MIN = 4
local function CanGive(fam, giverLevel)
  local min = FamMinLevel(fam)
  if giverLevel and giverLevel > 0 and giverLevel < math.max(min, ASK_GIVER_MIN) then return false end
  local me = UnitLevel("player") or 60
  return me <= 0 or me >= min - 10
end

-- Which buff to ask this class for, or nil when there is nothing to ask.
-- giverLevel: level of the player you would ask.
local function AskFamily(class, giverLevel)
  local what = ns.ASK_FOR[class]
  if not what then return nil end
  if what == "BLESSING" then
    for _, fam in ipairs(ns.SELF_WISH) do
      if Lacking(fam) and CanGive(fam, giverLevel) then return fam end
    end
    return nil
  end
  if not CanGive(what, giverLevel) then return nil end
  if db.askOnlyIfMissing and not Lacking(what) then return nil end
  return what
end

-- Forever has no realms: "First-Last" is the character's two-part name, and
-- players are grouped by their Preferred Online Language. So: your own
-- language, unless you set this player with /barter lang.
local function LangFor(full)
  return db.playerLang[full] or db.myLang
end

local function SpellLink(id)
  if not id then return end
  local link
  if C_Spell and C_Spell.GetSpellLink then link = C_Spell.GetSpellLink(id)
  elseif GetSpellLink then link = (GetSpellLink(id)) end
  if not link then return end
  -- "[Blessing of Wisdom (Rank 5)]" -> "[Blessing of Wisdom]": the rank text
  -- looks odd and makes the server drop the link to plain text.
  link = link:gsub("%s*%([^%)%]]*%)%]", "]")
  return link
end

-- Representative spell ID of a family (for links).
local function FamilySpellID(fam)
  if known[fam] and known[fam].id then return known[fam].id end
  if ns.BUFFS[fam] then return ns.BUFFS[fam].ids[1] end
end

local function Template(lang, key)
  local t = db.templates[lang]
  if t and t[key] ~= nil then return t[key] end
  return ns.DEFAULT_TEMPLATES[lang] and ns.DEFAULT_TEMPLATES[lang][key] or ""
end

-- Builds the whisper. Returns text, lang  or nil, lang when nothing to send.
local function BuildAsk(full, short, realm, class, fam, level)
  local lang = LangFor(full)
  local key = ns.ASK_FOR[class] and class or "OTHER"
  local askFam = AskFamily(class, level)
  if ns.ASK_FOR[class] and not askFam then return nil, lang end
  local text = Template(lang, key)
  if not text or strtrim(text) == "" then return nil, lang end
  local names = ns.BUFF_NAMES[lang] or ns.BUFF_NAMES.en
  local sub = {
    name = short or full,
    buff = names[fam] or (known[fam] and known[fam].name) or "",
    ask  = askFam and names[askFam] or "",
    me   = UnitName("player") or "",
  }
  if db.useLinks then
    sub.buff = SpellLink(FamilySpellID(fam)) or sub.buff
    if askFam then sub.ask = SpellLink(FamilySpellID(askFam)) or sub.ask end
  end
  text = text:gsub("{(%w+)}", function(k) return sub[k] end)
  return text, lang
end

local function CanWhisper()
  if IsInInstance() then return false end
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return false end
  return true
end

-- Low level players only have low ranks: buff them, but do not ask them.
local function LevelOK(level)
  if not level or level <= 0 or db.askMaxBelow >= 60 then return true end
  return level >= (UnitLevel("player") or 1) - db.askMaxBelow
end

-- Say thanks when someone buffs you: /thank emote or a whisper.
-- At most once per player every 30 minutes, never inside instances.
-- Group and raid members buff each other anyway: no automatic whispers to
-- them unless the player switches that on.
local function GroupMuted(unit)
  if db.msgToGroup or not unit or not UnitExists(unit) then return false end
  return (UnitInParty(unit) or UnitInRaid(unit)) and true or false
end

local thankedAt = {}
local function ThankFor(unit, full, short, fam)
  local function why(reason)
    if db.debug then Print(("thanks to %s skipped: %s"):format(tostring(full), reason)) end
  end
  if not db.thank then return why("switched off") end
  if not unit or not full then return why("buffer unknown") end
  if not CanWhisper() then return why("no whispers here") end
  if GroupMuted(unit) then return why("group member") end
  if thankedAt[full] and GetTime() - thankedAt[full] < ASK_COOLDOWN then return why("thanked recently") end
  thankedAt[full] = GetTime()
  if db.thankMode == "whisper" then
    local lang = LangFor(full)
    local text = Template(lang, "THANKS")
    if not text or strtrim(text) == "" then return end
    local names = ns.BUFF_NAMES[lang] or ns.BUFF_NAMES.en
    local buff = names[fam] or ""
    if db.useLinks then buff = SpellLink(FamilySpellID(fam)) or buff end
    local sub = { name = short or full, buff = buff, ask = buff, me = UnitName("player") or "" }
    text = text:gsub("{(%w+)}", function(k) return sub[k] end)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local ok, err = pcall(send, text, "WHISPER", nil, full)
    if not ok then why("whisper failed: " .. tostring(err)) end
  else
    local ok, err = pcall(DoEmote, "THANK", unit)
    if not ok then why("emote failed: " .. tostring(err)) end
  end
end

function ns.Remember(unit, fam)
  if not UnitExists(unit) or not fam then return end
  local full, short, realm = FullName(unit)
  local _, class = UnitClass(unit)
  local raceName, race = UnitRace(unit)
  if not full or UnitIsUnit(unit, "player") then return end
  pending = { full = full, short = short, realm = realm, class = class, race = race, raceName = raceName,
              unit = unit,
              level = UnitLevel(unit),
              fam = fam, t = GetTime() }
end

------------------------------------------------------------------------
-- Statistics (per character, stored in BuffBarterDB.stats)
------------------------------------------------------------------------
local answered = {}   -- ["First-Last"] = true once a buff came back after asking
local ANSWER_WINDOW = 15 * 60

local function CharStats()
  db.stats = db.stats or {}
  local key = UnitName("player") or "?"
  local st = db.stats[key]
  if not st then
    st = {
      since = time(),
      given    = { total = 0, players = {}, classes = {}, buffs = {} },
      received = { total = 0, players = {}, classes = {}, buffs = {}, camp = 0 },
      asks     = { afterBuff = 0, requests = 0, answered = 0 },
    }
    db.stats[key] = st
  end
  -- fields added later
  st.given.races = st.given.races or {}
  st.received.races = st.received.races or {}
  st.playerClass = st.playerClass or {}
  st.raceNames = st.raceNames or {}
  return st
end

local function Bump(t, k) if k then t[k] = (t[k] or 0) + 1 end end

local function Remember(st, full, class, race, raceName)
  if full and class then st.playerClass[full] = class end
  if race and raceName then st.raceNames[race] = raceName end
end

local function RecordGiven(full, class, fam, race, raceName)
  local st = CharStats()
  local g = st.given
  g.total = g.total + 1
  Bump(g.players, full); Bump(g.classes, class); Bump(g.buffs, fam); Bump(g.races, race)
  Remember(st, full, class, race, raceName)
end

local function RecordReceived(full, class, fam, isCamp, race, raceName)
  local st = CharStats()
  local r = st.received
  if isCamp then r.camp = r.camp + 1 return end
  r.total = r.total + 1
  Bump(r.players, full); Bump(r.classes, class); Bump(r.buffs, fam); Bump(r.races, race)
  Remember(st, full, class, race, raceName)
  if full and askedAt[full] and not answered[full] and GetTime() - askedAt[full] < ANSWER_WINDOW then
    answered[full] = true
    st.asks.answered = st.asks.answered + 1
  end
end

local function RecordAsk(full, kind)
  local asks = CharStats().asks
  asks[kind] = (asks[kind] or 0) + 1
  answered[full] = nil
end

-- New buffs on me (UNIT_AURA updateInfo.addedAuras), out of combat only.
local function OnPlayerAura(info)
  if InCombatLockdown() or not db or not info or not info.addedAuras then return end
  for _, a in ipairs(info.addedAuras) do
    pcall(function()
      if a.isHelpful == false then return end
      local id, name, src = a.spellId, a.name, a.sourceUnit
      local fam = (id and (otherIdToFam[id] or idToFamily[id])) or (name and (otherNameToFam[name] or nameToFamily[name]))
      local camp = (not fam) and CampFamily(id)
      if not fam and not camp then return end
      if src and UnitIsUnit(src, "player") then return end
      if db.debug then
        Print(("buff received: %s  id=%s  from=%s"):format(tostring(name), tostring(id), tostring(src and UnitName(src) or src)))
      end
      local full, class, race, raceName
      if src and UnitExists(src) and UnitIsPlayer(src) then
        full = FullName(src)
        class = select(2, UnitClass(src))
        raceName, race = UnitRace(src)
      end
      RecordReceived(full, class, fam or camp, camp and true, race, raceName)
      if full and not camp then
        local short = UnitName(src)
        ThankFor(src, full, short, fam)
      end
    end)
  end
end

local function OnOwnCast(spellID)
  local fam = spellID and (idToFamily[spellID] or nameToFamily[SpellInfo(spellID) or ""])
  if not fam then return end
  local p = (pending and GetTime() - pending.t <= 3) and pending or nil
  pending = nil
  -- cast from your action bars: count it for your current target
  if not p and UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player")
    and UnitCanAssist("player", "target") then
    local full, short, realm = FullName("target")
    local _, class = UnitClass("target")
    local raceName, race = UnitRace("target")
    p = { full = full, short = short, realm = realm, class = class, race = race, raceName = raceName,
          fam = fam, fromBar = true }
  end
  if not p then return end
  pcall(RecordGiven, p.full, p.class, fam, p.race, p.raceName)
  if p.fromBar then return end -- only ask back after buffs given through BuffBarter
  if not db.askBack or not CanWhisper() or not LevelOK(p.level) then return end
  if askedAt[p.full] and GetTime() - askedAt[p.full] < ASK_COOLDOWN then return end
  if p.class == "PALADIN" and HasBlessingFrom(p.unit) then return end
  if GroupMuted(p.unit) then return end
  local text = BuildAsk(p.full, p.short, p.realm, p.class, p.fam, p.level)
  if not text then return end
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  if pcall(send, text, "WHISPER", nil, p.full) then
    askedAt[p.full] = GetTime()
    RecordAsk(p.full, "afterBuff")
  end
end

------------------------------------------------------------------------
-- Request icons: click a priest/mage/druid/paladin to ask for their buff.
-- Whispering is allowed outside instances, so these are plain buttons and
-- work with a single click (no targeting needed).
------------------------------------------------------------------------
local reqPool, reqActive = {}, {}

-- Blessings I would like from another paladin.
local function MyBlessingWish()
  local _, myClass = UnitClass("player")
  if myClass == "PALADIN" then return ns.SELF_WISH end
  local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
  return (role == "TANK" and ns.PRIO.TANK) or ns.PRIO[myClass] or ns.SELF_WISH
end

-- What I would ask a player of this class for, or nil.
local function RequestFamily(class, unit)
  local what = ns.ASK_FOR[class]
  if not what then return nil end
  local level = UnitLevel(unit)
  if what == "BLESSING" then
    if HasBlessingFrom(unit) then return nil end
    for _, fam in ipairs(MyBlessingWish()) do
      if Lacking(fam) and CanGive(fam, level) then return fam end
    end
    return nil
  end
  local _, myClass = UnitClass("player")
  if ns.NO_WANT[myClass] and ns.NO_WANT[myClass][what] then return nil end
  if not CanGive(what, level) then return nil end
  if not Lacking(what) then return nil end
  return what
end

local function BuildRequest(unit, fam)
  local full, short = FullName(unit)
  if not full then return end
  local lang = LangFor(full)
  local text = Template(lang, "REQUEST")
  if not text or strtrim(text) == "" then return end
  local names = ns.BUFF_NAMES[lang] or ns.BUFF_NAMES.en
  local ask = names[fam] or ""
  if db.useLinks then ask = SpellLink(FamilySpellID(fam)) or ask end
  local sub = { name = short or full, ask = ask, buff = ask, me = UnitName("player") or "" }
  return (text:gsub("{(%w+)}", function(k) return sub[k] end)), full
end

local function ReqOnEnter(self)
  if not self.unit or not self.fam then return end
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  local names = ns.BUFF_NAMES[db.myLang] or ns.BUFF_NAMES.en
  local who = UnitName(self.unit) or "?"
  GameTooltip:AddLine(names[self.fam] or self.fam)
  if self.asked then
    local left = math.ceil((ASK_COOLDOWN - (GetTime() - self.asked)) / 60)
    GameTooltip:AddLine(L.REQ_TIP_ASKED:format(math.max(1, left)), 0.7, 0.7, 0.7, true)
  else
    GameTooltip:AddLine(L.REQ_TIP:format(who), 0.5, 1, 0.5, true)
  end
  GameTooltip:Show()
end

local function ReqOnClick(self)
  if not self.unit or not self.fam or self.asked then return end
  if not CanWhisper() then Print(L.REQ_NO_WHISPER) return end
  local text, full = BuildRequest(self.unit, self.fam)
  if not text then return end
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  if pcall(send, text, "WHISPER", nil, full) then
    askedAt[full] = GetTime()
    RecordAsk(full, "requests")
    -- if the other player runs BuffBarter too, they get a window with a buff button
    if ns.SendBuffRequest then ns.SendBuffRequest(full, self.fam) end
    if ns.RefreshReq then ns.RefreshReq(self.unit) end
  end
end

local function NewReqButton()
  local b = CreateFrame("Button", nil, holder)
  local size = math.floor(db.size * 0.85)
  b:SetSize(size, size)
  b:SetFrameStrata("MEDIUM")
  b.border = b:CreateTexture(nil, "BACKGROUND")
  b.border:SetPoint("TOPLEFT", -2, 2)
  b.border:SetPoint("BOTTOMRIGHT", 2, -2)
  b.border:SetColorTexture(0.2, 0.8, 1, 0.9)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:RegisterForClicks("LeftButtonUp")
  b:SetScript("OnClick", ReqOnClick)
  b:SetScript("OnEnter", ReqOnEnter)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

function ns.ReleaseReq(unit)
  local b = reqActive[unit]
  if not b then return end
  reqActive[unit] = nil
  b:Hide()
  b:ClearAllPoints()
  b.unit, b.fam, b.asked = nil, nil, nil
  table.insert(reqPool, b)
end

function ns.ReleaseAllReq()
  for unit in pairs(reqActive) do ns.ReleaseReq(unit) end
end

function ns.PruneReq()
  for unit in pairs(reqActive) do
    if not C_NamePlate.GetNamePlateForUnit(unit) then ns.ReleaseReq(unit) end
  end
end

function ns.RefreshReq(unit)
  if InCombatLockdown() then return end
  if not unit or not unit:match("^nameplate%d+$") then return end
  local plate = C_NamePlate.GetNamePlateForUnit(unit)
  if not Active() or not AskOn() or IsInInstance() or not plate
    or (plate.IsForbidden and plate:IsForbidden()) or not Eligible(unit) then
    ns.ReleaseReq(unit); return
  end
  local _, class = UnitClass(unit)
  if not LevelOK(UnitLevel(unit)) then ns.ReleaseReq(unit); return end
  local ok, fam = pcall(RequestFamily, class, unit)
  if not ok or not fam then ns.ReleaseReq(unit); return end
  local full = FullName(unit)
  local asked = full and askedAt[full]
  if asked and GetTime() - asked >= ASK_COOLDOWN then asked = nil end

  local b = reqActive[unit]
  if not b then
    b = table.remove(reqPool) or NewReqButton()
    reqActive[unit] = b
    b:ClearAllPoints()
    b:SetPoint("LEFT", plate, "RIGHT", 2, db.offset)
  end
  b.unit, b.fam, b.asked = unit, fam, asked
  local id = FamilySpellID(fam)
  local _, icon = SpellInfo(id)
  if not icon and id and C_Spell and C_Spell.GetSpellTexture then icon = C_Spell.GetSpellTexture(id) end
  b.icon:SetTexture(icon or 134400)
  if asked then
    b.label:SetText(L.REQ_ASKED); b.label:SetTextColor(0.7, 0.7, 0.7)
    b.icon:SetDesaturated(true)
    b:SetAlpha(0.5)
  else
    b.label:SetText(L.REQ_LABEL); b.label:SetTextColor(0.4, 0.85, 1)
    b.icon:SetDesaturated(false)
    b:SetAlpha(1)
  end
  b:Show()
end

------------------------------------------------------------------------
-- Buff requests between BuffBarter users. A chat link cannot cast anything,
-- but an addon message can open a window on the other side, and a click
-- there (by that player) buffs you.
------------------------------------------------------------------------
local PREFIX = "BuffBarter"
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

local incoming = {}      -- { short, tarName, fam, level, t, self }
local lastFrom = {}      -- ["First-Last"] = time of the last accepted request
local REQ_SPAM, REQ_TTL, REQ_MAX = 120, 60, 3

function ns.SendBuffRequest(full, fam)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) or not full or not fam then return end
  pcall(C_ChatInfo.SendAddonMessage, PREFIX, ("REQ:%s:%d"):format(fam, UnitLevel("player") or 1), "WHISPER", full)
end

local popup = CreateFrame("Frame", "BuffBarterRequestPopup", queueHolder)
popup:SetSize(320, 92)
popup:SetPoint("TOP", UIParent, "TOP", 0, -150)
popup:SetFrameStrata("DIALOG")
popup:EnableMouse(true)
popup:Hide()
popup.bg = popup:CreateTexture(nil, "BACKGROUND")
popup.bg:SetAllPoints()
popup.bg:SetColorTexture(0.05, 0.07, 0.1, 0.9)
popup.edge = popup:CreateTexture(nil, "BORDER")
popup.edge:SetPoint("TOPLEFT"); popup.edge:SetPoint("TOPRIGHT"); popup.edge:SetHeight(2)
popup.edge:SetColorTexture(0.3, 0.75, 1, 0.9)
popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
popup.title:SetPoint("TOPLEFT", 10, -8)
popup.icon = popup:CreateTexture(nil, "ARTWORK")
popup.icon:SetSize(32, 32)
popup.icon:SetPoint("TOPLEFT", 10, -24)
popup.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
popup.text = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
popup.text:SetPoint("TOPLEFT", popup.icon, "TOPRIGHT", 10, -2)
popup.text:SetWidth(258)
popup.text:SetJustifyH("LEFT")

popup.buff = CreateFrame("Button", "BuffBarterRequestBuff", popup, "SecureActionButtonTemplate,UIPanelButtonTemplate")
popup.buff:SetSize(130, 24)
popup.buff:SetPoint("BOTTOMLEFT", 52, 10)
popup.buff:RegisterForClicks("AnyUp", "AnyDown")
popup.buff:SetAttribute("type", "macro")
popup.buff:SetText(L.REQ_POPUP_BUFF)

popup.no = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
popup.no:SetSize(110, 24)
popup.no:SetPoint("LEFT", popup.buff, "RIGHT", 8, 0)
popup.no:SetText(L.REQ_POPUP_NO)

local function ShowRequest()
  if InCombatLockdown() then return end -- the window waits until after combat
  local now = GetTime()
  while incoming[1] and now - incoming[1].t > REQ_TTL do table.remove(incoming, 1) end
  local r = incoming[1]
  if not r or not known[r.fam] then
    if r then table.remove(incoming, 1) end
    popup.buff:SetAttribute("macrotext", nil)
    popup:Hide()
    return
  end
  local spell = CastName(r.fam, r.level)
  if r.self then
    popup.buff:SetAttribute("macrotext", "/cast [@player] " .. spell)
  else
    popup.buff:SetAttribute("macrotext", "/tar " .. r.tarName .. "\n/cast [@target,help,nodead] " .. spell .. "\n/targetlasttarget")
  end
  popup.title:SetText("BuffBarter: " .. L.REQ_POPUP_TITLE .. (#incoming > 1 and ("  |cff8a8a8a(+" .. (#incoming - 1) .. ")|r") or ""))
  popup.icon:SetTexture(known[r.fam].icon)
  popup.text:SetText(L.REQ_POPUP:format(r.short, known[r.fam].name))
  popup:Show()
end
ns.ShowRequest = ShowRequest

local function NextRequest()
  if InCombatLockdown() then return end
  table.remove(incoming, 1)
  ShowRequest()
end

popup.buff:HookScript("PostClick", function(self, mouse, down)
  if ActionEdge(down) then C_Timer.After(0.1, NextRequest) end
end)
popup.no:SetScript("OnClick", NextRequest)

local function OnAddonMessage(prefix, msg, channel, sender)
  if prefix ~= PREFIX or not db or not db.acceptRequests or not msg or not sender then return end
  local fam, lvl = msg:match("^REQ:(%u+):(%d+)$")
  if not fam or not known[fam] then return end
  if not Active() or IsInInstance() then return end
  if lastFrom[sender] and GetTime() - lastFrom[sender] < REQ_SPAM then return end
  if #incoming >= REQ_MAX then return end
  lastFrom[sender] = GetTime()
  incoming[#incoming + 1] = {
    short = sender:match("^[^-]+") or sender,
    tarName = (sender:gsub("%-", " ")),
    fam = fam, level = tonumber(lvl), t = GetTime(),
  }
  if PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then pcall(PlaySound, SOUNDKIT.TELL_MESSAGE) end
  ShowRequest()
end

-- /barter testrequest: shows the window with yourself as the sender.
local function TestRequest()
  local fam
  for _, f in ipairs({ "KINGS", "MIGHT", "WISDOM", "FORTITUDE", "INTELLECT", "WILD", "SPIRIT", "THORNS", "LIGHT" }) do
    if known[f] then fam = f break end
  end
  if not fam then Print(L.KNOWN_NONE) return end
  table.insert(incoming, 1, { short = UnitName("player"), fam = fam, level = UnitLevel("player"), t = GetTime(), self = true })
  ShowRequest()
end

------------------------------------------------------------------------
-- Demo scenes for screenshots (/barter demo <scene>). Everything here is
-- display only: invented players, no casting, no whispers are sent.
------------------------------------------------------------------------
do
  local demoFrames, demoPool = {}, {}
  local anchor = CreateFrame("Frame", nil, UIParent)
  anchor:SetSize(130, 16)
  anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 170)
  local anchor2 = CreateFrame("Frame", nil, UIParent)
  anchor2:SetSize(130, 16)
  anchor2:SetPoint("CENTER", UIParent, "CENTER", 0, 70)
  local statsMoved = false

  local DEMO_PLAYERS = {
    { name = "Mira Dawnfeather",  class = "PRIEST",  level = 60, state = "MISSING" },
    { name = "Thorin Ashbeard",   class = "WARRIOR", level = 58, state = "CAMP" },
    { name = "Selene Moonbrook",  class = "MAGE",    level = 60, state = "EXPIRING", left = 240 },
    { name = "Elowen Fairwind",   class = "DRUID",   level = 57, state = "DISPEL" },
    { name = "Garrick Holt",      class = "ROGUE",   level = 52, state = "SWAP" },
    { name = "Bram Ironvale",     class = "HUNTER",  level = 60, state = "PVP" },
    { name = "Pip Copperkettle",  class = "WARLOCK", level = 18, state = "MISSING", far = true },
  }
  local DEBUFF_ICON = {
    Magic   = "Interface\\Icons\\Spell_Frost_FrostNova",
    Curse   = "Interface\\Icons\\Spell_Shadow_CurseOfMannoroth",
    Disease = "Interface\\Icons\\Spell_Shadow_CallofBone",
    Poison  = "Interface\\Icons\\Spell_Nature_CorrosiveBreath",
  }

  local function FamName(fam)
    if known[fam] then return known[fam].name end
    local d = ns.BUFFS[fam]
    return (d and SpellInfo(d.ids[1])) or fam
  end
  local function FamIcon(fam)
    if known[fam] then return known[fam].icon end
    local d = ns.BUFFS[fam]
    if not d then return 134400 end
    local _, icon = SpellInfo(d.ids[1])
    if not icon and C_Spell and C_Spell.GetSpellTexture then icon = C_Spell.GetSpellTexture(d.ids[1]) end
    return icon or 134400
  end
  -- the buff you would hand out, and a second one for "swap"
  local function MyFams()
    local list = {}
    for _, f in ipairs({ "KINGS", "MIGHT", "WISDOM", "LIGHT", "FORTITUDE", "INTELLECT", "WILD", "SPIRIT", "THORNS" }) do
      if known[f] then list[#list + 1] = f end
    end
    if #list == 0 then list = { "KINGS", "MIGHT" } end
    return list[1], list[2] or list[1]
  end
  -- a debuff type you can actually remove
  local function MyDispelType()
    local _, myClass = UnitClass("player")
    for _, d in ipairs(ns.DISPELS[myClass] or {}) do
      for _, t in ipairs({ "Disease", "Curse", "Poison", "Magic" }) do
        if d.types[t] then return t end
      end
    end
    return "Disease"
  end
  local function PvPTex()
    return UnitFactionGroup("player") == "Horde" and "Interface\\TargetingFrame\\UI-PVP-Horde"
      or "Interface\\TargetingFrame\\UI-PVP-Alliance"
  end

  local function NewIcon(ask)
    local b = table.remove(demoPool) or CreateFrame("Frame", nil, UIParent)
    if not b.icon then
      b.border = b:CreateTexture(nil, "BACKGROUND")
      b.border:SetPoint("TOPLEFT", -2, 2)
      b.border:SetPoint("BOTTOMRIGHT", 2, -2)
      b.icon = b:CreateTexture(nil, "ARTWORK")
      b.icon:SetAllPoints()
      b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
      b.pvp = b:CreateTexture(nil, "OVERLAY", nil, 7)
      b.pvp:SetTexCoord(0, 0.62, 0, 0.62)
    end
    local size = ask and math.floor(db.size * 0.85) or db.size
    b:SetSize(size, size)
    b:SetFrameStrata("MEDIUM")
    b.pvp:SetSize(math.floor(db.size * 0.9), math.floor(db.size * 0.9))
    b.pvp:ClearAllPoints()
    b.pvp:SetPoint("CENTER", b, "TOPRIGHT", -2, -2)
    b.pvp:Hide()
    b.label:SetText("")
    b:ClearAllPoints()
    b:SetAlpha(1)
    b:Show()
    demoFrames[#demoFrames + 1] = b
    return b
  end

  -- kind: MISSING, CAMP, EXPIRING, SWAP, DISPEL, PVP, ASK
  local function StyleIcon(b, kind)
    local fam, other = MyFams()
    local c
    if kind == "DISPEL" then
      local t = MyDispelType()
      b.icon:SetTexture(DEBUFF_ICON[t])
      c = { DispelColor(t) }
      b.label:SetText(L["DISPEL_" .. t] or t); b.label:SetTextColor(DispelColor(t))
    elseif kind == "ASK" then
      local _, myClass = UnitClass("player")
      local askFam = (myClass == "PRIEST") and "INTELLECT" or "FORTITUDE"
      b.icon:SetTexture(FamIcon(askFam))
      c = { 0.2, 0.8, 1 }
      b.label:SetText(L.REQ_LABEL); b.label:SetTextColor(0.4, 0.85, 1)
    else
      b.icon:SetTexture(FamIcon(kind == "SWAP" and other or fam))
      if kind == "PVP" then
        c = { 1, 0.1, 0.1 }
        b.pvp:SetTexture(PvPTex()); b.pvp:Show()
        b.label:SetText(L.PVP_LABEL); b.label:SetTextColor(1, 0.25, 0.25)
      else
        c = STATE_COLOR[kind] or STATE_COLOR.MISSING
        if kind == "CAMP" then b.label:SetText(L.CAMP); b.label:SetTextColor(1, 0.5, 0)
        elseif kind == "EXPIRING" then b.label:SetText("4m"); b.label:SetTextColor(1, 0.85, 0)
        elseif kind == "SWAP" then b.label:SetText(L.SWAP); b.label:SetTextColor(0.7, 0.3, 1) end
      end
    end
    b.border:SetColorTexture(c[1], c[2], c[3], 0.9)
  end

  -- Your target's nameplate if there is one, else a spot above your character.
  local function Plate()
    local p = UnitExists("target") and C_NamePlate.GetNamePlateForUnit("target")
    if p and not (p.IsForbidden and p:IsForbidden()) then return p end
    return anchor
  end

  local function ShowOnPlate(kind, withAsk, fallback)
    local plate = Plate()
    if plate == anchor and fallback then plate = fallback end
    local b = NewIcon()
    StyleIcon(b, kind)
    b:SetPoint("CENTER", plate, "CENTER", 0, db.offset)
    if withAsk then
      local a = NewIcon(true)
      StyleIcon(a, "ASK")
      a:SetPoint("LEFT", plate, "RIGHT", 2, db.offset)
    end
  end

  local function ShowLegend(fixed)
    local plate = fixed and anchor or Plate()
    local kinds = { "MISSING", "CAMP", "EXPIRING", "SWAP", "DISPEL", "PVP", "ASK" }
    local step = db.size + 30
    for i, k in ipairs(kinds) do
      local b = NewIcon(k == "ASK")
      StyleIcon(b, k)
      b:SetPoint("CENTER", plate, "CENTER", (i - (#kinds + 1) / 2) * step, db.offset)
    end
  end

  local function FillList(onlyPvP, onlyDispel, folded)
    local fam, other = MyFams()
    local _, myClass = UnitClass("player")
    local rows = {}
    rows[#rows + 1] = { name = L.QUEUE_YOU, class = myClass, level = UnitLevel("player"), state = "MISSING" }
    for _, p in ipairs(DEMO_PLAYERS) do rows[#rows + 1] = p end
    for i = 1, QUEUE_ROWS do
      local r, e = queue.rows[i], rows[i]
      r:SetAttribute("macrotext", nil)
      r.unit, r.fam, r.disp, r.pvpFlag, r.needsArm = nil, nil, nil, nil, nil
      if e and not folded then
        local pvp = e.state == "PVP"
        r.bg:SetColorTexture(pvp and 0.6 or 1, pvp and 0.05 or 1, pvp and 0.05 or 1,
          pvp and 0.25 or ((i % 2 == 0) and 0.05 or 0.02))
        if e.state == "DISPEL" then
          local t = MyDispelType()
          r.icon:SetTexture(DEBUFF_ICON[t])
          r.tag:SetText(L["DISPEL_" .. t] or t); r.tag:SetTextColor(DispelColor(t))
        else
          r.icon:SetTexture(FamIcon(e.state == "SWAP" and other or fam))
          if pvp then r.tag:SetText(L.PVP_ARM); r.tag:SetTextColor(1, 0.25, 0.25)
          elseif e.state == "CAMP" then r.tag:SetText(L.CAMP); r.tag:SetTextColor(1, 0.5, 0)
          elseif e.state == "EXPIRING" then r.tag:SetText(("%dm"):format(e.left / 60)); r.tag:SetTextColor(1, 0.85, 0)
          elseif e.state == "SWAP" then r.tag:SetText(L.SWAP); r.tag:SetTextColor(0.7, 0.3, 1)
          else r.tag:SetText("") end
        end
        r.name:SetText(e.name .. "  |cff8a8a8a" .. (e.level or "") .. "|r")
        r.name:SetTextColor(ClassRGB(e.class))
        local dim = e.far or (onlyPvP and not pvp and i > 1) or (onlyDispel and e.state ~= "DISPEL" and i > 1)
        r:SetAlpha(dim and 0.4 or 1)
        r:Show()
      else
        r:Hide()
      end
    end
    local n = folded and 0 or math.min(#rows, QUEUE_ROWS)
    queue.title:SetText(folded and ("BuffBarter  |cffffffff" .. #rows .. "|r  |cff8a8a8a" .. L.QUEUE_CITY_TAG .. "|r")
      or ("BuffBarter  |cffffffff" .. #rows .. "|r"))
    queue.toggle:SetNormalTexture(folded and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
    queue.eye.tex:SetDesaturated(folded); queue.eye:SetAlpha(folded and 0.5 or 1)
    queue.ask.tex:SetDesaturated(folded); queue.ask:SetAlpha(folded and 0.5 or 1)
    queue.empty:SetText("")
    queue:SetHeight(folded and 20 or (26 + n * ROW_H))
    queue:Show()
  end

  -- a second, folded list as it looks in a capital city
  local mini
  local function ShowCityMini()
    if not mini then
      mini = CreateFrame("Frame", nil, UIParent)
      mini:SetSize(210, 20)
      mini.bg = mini:CreateTexture(nil, "BACKGROUND"); mini.bg:SetAllPoints()
      mini.bg:SetColorTexture(0.05, 0.07, 0.1, 0.75)
      mini.edge = mini:CreateTexture(nil, "BORDER")
      mini.edge:SetPoint("TOPLEFT"); mini.edge:SetPoint("TOPRIGHT"); mini.edge:SetHeight(2)
      mini.edge:SetColorTexture(0.95, 0.75, 0.25, 0.9)
      mini.title = mini:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      mini.title:SetPoint("TOPLEFT", 8, -6)
      local function Tex(path, x, crop)
        local t = mini:CreateTexture(nil, "ARTWORK")
        t:SetSize(16, 16); t:SetPoint("TOPRIGHT", x, -2); t:SetTexture(path)
        if crop then t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        return t
      end
      mini.plus = Tex("Interface\\Buttons\\UI-PlusButton-Up", -4)
      mini.eye = Tex("Interface\\Icons\\INV_Misc_Eye_01", -24, true)
      mini.ask = Tex("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up", -44)
      mini.eye:SetDesaturated(true); mini.eye:SetAlpha(0.5)
      mini.ask:SetDesaturated(true); mini.ask:SetAlpha(0.5)
    end
    mini.title:SetText("BuffBarter  |cffffffff7|r  |cff8a8a8a" .. L.QUEUE_CITY_TAG .. "|r")
    mini:ClearAllPoints()
    mini:SetPoint("TOPLEFT", queue, "TOPRIGHT", 16, 0)
    mini:Show()
    demoFrames[#demoFrames + 1] = mini
  end

  local function ShowStatsDemo()
    if not ns.ShowStats then return end
    local f = _G.BuffBarterStatsFrame
    if not (f and f:IsShown()) then ns.ShowStats() end
    f = _G.BuffBarterStatsFrame
    if f then
      f:ClearAllPoints()
      f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 0)
      statsMoved = true
    end
  end

  local function ChatLine(text, r, g, b)
    DEFAULT_CHAT_FRAME:AddMessage(text, r, g, b)
  end
  local function Whisper(to, text)
    local c = ChatTypeInfo and ChatTypeInfo.WHISPER_INFORM or { r = 1, g = 0.5, b = 1 }
    local fmt = CHAT_WHISPER_INFORM_GET or "To %s: "
    ChatLine(fmt:format("[" .. to .. "]") .. text, c.r, c.g, c.b)
  end
  local function Fill(key, sub)
    local text = Template(db.myLang, key)
    if not text or strtrim(text) == "" then text = ns.DEFAULT_TEMPLATES.en[key] or "" end
    return (text:gsub("{(%w+)}", function(k) return sub[k] or "" end))
  end
  local function Named(fam)
    local names = ns.BUFF_NAMES[db.myLang] or ns.BUFF_NAMES.en
    local n = names[fam] or FamName(fam)
    if db.useLinks then n = SpellLink(FamilySpellID(fam)) or n end
    return n
  end
  local function ShowWhispers()
    local fam = MyFams()
    local _, myClass = UnitClass("player")
    local me = UnitName("player") or ""
    -- ask back after buffing a priest
    local askBack = Fill("PRIEST", { name = "Mira", buff = Named(fam), ask = Named("FORTITUDE"), me = me })
    Whisper("Mira Dawnfeather", askBack)
    -- one click request to a mage
    local askFam = (myClass == "MAGE") and "FORTITUDE" or "INTELLECT"
    Whisper("Selene Moonbrook", Fill("REQUEST", { name = "Selene", ask = Named(askFam), buff = Named(askFam), me = me }))
    -- automatic thanks
    Whisper("Mira Dawnfeather", Fill("THANKS", { name = "Mira", buff = Named("FORTITUDE"), me = me }))
  end

  local function ShowPvPChat()
    Print("|cffff4040" .. L.PVP_ARMED:format("Bram Ironvale", ARM_TIME) .. "|r")
  end

  local function ShowPopup()
    local fam = MyFams()
    if not known[fam] then Print(L.KNOWN_NONE) return end
    table.insert(incoming, 1, { short = "Thorin Ashbeard", fam = fam, level = 58,
                                t = GetTime() + 3600, self = true, demo = true })
    ShowRequest()
  end

  local function Clear()
    for _, b in ipairs(demoFrames) do
      b:Hide(); b:ClearAllPoints()
      if b ~= mini then demoPool[#demoPool + 1] = b end
    end
    wipe(demoFrames)
    local f = _G.BuffBarterStatsFrame
    if statsMoved and f then
      f:Hide(); f:ClearAllPoints(); f:SetPoint("CENTER")
      statsMoved = false
    end
    for i = #incoming, 1, -1 do if incoming[i].demo then table.remove(incoming, i) end end
    ShowRequest()
  end

  local SCENES = {
    list    = function() FillList() end,
    icons   = function() ShowLegend() end,
    ask     = function() ShowOnPlate("MISSING", true) end,
    pvp     = function() ShowOnPlate("PVP"); FillList(true); ShowPvPChat() end,
    dispel  = function() ShowOnPlate("DISPEL"); FillList(false, true) end,
    whisper = function() ShowWhispers() end,
    request = function() ShowPopup() end,
    city    = function() FillList(false, false, true) end,
    -- everything at once, laid out so the parts do not overlap
    all     = function()
      ShowLegend(true)
      ShowOnPlate("MISSING", true, anchor2)
      FillList()
      ShowCityMini()
      ShowPopup()
      ShowWhispers()
      ShowPvPChat()
      ShowStatsDemo()
    end,
  }

  function ns.Demo(scene)
    if InCombatLockdown() then Print(L.COMBAT_WAIT) return end
    scene = scene or ""
    if scene == "off" then
      ns.demo = nil
      Clear()
      UpdateQueue()
      Print(L.DEMO_OFF)
      return
    end
    local fn = SCENES[scene]
    if not fn then
      for _, l in ipairs(L.DEMO_HELP) do print(l) end
      return
    end
    Clear()
    ns.demo = nil
    UpdateQueue() -- real list back first, then the scene paints over it
    ns.demo = scene
    fn()
    Print(L.DEMO_ON:format(scene))
  end
end

------------------------------------------------------------------------
-- Cleanup: remove the macro left over from the click casting experiment
------------------------------------------------------------------------
local function RemoveOldMacro()
  if InCombatLockdown() then return end
  local idx = GetMacroIndexByName("BuffMePLS")
  if idx and idx > 0 then DeleteMacro(idx) end
end

------------------------------------------------------------------------
-- Status line in the normal unit tooltip (our icons are click-through)
------------------------------------------------------------------------
local STATE_TEXT = { MISSING = "STATE_MISSING", CAMP = "STATE_CAMP", EXPIRING = "STATE_EXPIRING" }
local function AddTooltipLine(tooltip)
  if not Active() or tooltip ~= GameTooltip then return end
  if not SmartEligible("mouseover") then return end
  local ok, fam, state, myFam = pcall(Decide, "mouseover")
  if not ok or not fam or not known[fam] then return end
  local c = STATE_COLOR[state] or { 1, 1, 1 }
  local txt = state == "SWAP" and L.STATE_SWAP:format(known[myFam] and known[myFam].name or "?") or L[STATE_TEXT[state]]
  tooltip:AddLine("BuffBarter: " .. known[fam].name, 0.2, 0.8, 1)
  tooltip:AddLine(txt, state == "MISSING" and 0.8 or c[1], state == "MISSING" and 0.8 or c[2], state == "MISSING" and 0.8 or c[3])
end
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, AddTooltipLine)
else
  GameTooltip:HookScript("OnTooltipSetUnit", AddTooltipLine)
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local BuildOptions -- defined at the end of the file

local function ApplyBinding()
  if InCombatLockdown() then return end
  ClearOverrideBindings(ev)
  if db.bindKey then
    SetOverrideBindingClick(ev, true, db.bindKey, "BuffBarterSmartButton", "LeftButton")
  end
  if db.nextKey then
    SetOverrideBindingClick(ev, true, db.nextKey, "BuffBarterNextButton", "LeftButton")
  end
end
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, arg1, ...)
  if event == "PLAYER_LOGIN" then
    InitDB()
    BuildSpells()
    self:RegisterEvent("SPELLS_CHANGED")
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    self:RegisterEvent("UNIT_AURA")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("ADDON_ACTION_BLOCKED")
    self:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    self:RegisterEvent("UI_ERROR_MESSAGE")
    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    self:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("ZONE_CHANGED")
    self:RegisterEvent("CHAT_MSG_ADDON")
    ApplyBinding()
    RemoveOldMacro()
    self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    if BuildOptions then BuildOptions() end
    RestoreQueuePosition()
    if ns.UpdateMinimap then ns.UpdateMinimap() end
    C_Timer.NewTicker(0.5, function()
      RefreshAll(); UpdateSmart(); UpdateQueue()
      if popup:IsShown() or (#incoming > 0 and not InCombatLockdown()) then ShowRequest() end -- expire or resume
    end)
    Print(L.LOADED)
  elseif event == "SPELLS_CHANGED" then
    BuildSpells()
    RebuildAll()
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    Refresh(arg1)
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    if InCombatLockdown() then pendingRebuild = true else ReleaseBoth(arg1) end
  elseif event == "CHAT_MSG_ADDON" then
    OnAddonMessage(arg1, ...)
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    OnOwnCast(select(2, ...))
  elseif event == "UNIT_AURA" then
    if arg1 == "player" then OnPlayerAura(...) end
    if arg1 and arg1:match("^nameplate%d+$") then Refresh(arg1) end
    if arg1 == "target" or arg1 == "mouseover" then UpdateSmart() end
  elseif event == "PLAYER_TARGET_CHANGED" then
    RefreshAll(); UpdateSmart()
  elseif event == "UPDATE_MOUSEOVER_UNIT" then
    UpdateSmart()
  elseif event == "PLAYER_REGEN_ENABLED" then
    if pendingRebuild then RebuildAll() end
    ApplyBinding(); UpdateSmart(); UpdateQueue()
  elseif event == "GROUP_ROSTER_UPDATE" then
    RebuildAll()
  elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
    CheckCityChange()
    RebuildAll(); UpdateSmart(); UpdateQueue()
  elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    if db.debug then Print(("%s: %s  %s"):format(event, tostring(arg1), tostring(select(1, ...) or ""))) end
  elseif event == "UI_ERROR_MESSAGE" then
    if db.debug then Print("UI error: " .. tostring(select(1, ...))) end
  end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
local function FamilyList()
  local t = {}
  for fam in pairs(ns.BUFFS) do t[#t + 1] = fam end
  table.sort(t)
  return table.concat(t, ", ")
end

local function Scan()
  local unit = UnitExists("target") and "target" or "player"
  local who = UnitName(unit) or unit
  local lines, now = {}, GetTime()
  local ok = pcall(ForEachBuff, unit, function(name, id, src, exp)
    local from = src and (UnitName(src) or src) or "?"
    local left = (exp and exp > 0) and ("%dm"):format(math.floor((exp - now) / 60)) or ""
    local tag = ""
    if id and idToFamily[id] then tag = "[" .. idToFamily[id] .. "]"
    elseif CampFamily(id) then tag = "[" .. L.CAMP .. ":" .. CampFamily(id) .. "]" end
    lines[#lines + 1] = L.SCAN_LINE:format(tostring(name), tostring(id), from, left .. " " .. tag)
  end)
  if not ok or #lines == 0 then Print(L.SCAN_NONE:format(who)) return end
  Print(L.SCAN_HEADER:format(who))
  for _, l in ipairs(lines) do print("   " .. l) end
  print("   " .. L.SCAN_HINT)
end

SLASH_BUFFBARTER1 = "/barter"
SLASH_BUFFBARTER2 = "/buffbarter"
SlashCmdList.BUFFBARTER = function(msg)
  local cmd, a, b = strsplit(" ", strtrim(msg or ""):lower())
  if cmd == "" or cmd == "options" or cmd == "config" then
    ns.OpenSettings()
  elseif cmd == "demo" then
    ns.Demo(a)
  elseif cmd == "testrequest" then
    if InCombatLockdown() then Print(L.COMBAT_WAIT) return end
    TestRequest()
  elseif cmd == "where" then
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    Print(("map %s, zone %s, city: %s"):format(tostring(mapID), tostring(GetRealZoneText()), tostring(InCity())))
  elseif cmd == "icons" then
    if InCombatLockdown() then Print(L.COMBAT_WAIT) return end
    db.plateIcons = not db.plateIcons
    RebuildAll()
  elseif cmd == "list" then
    if InCombatLockdown() then Print(L.COMBAT_WAIT) return end
    db.showQueue = not db.showQueue
    UpdateQueue()
  elseif cmd == "minimap" then
    db.minimap = not db.minimap
    if ns.UpdateMinimap then ns.UpdateMinimap() end
  elseif cmd == "toggle" then
    if InCombatLockdown() then Print(L.COMBAT_WAIT) return end
    db.enabled = not db.enabled
    Print(db.enabled and L.ENABLED or L.DISABLED)
    RebuildAll()
  elseif cmd == "help" then
    for _, l in ipairs(L.HELP) do print(l) end
  elseif cmd == "scan" then
    Scan()
  elseif cmd == "spells" then
    if not next(known) then Print(L.KNOWN_NONE) return end
    Print(L.KNOWN_HEADER)
    for fam, k in pairs(known) do
      local parts = {}
      for _, r in ipairs(k.ranks or {}) do
        parts[#parts + 1] = ("%s L%d"):format(r.sub or "?", r.level)
      end
      print(("   %s: %s  %s"):format(fam, k.name, table.concat(parts, ", ")))
    end
  elseif cmd == "camp" then
    local fam, id = a and a:upper(), tonumber(b)
    if not fam or not ns.BUFFS[fam] or not id then Print(L.CAMP_BAD:format(FamilyList())) return end
    db.campIDs[id] = fam
    Print(L.CAMP_ADDED:format(id, fam))
    RebuildAll()
  elseif cmd == "friendly" then
    if InCombatLockdown() then Print(L.COMBAT_WAIT) return end
    SetCVar("nameplateShowFriends", "1")
    Print(L.FRIENDLY_ON)
  elseif cmd == "bind" then
    if InCombatLockdown() then Print(L.COMBAT_WAIT) return end
    if not a or a == "" then Print(L.BIND_USAGE) return end
    db.bindKey = a:upper()
    ApplyBinding()
    Print(L.BIND_SET:format(db.bindKey))
  elseif cmd == "bindnext" then
    if InCombatLockdown() then Print(L.COMBAT_WAIT) return end
    if not a or a == "" then Print(L.NEXT_USAGE) return end
    db.nextKey = a:upper()
    ApplyBinding()
    Print(L.NEXT_SET:format(db.nextKey))
  elseif cmd == "unbindnext" then
    if InCombatLockdown() then Print(L.COMBAT_WAIT) return end
    db.nextKey = nil
    ApplyBinding()
    Print(L.BIND_CLEARED)
  elseif cmd == "unbind" then
    if InCombatLockdown() then Print(L.COMBAT_WAIT) return end
    db.bindKey = nil
    ApplyBinding()
    Print(L.BIND_CLEARED)
  elseif cmd == "stats" then
    if ns.ShowStats then ns.ShowStats() end
  elseif cmd == "preview" then
    if not (UnitExists("target") and UnitIsPlayer("target")) then Print(L.NEED_TARGET) return end
    local full, short, realm = FullName("target")
    local _, class = UnitClass("target")
    local fam = Decide("target") or "KINGS"
    local text, lang = BuildAsk(full, short, realm, class, fam, UnitLevel("target"))
    if text then Print(L.PREVIEW:format(full, lang, text)) else Print(L.PREVIEW_NONE:format(full)) end
  elseif cmd == "lang" then
    if not (UnitExists("target") and UnitIsPlayer("target")) then Print(L.NEED_TARGET) return end
    if a ~= "de" and a ~= "en" then Print(L.LANG_USAGE) return end
    local full = FullName("target")
    db.playerLang[full] = a
    Print(L.LANG_SET:format(full, L["LANG_" .. a]))
  elseif cmd == "debug" then
    db.debug = not db.debug
    Print("debug " .. (db.debug and L.ENABLED or L.DISABLED))
  elseif cmd == "strangers" then
    db.strangers = not db.strangers
    Print(db.strangers and L.STRANGERS_ON or L.STRANGERS_OFF)
    RebuildAll()
  elseif cmd == "reset" then
    if InCombatLockdown() then Print(L.COMBAT_WAIT) return end
    BuffBarterDB = nil
    InitDB()
    Print(L.RESET_DONE)
    RebuildAll()
  else
    for _, l in ipairs(L.HELP) do print(l) end
  end
end

------------------------------------------------------------------------
-- Statistics window (/barter stats)
------------------------------------------------------------------------
local statsFrame

local CLASS_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local RACE_ATLAS = { Scourge = "undead", NightElf = "nightelf", BloodElf = "bloodelf" }

local function HasAtlas(name)
  return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function SetClassIcon(tex, class)
  tex:SetTexCoord(0, 1, 0, 1)
  local atlas = class and ("classicon-" .. class:lower())
  if atlas and HasAtlas(atlas) then tex:SetAtlas(atlas) return end
  if class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class] then
    tex:SetTexture(CLASS_TEX)
    tex:SetTexCoord(unpack(CLASS_ICON_TCOORDS[class]))
    return
  end
  tex:SetTexture(134400) -- question mark
end

local function SetRaceIcon(tex, race)
  tex:SetTexCoord(0, 1, 0, 1)
  local key = race and (RACE_ATLAS[race] or race:lower())
  for _, atlas in ipairs({ key and ("raceicon-" .. key .. "-male"), key and ("raceicon128-" .. key .. "-male") }) do
    if atlas and HasAtlas(atlas) then tex:SetAtlas(atlas) return end
  end
  tex:SetTexture(134400)
end

local function SetBuffIcon(tex, fam)
  tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local _, icon = SpellInfo(FamilySpellID(fam))
  tex:SetTexture(icon or 134400)
end

local function ClassColor(c)
  local col = c and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c]
  if col then return col.r, col.g, col.b end
  return 0.85, 0.85, 0.85
end

local function ClassName(c)
  return c and ((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c]) or c) or L.UNKNOWN
end

local function BuffLabel(f)
  local names = ns.BUFF_NAMES[db.myLang] or ns.BUFF_NAMES.en
  return names[f] or f
end

local function Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

-- Union of keys from given/received, sorted by total activity.
local function Merged(g, r, limit)
  local arr, seen = {}, {}
  for _, t in ipairs({ g or {}, r or {} }) do
    for k in pairs(t) do
      if not seen[k] then
        seen[k] = true
        arr[#arr + 1] = { k = k, g = (g and g[k]) or 0, r = (r and r[k]) or 0 }
      end
    end
  end
  table.sort(arr, function(x, y) return (x.g + x.r) > (y.g + y.r) end)
  if limit then for i = #arr, limit + 1, -1 do arr[i] = nil end end
  return arr
end

local GOLD = { 0.95, 0.75, 0.25 }
local BLUE = { 0.30, 0.75, 1.00 }
local ROW_W, BAR_X, BAR_W = 420, 170, 170

local function BuildStatsFrame()
  local f = CreateFrame("Frame", "BuffBarterStatsFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(470, 620)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -5)
  title:SetText(L.STATS_TITLE)

  -- summary tiles
  f.tiles = {}
  for i = 1, 4 do
    local t = CreateFrame("Frame", nil, f)
    t:SetSize(103, 58)
    t:SetPoint("TOPLEFT", 12 + (i - 1) * 110, -30)
    t.bg = t:CreateTexture(nil, "BACKGROUND")
    t.bg:SetAllPoints()
    t.bg:SetColorTexture(1, 1, 1, 0.06)
    t.edge = t:CreateTexture(nil, "BORDER")
    t.edge:SetPoint("TOPLEFT"); t.edge:SetPoint("TOPRIGHT"); t.edge:SetHeight(3)
    t.big = t:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    t.big:SetPoint("TOP", 0, -8)
    t.label = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.label:SetPoint("TOP", t.big, "BOTTOM", 0, -2)
    t.sub = t:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    t.sub:SetPoint("TOP", t.label, "BOTTOM", 0, -1)
    f.tiles[i] = t
  end

  local legend = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  legend:SetPoint("TOPLEFT", 14, -96)
  legend:SetText(L.STATS_LEGEND)

  local sc = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  sc:SetPoint("TOPLEFT", 12, -114)
  sc:SetPoint("BOTTOMRIGHT", -32, 42)
  local child = CreateFrame("Frame", nil, sc)
  child:SetSize(ROW_W, 10)
  sc:SetScrollChild(child)
  f.child = child
  f.rows, f.heads = {}, {}

  f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.footer:SetPoint("BOTTOMRIGHT", -14, 18)
  f.footer:SetPoint("LEFT", f, "BOTTOMLEFT", 162, 0)
  f.footer:SetJustifyH("RIGHT")

  local reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  reset:SetSize(140, 22)
  reset:SetPoint("BOTTOMLEFT", 14, 12)
  reset:SetText(L.STATS_RESET)
  reset:SetScript("OnClick", function()
    if IsShiftKeyDown() then
      db.stats[UnitName("player") or "?"] = nil
      f:Refresh()
    else
      Print(L.STATS_RESET_HINT)
    end
  end)

  function f:Head(i, text, y)
    local h = self.heads[i]
    if not h then
      h = self.child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      self.heads[i] = h
    end
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", 2, y)
    h:SetText(text)
    h:Show()
  end

  function f:Row(i, y)
    local r = self.rows[i]
    if not r then
      r = CreateFrame("Frame", nil, self.child)
      r:SetSize(ROW_W, 22)
      r.bg = r:CreateTexture(nil, "BACKGROUND")
      r.bg:SetAllPoints()
      r.icon = r:CreateTexture(nil, "ARTWORK")
      r.icon:SetSize(18, 18)
      r.icon:SetPoint("LEFT", 2, 0)
      r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
      r.name:SetWidth(BAR_X - 30)
      r.name:SetJustifyH("LEFT")
      r.name:SetWordWrap(false)
      r.barG = r:CreateTexture(nil, "ARTWORK")
      r.barG:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
      r.barG:SetHeight(7)
      r.barG:SetPoint("TOPLEFT", BAR_X, -3)
      r.barR = r:CreateTexture(nil, "ARTWORK")
      r.barR:SetColorTexture(BLUE[1], BLUE[2], BLUE[3], 0.9)
      r.barR:SetHeight(7)
      r.barR:SetPoint("BOTTOMLEFT", BAR_X, 3)
      r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      r.count:SetPoint("RIGHT", -4, 0)
      r.count:SetJustifyH("RIGHT")
      self.rows[i] = r
    end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, y)
    r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.05 or 0.02)
    r:Show()
    return r
  end

  function f:Refresh()
    local st = CharStats()
    local g, r, a = st.given, st.received, st.asks

    -- tiles
    local back, buffedUnique = 0, Count(g.players)
    for full in pairs(g.players) do if r.players[full] then back = back + 1 end end
    local asked = (a.afterBuff or 0) + (a.requests or 0)
    local function pct(x, y) return y > 0 and math.floor(x * 100 / y + 0.5) or 0 end
    local tiles = {
      { g.total, L.STATS_TILE_GIVEN, (buffedUnique == 1 and L.STATS_PLAYER or L.STATS_PLAYERS):format(buffedUnique), GOLD },
      { r.total, L.STATS_TILE_RECEIVED, (Count(r.players) == 1 and L.STATS_PLAYER or L.STATS_PLAYERS):format(Count(r.players)), BLUE },
      { pct(back, buffedUnique) .. "%", L.STATS_TILE_BACK, L.STATS_OF:format(back, buffedUnique), { 0.45, 0.9, 0.45 } },
      { pct(a.answered or 0, asked) .. "%", L.STATS_TILE_ANSWER, L.STATS_OF:format(a.answered or 0, asked), { 0.8, 0.55, 1 } },
    }
    for i, t in ipairs(tiles) do
      local tile = self.tiles[i]
      tile.big:SetText(t[1])
      tile.big:SetTextColor(t[4][1], t[4][2], t[4][3])
      tile.edge:SetColorTexture(t[4][1], t[4][2], t[4][3], 0.9)
      tile.label:SetText(t[2])
      tile.sub:SetText(t[3])
    end

    for _, row in ipairs(self.rows) do row:Hide() end
    for _, h in ipairs(self.heads) do h:Hide() end
    local y, ri, hi = -2, 0, 0

    local function section(title, arr, setIcon, label, color)
      hi = hi + 1
      self:Head(hi, title, y)
      y = y - 20
      if #arr == 0 then
        ri = ri + 1
        local row = self:Row(ri, y)
        row.icon:SetTexture(nil)
        row.name:SetText(L.STATS_NONE_SHORT)
        row.name:SetTextColor(0.6, 0.6, 0.6)
        row.barG:Hide(); row.barR:Hide(); row.count:SetText("")
        y = y - 24
        return
      end
      local max = 1
      for _, e in ipairs(arr) do max = math.max(max, e.g, e.r) end
      for _, e in ipairs(arr) do
        ri = ri + 1
        local row = self:Row(ri, y)
        setIcon(row.icon, e.k)
        row.name:SetText(label(e.k))
        row.name:SetTextColor(color(e.k))
        row.barG:SetShown(e.g > 0); row.barG:SetWidth(math.max(1, BAR_W * e.g / max))
        row.barR:SetShown(e.r > 0); row.barR:SetWidth(math.max(1, BAR_W * e.r / max))
        row.count:SetText(("|cfff2bf40%d|r  |cff4dbfff%d|r"):format(e.g, e.r))
        y = y - 24
      end
      y = y - 8
    end

    local white = function() return 1, 1, 1 end
    section(L.STATS_BY_CLASS, Merged(g.classes, r.classes), SetClassIcon, ClassName, ClassColor)
    section(L.STATS_BY_RACE, Merged(g.races, r.races, 10), SetRaceIcon,
      function(k) return st.raceNames[k] or k end, white)
    section(L.STATS_BY_BUFF, Merged(g.buffs, r.buffs), SetBuffIcon, BuffLabel, white)
    section(L.STATS_TOP, Merged(g.players, r.players, 10),
      function(tex, full) SetClassIcon(tex, st.playerClass[full]) end,
      function(full) return (full:gsub("%-", " ")) end,
      function(full) return ClassColor(st.playerClass[full]) end)

    self.child:SetHeight(-y + 10)
    self.footer:SetText(L.STATS_FOOTER:format(r.camp or 0, date("%d.%m.%Y", st.since)))
  end

  -- Close directly instead of through the template's panel logic, which
  -- does not work reliably in combat.
  local close = f.CloseButton or _G["BuffBarterStatsFrameCloseButton"]
  if close then close:SetScript("OnClick", function() f:Hide() end) end
  tinsert(UISpecialFrames, "BuffBarterStatsFrame") -- Esc closes it
  return f
end

local function ShowStats()
  if statsFrame and statsFrame:IsShown() then statsFrame:Hide() return end -- toggle
  statsFrame = statsFrame or BuildStatsFrame()
  statsFrame:Refresh()
  statsFrame:Show()
end
ns.ShowStats = ShowStats

------------------------------------------------------------------------
-- Minimap icon: left click settings, right click statistics,
-- shift-click shows or hides the buff list. Drag to move it.
------------------------------------------------------------------------
function ns.OpenSettings()
  if ns.settingsCategory and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(ns.settingsCategory:GetID())
  end
end

local mm
local function PlaceMinimapButton()
  local angle = math.rad(db.minimapAngle or 210)
  local r = (Minimap:GetWidth() / 2) + 5
  mm:ClearAllPoints()
  mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

function ns.UpdateMinimap()
  if not mm then
    mm = CreateFrame("Button", "BuffBarterMinimapButton", Minimap)
    mm:SetSize(31, 31)
    mm:SetFrameStrata("MEDIUM")
    mm:SetFrameLevel(8)
    mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mm:RegisterForDrag("LeftButton")
    mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = mm:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = mm:CreateTexture(nil, "ARTWORK")
    icon:SetSize(19, 19)
    icon:SetPoint("TOPLEFT", 6, -6)
    icon:SetTexture("Interface\\AddOns\\BuffBarter\\Media\\icon")
    local border = mm:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    mm:SetScript("OnClick", function(self, button)
      if button == "RightButton" then
        if ns.ShowStats then ns.ShowStats() end
      elseif IsShiftKeyDown() then
        if InCombatLockdown() then Print(L.COMBAT_WAIT) return end
        db.showQueue = not db.showQueue
        UpdateQueue()
      else
        ns.OpenSettings()
      end
    end)
    mm:SetScript("OnDragStart", function(self)
      self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
        PlaceMinimapButton()
      end)
    end)
    mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mm:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine("BuffBarter")
      GameTooltip:AddLine(L.MM_LEFT, 1, 1, 1)
      GameTooltip:AddLine(L.MM_RIGHT, 1, 1, 1)
      GameTooltip:AddLine(L.MM_SHIFT, 1, 1, 1)
      GameTooltip:AddLine(L.MM_DRAG, 0.6, 0.6, 0.6)
      GameTooltip:Show()
    end)
    mm:SetScript("OnLeave", GameTooltip_Hide)
  end
  PlaceMinimapButton()
  mm:SetShown(db.minimap and true or false)
end

------------------------------------------------------------------------
-- Settings panel (Esc > Options > AddOns > BuffBarter, or /barter)
------------------------------------------------------------------------
BuildOptions = function()
  if ns.settingsCategory then return end
  local panel = CreateFrame("Frame")
  panel.name = "BuffBarter"

  local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -4)
  scroll:SetPoint("BOTTOMRIGHT", -28, 4)
  local c = CreateFrame("Frame", nil, scroll)
  c:SetSize(620, 1000)
  scroll:SetScrollChild(c)

  local y = -8
  local function Text(text, font, height)
    local fs = c:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", 10, y)
    fs:SetWidth(580)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    y = y - (height or 20)
    return fs
  end
  local function Header(text) y = y - 8; Text(text, "GameFontNormalLarge", 28) end

  local function Check(label, key, after)
    local cb = CreateFrame("CheckButton", nil, c, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", 6, y)
    local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    fs:SetText(label)
    cb:SetChecked(db[key] and true or false)
    cb:SetScript("OnClick", function(self)
      db[key] = self:GetChecked() and true or false
      if after then after() end
    end)
    y = y - 28
  end

  local function Input(label, getter, setter)
    Text(label, "GameFontHighlightSmall", 16)
    local eb = CreateFrame("EditBox", nil, c, "InputBoxTemplate")
    eb:SetAutoFocus(false)
    eb:SetSize(570, 22)
    eb:SetPoint("TOPLEFT", 16, y)
    eb:SetMaxLetters(255)
    eb:SetText(getter() or "")
    eb:SetCursorPosition(0)
    local function save(self)
      if self:GetText() ~= (getter() or "") then setter(self:GetText()) end
    end
    eb:SetScript("OnEnterPressed", function(self) save(self); self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", save)
    eb:SetScript("OnEscapePressed", function(self) self:SetText(getter() or ""); self:ClearFocus() end)
    eb.getter = getter
    y = y - 32
    return eb
  end

  -- Plain slider (no template needed). fmt gets the value text via %s.
  local function Slider(fmt, key, minV, maxV, valueText, after)
    local label = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 12, y)
    local sl = CreateFrame("Slider", nil, c)
    sl:SetOrientation("HORIZONTAL")
    sl:SetSize(320, 16)
    sl:SetPoint("TOPLEFT", 14, y - 20)
    sl:SetMinMaxValues(minV, maxV)
    sl:SetValueStep(1)
    sl:SetObeyStepOnDrag(true)
    sl:EnableMouse(true)
    sl:EnableMouseWheel(true)
    local track = sl:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT"); track:SetPoint("RIGHT")
    track:SetHeight(6)
    track:SetColorTexture(0.2, 0.2, 0.25, 0.9)
    local fill = sl:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT")
    fill:SetHeight(6)
    fill:SetColorTexture(0.95, 0.75, 0.25, 0.9)
    sl:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local lo = sl:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    lo:SetPoint("TOPLEFT", sl, "BOTTOMLEFT", 0, -2); lo:SetText(valueText(minV))
    local hi = sl:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hi:SetPoint("TOPRIGHT", sl, "BOTTOMRIGHT", 0, -2); hi:SetText(valueText(maxV))
    local function show(v)
      label:SetText(fmt:format("|cffffd100" .. valueText(v) .. "|r"))
      fill:SetWidth(math.max(1, 320 * (v - minV) / (maxV - minV)))
    end
    sl:SetScript("OnValueChanged", function(self, v)
      v = math.floor(v + 0.5)
      db[key] = v
      show(v)
      if after then after() end
    end)
    sl:SetScript("OnMouseWheel", function(self, delta)
      self:SetValue(math.min(maxV, math.max(minV, self:GetValue() + delta)))
    end)
    sl:SetValue(db[key])
    show(db[key])
    y = y - 58
  end

  local function LangButton(fmt, key)
    local btn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    btn:SetSize(330, 24)
    btn:SetPoint("TOPLEFT", 10, y)
    local function label() btn:SetText(fmt:format(L["LANG_" .. db[key]])) end
    btn:SetScript("OnClick", function() db[key] = (db[key] == "de") and "en" or "de"; label() end)
    label()
    y = y - 30
  end

  -- General
  Header(L.OPT_GENERAL)
  do
    local btn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    btn:SetSize(200, 24)
    btn:SetPoint("TOPRIGHT", c, "TOPRIGHT", -20, y + 26)
    btn:SetText(L.OPT_STATS)
    btn:SetScript("OnClick", function() if ns.ShowStats then ns.ShowStats() end end)
  end
  Check(L.OPT_ENABLED, "enabled", RebuildAll)
  Check(L.OPT_PLATE_ICONS, "plateIcons", RebuildAll)
  Check(L.OPT_MINIMAP, "minimap", function() ns.UpdateMinimap() end)
  Check(L.OPT_STRANGERS, "strangers", RebuildAll)
  Check(L.OPT_CAMPBUFFED, "campCountsAsBuffed", RebuildAll)
  Check(L.OPT_ONECLICK, "oneClick", RebuildAll)
  Check(L.OPT_QUEUE, "showQueue")
  Check(L.OPT_QUEUE_LOCK, "queueLocked")
  Text(L.OPT_NEXT_NOTE, "GameFontHighlightSmall", 30)
  Check(L.OPT_DISPEL, "dispel", RebuildAll)
  local function zoneChanged() RebuildAll(); UpdateQueue() end
  Check(L.OPT_OFF_CITY, "offInCities", zoneChanged)
  Check(L.OPT_OFF_DUNGEON, "offInDungeon", zoneChanged)
  Check(L.OPT_OFF_RAID, "offInRaid", zoneChanged)
  Check(L.OPT_OFF_PVP, "offInPvP", zoneChanged)
  Check(L.OPT_REQUEST, "showRequest", RebuildAll)
  Check(L.OPT_ACCEPT_REQ, "acceptRequests")
  do
    local btn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    btn:SetSize(420, 24)
    btn:SetPoint("TOPLEFT", 10, y)
    local function label() btn:SetText(L.OPT_PVP:format(L["PVPMODE_" .. db.pvpMode])) end
    btn:SetScript("OnClick", function()
      db.pvpMode = (db.pvpMode == "warn") and "block" or "warn"
      label(); RebuildAll()
    end)
    label()
    y = y - 30
  end

  -- Asking back
  Header(L.OPT_ASK_HEADER)
  Text(L.OPT_ASK_NOTE, "GameFontHighlightSmall", 30)
  Check(L.OPT_ASK, "askBack", function() db.askBackChosen = true end)
  Check(L.OPT_ASK_MISSING, "askOnlyIfMissing")
  Check(L.OPT_ASK_CAMP, "askCampCounts")
  Check(L.OPT_THANK, "thank")
  Check(L.OPT_MSG_GROUP, "msgToGroup")
  do
    local btn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    btn:SetSize(330, 24)
    btn:SetPoint("TOPLEFT", 10, y)
    local function label() btn:SetText(L.OPT_THANK_MODE:format(L["THANKMODE_" .. db.thankMode])) end
    btn:SetScript("OnClick", function()
      db.thankMode = (db.thankMode == "emote") and "whisper" or "emote"
      db.thankModeChosen = true
      label()
    end)
    label()
    y = y - 30
  end
  Slider(L.OPT_ASK_REMAIN, "askRemainMin", 1, 60, function(v) return tostring(v) end, RebuildAll)
  Slider(L.OPT_ASK_LEVEL, "askMaxBelow", 1, 60,
    function(v) return v >= 60 and L.LEVEL_ANY or tostring(v) end, RebuildAll)
  Check(L.OPT_LINKS, "useLinks")
  LangButton(L.OPT_MYLANG, "myLang")

  -- Messages
  Header(L.OPT_TEMPLATES)
  Text(L.OPT_TEMPLATES_NOTE, "GameFontHighlightSmall", 44)

  local editLang = db.myLang
  local boxes = {}
  local langLabel = Text("", "GameFontNormal", 26)
  local function refresh()
    langLabel:SetText(L.OPT_EDITING:format(L["LANG_" .. editLang]))
    for _, eb in ipairs(boxes) do eb:SetText(eb.getter() or ""); eb:SetCursorPosition(0) end
  end
  local function smallButton(text, x, onClick)
    local btn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    btn:SetSize(130, 22)
    btn:SetPoint("TOPLEFT", x, y + 26)
    btn:SetText(text)
    btn:SetScript("OnClick", onClick)
  end
  smallButton(L.LANG_en, 250, function() editLang = "en"; refresh() end)
  smallButton(L.LANG_de, 384, function() editLang = "de"; refresh() end)

  for _, key in ipairs(ns.TEMPLATE_CLASSES) do
    local label = (key == "OTHER") and L.OPT_OTHER
      or ((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[key]) or key)
    boxes[#boxes + 1] = Input(label,
      function() return Template(editLang, key) end,
      function(v)
        db.templates[editLang] = db.templates[editLang] or {}
        db.templates[editLang][key] = v
      end)
  end

  boxes[#boxes + 1] = Input(L.OPT_THANK_TEXT,
    function() return Template(editLang, "THANKS") end,
    function(v)
      db.templates[editLang] = db.templates[editLang] or {}
      db.templates[editLang].THANKS = v
    end)
  boxes[#boxes + 1] = Input(L.OPT_REQUEST_TEXT,
    function() return Template(editLang, "REQUEST") end,
    function(v)
      db.templates[editLang] = db.templates[editLang] or {}
      db.templates[editLang].REQUEST = v
    end)

  local reset = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
  reset:SetSize(200, 24)
  reset:SetPoint("TOPLEFT", 10, y)
  reset:SetText(L.OPT_RESET)
  reset:SetScript("OnClick", function() db.templates[editLang] = nil; refresh() end)
  y = y - 34

  refresh()
  c:SetHeight(-y + 20)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local cat = Settings.RegisterCanvasLayoutCategory(panel, "BuffBarter")
    Settings.RegisterAddOnCategory(cat)
    ns.settingsCategory = cat
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end
