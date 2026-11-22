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
  askBack = true,            -- whisper after buffing someone
  askOnlyIfMissing = true,   -- only ask for buffs you do not have
  askCampCounts = false,     -- your own camp buff counts as having it
  myLang = (GetLocale() == "deDE") and "de" or "en", -- default whisper language
  useLinks = true,
  oneClick = true,
  askMaxBelow = 5,           -- only ask players at most this many levels below you           -- icon click targets the player by name, casts, retargets
  pvpMode = "warn",          -- PvP flagged targets: "warn" or "block"           -- {buff} and {ask} as clickable spell links
  playerLang = {},           -- ["First-Last"] = "de"|"en", via /barter lang
  templates = {},            -- [lang][CLASS] = text, overrides defaults
}
local db

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

local function BuildSpells()
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
    -- highest known rank by ID
    for _, id in ipairs(d.ids) do
      if IsKnown(id) then
        local n, icon = SpellInfo(id)
        if n then known[fam] = { name = n, icon = icon, id = id } end
        break
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

local STATE_COLOR = {
  MISSING  = { 0, 0, 0 },
  CAMP     = { 1, 0.5, 0 },
  EXPIRING = { 1, 0.85, 0 },
  SWAP     = { 0.7, 0.3, 1 },
}

local function OnEnter(self)
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
    if self.pvpFlag then GameTooltip:AddLine(L.PVP_WARN, 1, 0.25, 0.25, true) end
    GameTooltip:AddLine(L.CLICK_TO_CAST, 0.5, 1, 0.5)
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
  b:SetScript("OnEnter", OnEnter)
  b:SetScript("OnLeave", GameTooltip_Hide)
  b:HookScript("PostClick", function(self, mouse, down)
    if ns.Remember and self.clickable and self.unit then ns.Remember(self.unit, self.fam) end
    if down and self.clickable and self.pvpFlag then
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
  if not db.enabled or not plate or (plate.IsForbidden and plate:IsForbidden()) or not Eligible(unit) then
    Release(unit); return
  end

  local fam, state, myFam, myLeft = Decide(unit)
  if not fam then Release(unit); return end

  local b = active[unit]
  if not b then
    b = table.remove(pool) or NewButton()
    active[unit] = b
    b:ClearAllPoints()
    b:SetPoint("CENTER", plate, "CENTER", 0, db.offset)
  end

  local k = known[fam]
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
  if blocked then
    b:SetAttribute("macrotext", nil)
  elseif isTarget then
    b:SetAttribute("macrotext", "/cast [@target,help,nodead] " .. k.name)
    clickable = true
  elseif db.oneClick and tarName then
    b:SetAttribute("macrotext", "/tar " .. tarName .. "\n/cast [@target,help,nodead] " .. k.name .. "\n/targetlasttarget")
    clickable = true
  else
    b:SetAttribute("macrotext", nil)
  end
  b:EnableMouse(clickable)
  b.clickable = clickable
  b.isTarget = isTarget
  b.unit, b.fam, b.state, b.myFam = unit, fam, state, myFam
  b.icon:SetTexture(k.icon)
  local c = pvpFlag and { 1, 0.1, 0.1 } or STATE_COLOR[state]
  b.border:SetColorTexture(c[1], c[2], c[3], 0.9)

  if pvpFlag then
    b.label:SetText(L.PVP_LABEL); b.label:SetTextColor(1, 0.25, 0.25)
  elseif state == "CAMP" then
    b.label:SetText(L.CAMP); b.label:SetTextColor(1, 0.5, 0)
  elseif state == "EXPIRING" then
    b.label:SetText(("%dm"):format(math.max(0, math.floor(myLeft / 60)))); b.label:SetTextColor(1, 0.85, 0)
  elseif state == "SWAP" then
    b.label:SetText(L.SWAP); b.label:SetTextColor(0.7, 0.3, 1)
  else
    b.label:SetText("")
  end

  b:SetAlpha(InRange(k.name, unit) and (clickable and 1 or 0.6) or 0.3)
  b:Show()
end

-- Blessing icon plus request icon (the latter is defined further down).
local function Refresh(unit)
  RefreshBuff(unit)
  if ns.RefreshReq then ns.RefreshReq(unit) end
end

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
  if not db.enabled then return end
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
  if unit and db.enabled and not (db.pvpMode == "block" and WouldFlag(unit)) then
    local fam = Decide(unit)
    if fam and known[fam] then
      text = "/cast [@" .. unit .. ",help,nodead] " .. known[fam].name
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
local function PlayerHas(fam)
  local res
  pcall(ForEachBuff, "player", function(name, id, src, exp)
    local f = (id and (otherIdToFam[id] or idToFamily[id])) or (name and (otherNameToFam[name] or nameToFamily[name]))
    if f == fam then res = "class" end
    if not res and CampFamily(id) == fam then res = "camp" end
  end)
  return res
end

local function Lacking(fam)
  local has = PlayerHas(fam)
  if has == "class" then return false end
  if has == "camp" and db.askCampCounts then return false end
  return true
end

-- Which buff to ask this class for, or nil when there is nothing to ask.
local function AskFamily(class)
  local what = ns.ASK_FOR[class]
  if not what then return nil end
  if what == "BLESSING" then
    for _, fam in ipairs(ns.SELF_WISH) do
      if Lacking(fam) then return fam end
    end
    return nil
  end
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
local function BuildAsk(full, short, realm, class, fam)
  local lang = LangFor(full)
  local key = ns.ASK_FOR[class] and class or "OTHER"
  local askFam = AskFamily(class)
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
local ASK_LEVEL_STEPS = { 3, 5, 10, 15, 60 }   -- 60 = any level
local function LevelOK(level)
  if not level or level <= 0 or db.askMaxBelow >= 60 then return true end
  return level >= (UnitLevel("player") or 1) - db.askMaxBelow
end

function ns.Remember(unit, fam)
  if not UnitExists(unit) or not fam then return end
  local full, short, realm = FullName(unit)
  local _, class = UnitClass(unit)
  local raceName, race = UnitRace(unit)
  if not full or UnitIsUnit(unit, "player") then return end
  pending = { full = full, short = short, realm = realm, class = class, race = race, raceName = raceName,
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
      local full, class, race, raceName
      if src and UnitExists(src) and UnitIsPlayer(src) then
        full = FullName(src)
        class = select(2, UnitClass(src))
        raceName, race = UnitRace(src)
      end
      RecordReceived(full, class, fam or camp, camp and true, race, raceName)
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
  local text = BuildAsk(p.full, p.short, p.realm, p.class, p.fam)
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
local function RequestFamily(class)
  local what = ns.ASK_FOR[class]
  if not what then return nil end
  if what == "BLESSING" then
    for _, fam in ipairs(MyBlessingWish()) do
      if Lacking(fam) then return fam end
    end
    return nil
  end
  local _, myClass = UnitClass("player")
  if ns.NO_WANT[myClass] and ns.NO_WANT[myClass][what] then return nil end
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
  if not db.enabled or not db.showRequest or IsInInstance() or not plate
    or (plate.IsForbidden and plate:IsForbidden()) or not Eligible(unit) then
    ns.ReleaseReq(unit); return
  end
  local _, class = UnitClass(unit)
  if not LevelOK(UnitLevel(unit)) then ns.ReleaseReq(unit); return end
  local ok, fam = pcall(RequestFamily, class)
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
  if not db or not db.enabled or tooltip ~= GameTooltip then return end
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
    ApplyBinding()
    RemoveOldMacro()
    self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    if BuildOptions then BuildOptions() end
    C_Timer.NewTicker(0.5, function() RefreshAll(); UpdateSmart() end) -- range, expiry, mouseover
    Print(L.LOADED)
  elseif event == "SPELLS_CHANGED" then
    BuildSpells()
    RebuildAll()
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    Refresh(arg1)
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    if InCombatLockdown() then pendingRebuild = true else ReleaseBoth(arg1) end
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
    ApplyBinding(); UpdateSmart()
  elseif event == "GROUP_ROSTER_UPDATE" then
    RebuildAll()
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
    if ns.settingsCategory and Settings and Settings.OpenToCategory then
      Settings.OpenToCategory(ns.settingsCategory:GetID())
    end
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
    for fam, k in pairs(known) do print(("   %s: %s"):format(fam, k.name)) end
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
    local text, lang = BuildAsk(full, short, realm, class, fam)
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

  tinsert(UISpecialFrames, "BuffBarterStatsFrame") -- Esc closes it
  return f
end

local function ShowStats()
  statsFrame = statsFrame or BuildStatsFrame()
  statsFrame:Refresh()
  statsFrame:Show()
end
ns.ShowStats = ShowStats

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
  Check(L.OPT_STRANGERS, "strangers", RebuildAll)
  Check(L.OPT_CAMPBUFFED, "campCountsAsBuffed", RebuildAll)
  Check(L.OPT_ONECLICK, "oneClick", RebuildAll)
  Check(L.OPT_REQUEST, "showRequest", RebuildAll)
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
  Check(L.OPT_ASK, "askBack")
  Check(L.OPT_ASK_MISSING, "askOnlyIfMissing")
  Check(L.OPT_ASK_CAMP, "askCampCounts")
  do
    local btn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    btn:SetSize(470, 24)
    btn:SetPoint("TOPLEFT", 10, y)
    local function label()
      local v = db.askMaxBelow >= 60 and L.LEVEL_ANY or tostring(db.askMaxBelow)
      btn:SetText(L.OPT_ASK_LEVEL:format(v))
    end
    btn:SetScript("OnClick", function()
      local nextValue = ASK_LEVEL_STEPS[1]
      for i, v in ipairs(ASK_LEVEL_STEPS) do
        if v == db.askMaxBelow then nextValue = ASK_LEVEL_STEPS[i % #ASK_LEVEL_STEPS + 1] end
      end
      db.askMaxBelow = nextValue
      label(); RebuildAll()
    end)
    label()
    y = y - 30
  end
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
