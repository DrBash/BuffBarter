local ADDON, ns = ...

-- All buff families. ids: single target ranks, HIGHEST FIRST.
-- greater: group/class wide versions (only used for detection).
-- class: who casts it. blessing: paladin rule "one blessing per paladin".
-- IDs are Classic Era IDs. If Forever uses different ones, the addon
-- falls back to matching the localized spell name.
ns.BUFFS = {
  -- Paladin
  MIGHT     = { class = "PALADIN", blessing = true, ids = { 25291, 19838, 19837, 19836, 19835, 19834, 19740 }, greater = { 25916, 25782 } },
  WISDOM    = { class = "PALADIN", blessing = true, ids = { 25290, 19854, 19853, 19852, 19850, 19742 },        greater = { 25918, 25894 } },
  KINGS     = { class = "PALADIN", blessing = true, ids = { 20217 },                                           greater = { 25898 } },
  LIGHT     = { class = "PALADIN", blessing = true, ids = { 19979, 19978, 19977 },                             greater = { 25890 } },
  -- Priest
  FORTITUDE  = { class = "PRIEST", ids = { 10938, 10937, 2791, 1245, 1244, 1243 }, greater = { 21564, 21562 } },
  SPIRIT     = { class = "PRIEST", ids = { 27841, 14819, 14818, 14752 },           greater = { 27681 } },
  SHADOWPROT = { class = "PRIEST", ids = { 10958, 10957, 976 },                    greater = { 27683 } },
  -- Mage
  INTELLECT  = { class = "MAGE",   ids = { 10157, 10156, 1461, 1460, 1459 },       greater = { 23028 } },
  -- Druid
  WILD       = { class = "DRUID",  ids = { 9885, 9884, 8907, 5234, 6756, 5232, 1126 }, greater = { 21850, 21849 } },
  THORNS     = { class = "DRUID",  ids = { 9910, 9756, 8914, 1075, 782, 467 } },
}

-- Paladin subset (kept for the blessing specific code).
ns.BLESSINGS = {}
for fam, d in pairs(ns.BUFFS) do
  if d.blessing then ns.BLESSINGS[fam] = d end
end

-- Non-paladin buffers: which of your buffs to offer, in this order.
-- SHADOWPROT is situational and left out by default.
ns.CLASS_ORDER = {
  PRIEST = { "FORTITUDE", "SPIRIT" },
  MAGE   = { "INTELLECT" },
  DRUID  = { "WILD", "THORNS" },
}

-- Who wants a non-blessing buff. Missing entry = everybody.
-- TANK means: only targets with the tank role.
ns.WANTS = {
  INTELLECT  = { notFor = { WARRIOR = true, ROGUE = true } },
  SPIRIT     = { notFor = { WARRIOR = true, ROGUE = true } },
  THORNS     = { tankOnly = true },
}

-- Priority per target class. Only families listed here are ever offered,
-- so "no Wisdom for warriors" simply means WISDOM is not in the list.
-- TANK overrides the class when the target has the tank role assigned.
ns.PRIO = {
  WARRIOR = { "MIGHT", "KINGS" },
  ROGUE   = { "MIGHT", "KINGS" },
  HUNTER  = { "WISDOM", "KINGS" },
  MAGE    = { "WISDOM", "KINGS" },
  WARLOCK = { "WISDOM", "KINGS" },
  PRIEST  = { "WISDOM", "KINGS" },
  DRUID   = { "KINGS", "WISDOM", "MIGHT" },
  SHAMAN  = { "KINGS", "WISDOM", "MIGHT" },
  PALADIN = { "KINGS", "WISDOM", "MIGHT" },
  TANK    = { "KINGS", "MIGHT" },
}

-- Camp buff spell IDs -> family they are a weaker copy of.
-- Unknown yet. Fill in via /barter scan + /barter camp, stored per account.
-- Known pairs: Fish Bowl -> KINGS, Lodestone -> MIGHT, Mana Well -> WISDOM,
-- First Aid Kit -> FORTITUDE, Incense Candle -> INTELLECT,
-- Enchanted Lute -> WILD, Faction Banner -> SPIRIT.
ns.CAMP_IDS = {
  -- [123456] = "KINGS",
}

------------------------------------------------------------------------
-- Asking for a buff back
------------------------------------------------------------------------
-- What to ask each class for. BLESSING means: the first blessing from
-- ns.SELF_WISH that you do not have yet.
ns.ASK_FOR = { PRIEST = "FORTITUDE", MAGE = "INTELLECT", DRUID = "WILD", PALADIN = "BLESSING" }
ns.SELF_WISH = { "KINGS", "WISDOM", "MIGHT" }

-- Buffs a class never asks for (no mana: no Arcane Intellect).
ns.NO_WANT = {
  WARRIOR = { INTELLECT = true },
  ROGUE   = { INTELLECT = true },
}

-- Buff names in the language of the whisper (not of your client).
ns.BUFF_NAMES = {
  en = {
    MIGHT = "Blessing of Might", WISDOM = "Blessing of Wisdom", KINGS = "Blessing of Kings",
    LIGHT = "Blessing of Light",
    FORTITUDE = "Power Word: Fortitude", INTELLECT = "Arcane Intellect", WILD = "Mark of the Wild",
    SPIRIT = "Divine Spirit", SHADOWPROT = "Shadow Protection", THORNS = "Thorns",
  },
  de = {
    MIGHT = "Segen der Macht", WISDOM = "Segen der Weisheit", KINGS = "Segen der Könige",
    LIGHT = "Segen des Lichts",
    FORTITUDE = "Machtwort: Seelenstärke", INTELLECT = "Arkane Intelligenz", WILD = "Mal der Wildnis",
    SPIRIT = "Göttlicher Willen", SHADOWPROT = "Schattenschutz", THORNS = "Dornen",
  },
}

-- Default whispers. Placeholders: {name} {buff} {ask} {me}
-- An empty text means: send nothing to that class.
ns.TEMPLATE_CLASSES = { "PRIEST", "MAGE", "DRUID", "PALADIN", "OTHER" }
ns.DEFAULT_TEMPLATES = {
  en = {
    PRIEST  = "Hi {name}, I gave you {buff}. Would you mind giving me {ask}? Thanks!",
    MAGE    = "Hi {name}, I gave you {buff}. Would you mind giving me {ask}? Thanks!",
    DRUID   = "Hi {name}, I gave you {buff}. Would you mind giving me {ask}? Thanks!",
    PALADIN = "Hi {name}, I gave you {buff}. Could you give me {ask} in return? Thanks!",
    OTHER   = "",
    REQUEST = "Hi {name}, could you give me {ask}, please? Thanks!",
  },
  de = {
    PRIEST  = "Hi {name}, ich hab dir {buff} gegeben. Magst du mir {ask} geben? Danke!",
    MAGE    = "Hi {name}, ich hab dir {buff} gegeben. Magst du mir {ask} geben? Danke!",
    DRUID   = "Hi {name}, ich hab dir {buff} gegeben. Magst du mir {ask} geben? Danke!",
    PALADIN = "Hi {name}, ich hab dir {buff} gegeben. Gibst du mir im Gegenzug {ask}? Danke!",
    OTHER   = "",
    REQUEST = "Hi {name}, könntest du mir bitte {ask} geben? Danke!",
  },
}
