local ADDON, ns = ...

-- English is the default. Missing keys fall back to the key itself.
local L = setmetatable({}, { __index = function(_, k) return k end })
ns.L = L

L.LOADED       = "loaded. Type /barter help for commands."
L.ENABLED      = "enabled"
L.DISABLED     = "disabled"
L.CAMP         = "Camp"
L.SWAP         = "Swap"
L.STATE_MISSING  = "Not buffed"
L.STATE_CAMP     = "Only the camp buff is active (your buff replaces it)"
L.STATE_EXPIRING = "Your buff expires soon"
L.STATE_SWAP     = "Replaces your current blessing: %s"
L.CLICK_TO_CAST  = "Click to cast"
L.SCAN_HEADER  = "Buffs on %s:"
L.SCAN_NONE    = "No readable buffs on %s."
L.SCAN_LINE    = "%s  id=%s  from=%s  %s"
L.SCAN_HINT    = "Unknown camp buff? Register it with /barter camp <MIGHT|WISDOM|KINGS|...> <id>"
L.KNOWN_HEADER = "Your buffs:"
L.KNOWN_NONE   = "No supported buffs found (paladin, priest, mage or druid)."
L.CAMP_ADDED   = "Camp buff %s registered as weaker %s."
L.CAMP_BAD     = "Usage: /barter camp <FAMILY> <spellID>  (families: %s)"
L.FRIENDLY_ON  = "Friendly nameplates switched on."
L.STRANGERS_ON  = "Buttons also for strangers."
L.STRANGERS_OFF = "Buttons only for group and guild."
L.COMBAT_WAIT  = "In combat. Try again afterwards."
L.RESET_DONE   = "Settings reset."
L.HINT_TARGET  = "Target this player first, then click. Or hover the player and press your BuffBarter key (/barter bind)."
L.BIND_SET     = "Key %s now buffs the player under your mouse (or your target)."
L.BIND_CLEARED = "Key binding removed."
L.BIND_USAGE   = "Usage: /barter bind <KEY>, e.g. /barter bind F or /barter bind SHIFT-B"
L.MACRO_READY  = "Macro 'BuffBarter' is ready. Bind it in Options > Keybindings > Click Casting (e.g. to Left Click)."
L.MACRO_FULL   = "Could not create the macro 'BuffBarter' (macro slots full?)."
L.LANG_en = "English"
L.LANG_de = "Deutsch"
L.NEED_TARGET  = "Target a player first."
L.PREVIEW      = "Would whisper %s (%s): %s"
L.PREVIEW_NONE = "Nothing would be sent to %s (no buff to ask for, or the text for this class is empty)."
L.LANG_USAGE   = "Usage: target a player, then /barter lang de  or  /barter lang en"
L.LANG_SET     = "%s will be whispered in %s."
L.OPT_GENERAL     = "General"
L.OPT_ENABLED     = "Show buff icons on nameplates"
L.OPT_STRANGERS   = "Also for players outside group and guild"
L.OPT_CAMPBUFFED  = "Treat camp buffs as buffed (hide those players)"
L.OPT_ASK_HEADER  = "Ask for a buff back"
L.OPT_ASK_NOTE    = "After you buff someone, BuffBarter can whisper them and ask for their class buff. Only outside instances, at most once per player every 30 minutes."
L.OPT_ASK         = "After buffing, automatically whisper and ask for a buff back (off by default)"
L.OPT_ASK_MISSING = "Only ask for buffs I do not have yet"
L.OPT_ASK_CAMP    = "My camp buff counts as having it (do not ask then)"
L.OPT_MYLANG      = "Language of my whispers: %s"
L.OPT_LINKS       = "Show buffs as clickable spell links"
L.OPT_TEMPLATES   = "Messages"
L.OPT_TEMPLATES_NOTE = "Placeholders: {name} the player, {buff} the buff you gave, {ask} the buff you ask for, {me} your name. An empty line sends nothing to that class. Enter saves. Single players: target them and type /barter lang de or /barter lang en. Test: target someone and type /barter preview."
L.OPT_EDITING     = "Editing the %s texts"
L.OPT_OTHER       = "Other classes (thank you only, empty = nothing)"
L.OPT_RESET       = "Reset these texts"
L.STATS_TILE_GIVEN    = "buffs given"
L.STATS_TILE_RECEIVED = "buffs received"
L.STATS_TILE_BACK     = "buffed you back"
L.STATS_TILE_ANSWER   = "asks answered"
L.STATS_PLAYERS       = "%d players"
L.STATS_PLAYER        = "%d player"
L.STATS_OF            = "%d of %d"
L.STATS_LEGEND        = "|cfff2bf40gold|r = you buffed them    |cff4dbfffblue|r = they buffed you"
L.STATS_BY_RACE       = "By race"
L.STATS_NONE_SHORT    = "nothing yet"
L.STATS_FOOTER        = "Camp buffs: %d   since %s"
L.STATS_TITLE     = "BuffBarter statistics"
L.STATS_GIVEN     = "Buffs given"
L.STATS_RECEIVED  = "Buffs received"
L.STATS_TOTAL     = "Total: %d   Different players: %d"
L.STATS_CAMP      = "From camps: %d"
L.STATS_BY_CLASS  = "By class"
L.STATS_BY_BUFF   = "By buff"
L.STATS_TOP       = "Top players"
L.STATS_ASKS      = "Asking for buffs"
L.STATS_ASK_LINE  = "Asked after buffing: %d   Requests: %d   Answered: %d (%d%%)"
L.STATS_SINCE     = "Counting since %s (this character)"
L.STATS_NONE      = "   nothing yet"
L.STATS_RESET     = "Reset"
L.STATS_RESET_HINT = "Shift-click to really reset the statistics of this character."
L.OPT_STATS       = "Show statistics"
L.UNKNOWN         = "unknown"
L.PVP_LABEL       = "PvP"
L.PVP_ARM         = "PvP: click"
L.PVP_CONFIRM     = "Sure? Click"
L.PVP_ARM_TIP     = "PvP flagged! The first click only unlocks. A second click within 6 seconds buffs and flags you for PvP."
L.PVP_ARMED       = "%s is PvP flagged. Click again within %d seconds to buff. You will be flagged too."
L.PVP_WARN        = "PvP flagged: buffing this player flags you for PvP as well!"
L.PVP_BLOCKED     = "PvP flagged: not buffed because of your setting."
L.PVP_CHAT        = "Careful: %s is PvP flagged. Buffing flags you as well."
L.OPT_PVP         = "PvP flagged players (while you are not flagged): %s"
L.PVPMODE_warn    = "warn"
L.PVPMODE_block   = "do not buff"
L.OPT_ASK_LEVEL   = "Ask only players at most %s levels below me"
L.LEVEL_ANY       = "any number of"
L.QUEUE_YOU       = "You"
L.EYE_HIDE        = "Hide the icons above players (the list keeps working)"
L.ASK_HIDE        = "Hide the request (\"ask\") icons"
L.ASK_SHOW        = "Show the request (\"ask\") icons again"
L.EYE_SHOW        = "Show the icons above players again"
L.QUEUE_COLLAPSE  = "Fold the list"
L.QUEUE_EXPAND    = "Unfold the list"
L.QUEUE_EMPTY     = "Everyone nearby is buffed."
L.OPT_QUEUE       = "Show the buff list (fixed panel, drag to move)"
L.OPT_QUEUE_LOCK  = "Lock the buff list"
L.OPT_NEXT_NOTE   = "Tip: /barter bindnext KEY sets a key that buffs the first player in range from the list. Press it repeatedly to buff everyone."
L.OPT_ASK_REMAIN  = "Ask again when my buff has less than %s min left"
L.NEXT_USAGE      = "Usage: /barter bindnext <KEY>, e.g. /barter bindnext G"
L.NEXT_SET        = "Key %s now buffs the next player from the buff list."
L.OPT_MINIMAP     = "Show minimap icon"
L.MM_LEFT         = "Left click: settings"
L.MM_RIGHT        = "Right click: statistics"
L.MM_SHIFT        = "Shift + click: show or hide the buff list"
L.MM_DRAG         = "Drag to move"
L.DISPEL_Magic    = "Magic"
L.DISPEL_Curse    = "Curse"
L.DISPEL_Disease  = "Disease"
L.DISPEL_Poison   = "Poison"
L.STATE_DISPEL    = "Click to remove it with %s"
L.OPT_DISPEL      = "Show diseases, poisons, curses and magic you can remove (out of combat)"
L.OPT_OFF_CITY    = "In capital cities: no icons above players, buff list folded"
L.QUEUE_CITY_TAG  = "city"
L.CITY_VISIT      = "Only for this city visit. Next time you enter a city it starts off again."
L.QUEUE_CITY      = "In capital cities the list starts folded. Unfold it to see the players."
L.OPT_OFF_DUNGEON = "Switch off in dungeons"
L.OPT_OFF_RAID    = "Switch off in raids"
L.OPT_OFF_PVP     = "Switch off in battlegrounds and arenas"
L.OPT_THANK       = "Thank players who buff me (at most every 30 minutes per player)"
L.OPT_THANK_MODE  = "Thank via: %s (click to change)"
L.THANKMODE_emote = "/thank emote"
L.THANKMODE_whisper = "whisper"
L.OPT_THANK_TEXT  = "Thank you whisper ({name}, {buff}, {me})"
L.OPT_MSG_GROUP   = "Also send these automatic whispers to my group and raid members"
L.OPT_PLATE_ICONS = "Show buff icons above players (off: use only the buff list)"
L.REQ_POPUP_TITLE = "buff request"
L.REQ_POPUP       = "%s asks you for %s."
L.REQ_POPUP_BUFF  = "Buff"
L.REQ_POPUP_NO    = "No thanks"
L.OPT_ACCEPT_REQ  = "Accept buff requests from other BuffBarter users (window with a buff button)"
L.OPT_ONECLICK    = "One click buffs: the icon briefly targets the player, casts and switches back"
L.OPT_REQUEST     = "Request icons: click a priest, mage, druid or paladin to ask for their buff"
L.OPT_REQUEST_TEXT = "Request text, when you click a request icon ({name}, {ask}, {me})"
L.REQ_LABEL       = "ask"
L.REQ_ASKED       = "asked"
L.REQ_TIP         = "Click: whisper %s and ask for this buff"
L.REQ_TIP_ASKED   = "Already asked. You can ask again in %d min."
L.REQ_NO_WHISPER  = "Whispers are not possible here (inside instances)."
L.DEMO_ON  = "Demo '%s' shown (invented players, nothing is cast or sent). /barter demo off ends it."
L.DEMO_OFF = "Demo ended."
L.DEMO_HELP = {
  "/barter demo list     buff list with example players",
  "/barter demo icons    all icon states side by side (above your target, else above you)",
  "/barter demo ask      buff icon plus request icon",
  "/barter demo pvp      PvP flagged player: icon, list row, chat warning",
  "/barter demo dispel   removable debuff: icon and list row",
  "/barter demo whisper  example whispers in your chat (ask back, request, thanks)",
  "/barter demo request  buff request window",
  "/barter demo city     folded list in a capital city",
  "/barter demo all      everything at once (one screenshot shows it all)",
  "/barter demo off      end the demo",
}
L.HELP = {
  "/barter            open settings",
  "/barter toggle     icons on/off",
  "/barter minimap    minimap icon on/off",
  "/barter list       buff list on/off",
  "/barter icons      icons above players on/off",
  "/barter preview    show the whisper for your target",
  "/barter testrequest show the buff request window with yourself as sender",
  "/barter demo       example scenes for screenshots (/barter demo for the list)",
  "/barter stats      statistics",
  "/barter lang de|en whisper language for your target",
  "/barter bind KEY   key that buffs the player under your mouse (else target)",
  "/barter unbind     remove that key",
  "/barter bindnext KEY key that buffs the next player of the buff list",
  "/barter debug      toggle click diagnostics",
  "/barter scan       list buffs (with spell ID) on your target, or yourself",
  "/barter spells     list your buffs the addon knows",
  "/barter camp F ID  register camp buff ID as weaker version of family F",
  "/barter friendly   switch on friendly nameplates",
  "/barter strangers  toggle buttons for non-group players",
  "/barter reset      reset settings",
}

if GetLocale() == "deDE" then
  L.LOADED       = "geladen. /barter help zeigt die Befehle."
  L.ENABLED      = "aktiviert"
  L.DISABLED     = "deaktiviert"
  L.CAMP         = "Lager"
  L.SWAP         = "Tausch"
  L.STATE_MISSING  = "Nicht gebufft"
  L.STATE_CAMP     = "Nur der Lagerbuff ist aktiv (dein Buff ersetzt ihn)"
  L.STATE_EXPIRING = "Dein Buff läuft bald ab"
  L.STATE_SWAP     = "Ersetzt deinen aktuellen Segen: %s"
  L.CLICK_TO_CAST  = "Klicken zum Wirken"
  L.SCAN_HEADER  = "Buffs auf %s:"
  L.SCAN_NONE    = "Keine lesbaren Buffs auf %s."
  L.SCAN_LINE    = "%s  id=%s  von=%s  %s"
  L.SCAN_HINT    = "Unbekannter Lagerbuff? Eintragen mit /barter camp <MIGHT|WISDOM|KINGS|...> <id>"
  L.KNOWN_HEADER = "Deine Buffs:"
  L.KNOWN_NONE   = "Keine unterstützten Buffs gefunden (Paladin, Priester, Magier oder Druide)."
  L.CAMP_ADDED   = "Lagerbuff %s als schwächere Form von %s eingetragen."
  L.CAMP_BAD     = "Aufruf: /barter camp <FAMILIE> <SpellID>  (Familien: %s)"
  L.FRIENDLY_ON  = "Freundliche Namensplaketten eingeschaltet."
  L.STRANGERS_ON  = "Knöpfe auch für Fremde."
  L.STRANGERS_OFF = "Knöpfe nur für Gruppe und Gilde."
  L.COMBAT_WAIT  = "Im Kampf. Bitte danach nochmal."
  L.RESET_DONE   = "Einstellungen zurückgesetzt."
  L.HINT_TARGET  = "Erst den Spieler als Ziel wählen, dann hier klicken. Oder mit der Maus über den Spieler und die BuffBarter-Taste drücken (/barter bind)."
  L.BIND_SET     = "Taste %s bufft jetzt den Spieler unter der Maus (sonst dein Ziel)."
  L.BIND_CLEARED = "Tastenbelegung entfernt."
  L.BIND_USAGE   = "Aufruf: /barter bind <TASTE>, z. B. /barter bind F oder /barter bind SHIFT-B"
  L.MACRO_READY  = "Makro 'BuffBarter' ist bereit. Belege es unter Optionen > Tastaturbelegung > Klickzauber (z. B. auf Linksklick)."
  L.MACRO_FULL   = "Makro 'BuffBarter' konnte nicht erstellt werden (Makroplätze voll?)."
  L.NEED_TARGET  = "Erst einen Spieler als Ziel wählen."
  L.PREVIEW      = "Würde %s (%s) anflüstern: %s"
  L.PREVIEW_NONE = "An %s würde nichts geschickt (kein Buff zu erbitten oder der Text für diese Klasse ist leer)."
  L.LANG_USAGE   = "Aufruf: Spieler als Ziel wählen, dann /barter lang de  oder  /barter lang en"
  L.LANG_SET     = "%s wird auf %s angeflüstert."
  L.OPT_GENERAL     = "Allgemein"
  L.OPT_ENABLED     = "Buff-Symbole auf Namensplaketten anzeigen"
  L.OPT_STRANGERS   = "Auch für Spieler außerhalb von Gruppe und Gilde"
  L.OPT_CAMPBUFFED  = "Lagerbuffs als gebufft werten (diese Spieler ausblenden)"
  L.OPT_ASK_HEADER  = "Um einen Gegenbuff bitten"
  L.OPT_ASK_NOTE    = "Nachdem du jemanden gebufft hast, kann BuffBarter ihn anflüstern und um seinen Klassenbuff bitten. Nur außerhalb von Instanzen, höchstens einmal pro Spieler alle 30 Minuten."
  L.OPT_ASK         = "Nach dem Buffen automatisch anflüstern und um einen Gegenbuff bitten (standardmäßig aus)"
  L.OPT_ASK_MISSING = "Nur um Buffs bitten, die ich noch nicht habe"
  L.OPT_ASK_CAMP    = "Mein Lagerbuff zählt als vorhanden (dann nicht fragen)"
  L.OPT_MYLANG      = "Sprache meiner Flüsternachrichten: %s"
  L.OPT_LINKS       = "Buffs als anklickbare Zauberlinks schicken"
  L.OPT_TEMPLATES   = "Nachrichten"
  L.OPT_TEMPLATES_NOTE = "Platzhalter: {name} der Spieler, {buff} dein Buff, {ask} der erbetene Buff, {me} dein Name. Eine leere Zeile schickt dieser Klasse nichts. Enter speichert. Einzelne Spieler: als Ziel wählen und /barter lang de oder /barter lang en eingeben. Test: Ziel wählen und /barter preview eingeben."
  L.OPT_EDITING     = "Du bearbeitest die Texte auf %s"
  L.OPT_OTHER       = "Andere Klassen (nur Dankeschön, leer = nichts)"
  L.OPT_RESET       = "Diese Texte zurücksetzen"
  L.STATS_TILE_GIVEN    = "Buffs gegeben"
  L.STATS_TILE_RECEIVED = "Buffs bekommen"
  L.STATS_TILE_BACK     = "zurückgebufft"
  L.STATS_TILE_ANSWER   = "Anfragen erfüllt"
  L.STATS_PLAYERS       = "%d Spieler"
  L.STATS_PLAYER        = "%d Spieler"
  L.STATS_OF            = "%d von %d"
  L.STATS_LEGEND        = "|cfff2bf40Gold|r = du hast gebufft    |cff4dbfffBlau|r = du wurdest gebufft"
  L.STATS_BY_RACE       = "Nach Volk"
  L.STATS_NONE_SHORT    = "noch nichts"
  L.STATS_FOOTER        = "Lagerbuffs: %d   seit %s"
  L.STATS_TITLE     = "BuffBarter Statistik"
  L.STATS_GIVEN     = "Gegebene Buffs"
  L.STATS_RECEIVED  = "Erhaltene Buffs"
  L.STATS_TOTAL     = "Gesamt: %d   Verschiedene Spieler: %d"
  L.STATS_CAMP      = "Aus Lagern: %d"
  L.STATS_BY_CLASS  = "Nach Klasse"
  L.STATS_BY_BUFF   = "Nach Buff"
  L.STATS_TOP       = "Häufigste Spieler"
  L.STATS_ASKS      = "Um Buffs gebeten"
  L.STATS_ASK_LINE  = "Nach dem Buffen gefragt: %d   Anfragen: %d   Beantwortet: %d (%d %%)"
  L.STATS_SINCE     = "Gezählt seit %s (dieser Charakter)"
  L.STATS_NONE      = "   noch nichts"
  L.STATS_RESET     = "Zurücksetzen"
  L.STATS_RESET_HINT = "Shift-Klick, um die Statistik dieses Charakters wirklich zurückzusetzen."
  L.OPT_STATS       = "Statistik anzeigen"
  L.UNKNOWN         = "unbekannt"
  L.PVP_LABEL       = "PvP"
  L.PVP_ARM         = "PvP: Klick"
  L.PVP_CONFIRM     = "Sicher? Klick"
  L.PVP_ARM_TIP     = "PvP-geflaggt! Der erste Klick entsperrt nur. Ein zweiter Klick innerhalb von 6 Sekunden bufft, und du wirst selbst geflaggt."
  L.PVP_ARMED       = "%s ist PvP-geflaggt. Innerhalb von %d Sekunden erneut klicken zum Buffen. Du wirst dabei selbst geflaggt."
  L.PVP_WARN        = "PvP-geflaggt: Wenn du diesen Spieler buffst, wirst du selbst auch für PvP markiert!"
  L.PVP_BLOCKED     = "PvP-geflaggt: wird laut deiner Einstellung nicht gebufft."
  L.PVP_CHAT        = "Achtung: %s ist PvP-geflaggt. Durch das Buffen wirst du selbst markiert."
  L.OPT_PVP         = "PvP-geflaggte Spieler (solange du nicht geflaggt bist): %s"
  L.PVPMODE_warn    = "warnen"
  L.PVPMODE_block   = "nicht buffen"
  L.OPT_ASK_LEVEL   = "Nur Spieler fragen, die höchstens %s Level unter mir sind"
  L.LEVEL_ANY       = "beliebig viele"
  L.QUEUE_YOU       = "Du"
  L.EYE_HIDE        = "Symbole über den Köpfen ausblenden (die Liste bleibt)"
  L.ASK_HIDE        = "Anfrage-Symbole („fragen“) ausblenden"
  L.ASK_SHOW        = "Anfrage-Symbole („fragen“) wieder anzeigen"
  L.EYE_SHOW        = "Symbole über den Köpfen wieder anzeigen"
  L.QUEUE_COLLAPSE  = "Liste einklappen"
  L.QUEUE_EXPAND    = "Liste ausklappen"
  L.QUEUE_EMPTY     = "Alle in der Nähe sind gebufft."
  L.OPT_QUEUE       = "Buff-Liste anzeigen (feste Leiste, zum Verschieben ziehen)"
  L.OPT_QUEUE_LOCK  = "Buff-Liste fixieren"
  L.OPT_NEXT_NOTE   = "Tipp: /barter bindnext TASTE legt eine Taste fest, die den obersten Spieler in Reichweite aus der Liste bufft. Mehrmals drücken bufft alle."
  L.OPT_ASK_REMAIN  = "Erneut fragen, wenn mein Buff weniger als %s Min. hat"
  L.NEXT_USAGE      = "Aufruf: /barter bindnext <TASTE>, z. B. /barter bindnext G"
  L.NEXT_SET        = "Taste %s bufft jetzt den nächsten Spieler aus der Buff-Liste."
  L.OPT_MINIMAP     = "Minimap-Symbol anzeigen"
  L.MM_LEFT         = "Linksklick: Einstellungen"
  L.MM_RIGHT        = "Rechtsklick: Statistik"
  L.MM_SHIFT        = "Shift + Klick: Buff-Liste ein- oder ausblenden"
  L.MM_DRAG         = "Ziehen zum Verschieben"
  L.DISPEL_Magic    = "Magie"
  L.DISPEL_Curse    = "Fluch"
  L.DISPEL_Disease  = "Krankheit"
  L.DISPEL_Poison   = "Gift"
  L.STATE_DISPEL    = "Klicken zum Entfernen mit %s"
  L.OPT_DISPEL      = "Krankheiten, Gifte, Flüche und Magie anzeigen, die du entfernen kannst (außerhalb des Kampfes)"
  L.OPT_OFF_CITY    = "In Hauptstädten: keine Symbole über den Köpfen, Buff-Liste eingeklappt"
  L.QUEUE_CITY_TAG  = "Stadt"
  L.CITY_VISIT      = "Gilt nur für diesen Stadtbesuch. Beim nächsten Betreten einer Stadt ist es wieder aus."
  L.QUEUE_CITY      = "In Hauptstädten startet die Liste eingeklappt. Aufklappen zeigt die Spieler."
  L.OPT_OFF_DUNGEON = "In Dungeons ausschalten"
  L.OPT_OFF_RAID    = "In Schlachtzügen ausschalten"
  L.OPT_OFF_PVP     = "In Schlachtfeldern und Arenen ausschalten"
  L.OPT_THANK       = "Spielern danken, die mich buffen (höchstens alle 30 Minuten pro Spieler)"
  L.OPT_THANK_MODE  = "Danken per: %s (klicken zum Ändern)"
  L.THANKMODE_emote = "/danke-Emote"
  L.THANKMODE_whisper = "Flüstern"
  L.OPT_THANK_TEXT  = "Dankes-Flüstern ({name}, {buff}, {me})"
  L.OPT_MSG_GROUP   = "Diese automatischen Nachrichten auch an Gruppen- und Raidmitglieder schicken"
  L.OPT_PLATE_ICONS = "Buff-Symbole über den Köpfen anzeigen (aus: nur die Buff-Liste)"
  L.REQ_POPUP_TITLE = "Buff-Anfrage"
  L.REQ_POPUP       = "%s bittet dich um %s."
  L.REQ_POPUP_BUFF  = "Buffen"
  L.REQ_POPUP_NO    = "Nein danke"
  L.OPT_ACCEPT_REQ  = "Buff-Anfragen anderer BuffBarter-Nutzer annehmen (Fenster mit Buff-Knopf)"
  L.OPT_ONECLICK    = "Ein Klick bufft: das Symbol wählt den Spieler kurz an, wirkt und wechselt zurück"
  L.OPT_REQUEST     = "Anfrage-Symbole: Priester, Magier, Druiden oder Paladine anklicken und um ihren Buff bitten"
  L.OPT_REQUEST_TEXT = "Text für Anfragen per Klick ({name}, {ask}, {me})"
  L.REQ_LABEL       = "fragen"
  L.REQ_ASKED       = "gefragt"
  L.REQ_TIP         = "Klick: %s anflüstern und um diesen Buff bitten"
  L.REQ_TIP_ASKED   = "Schon gefragt. Erneut möglich in %d Min."
  L.REQ_NO_WHISPER  = "Flüstern ist hier nicht möglich (in Instanzen)."
  L.DEMO_ON  = "Demo '%s' angezeigt (erfundene Spieler, es wird nichts gewirkt oder gesendet). /barter demo off beendet sie."
  L.DEMO_OFF = "Demo beendet."
  L.DEMO_HELP = {
    "/barter demo list     Buff-Liste mit Beispielspielern",
    "/barter demo icons    alle Symbol-Zustände nebeneinander (über deinem Ziel, sonst über dir)",
    "/barter demo ask      Buff-Symbol plus Anfrage-Symbol",
    "/barter demo pvp      PvP-geflaggter Spieler: Symbol, Listenzeile, Chat-Warnung",
    "/barter demo dispel   entfernbarer Debuff: Symbol und Listenzeile",
    "/barter demo whisper  Beispiel-Flüstern im Chat (Rückfrage, Anfrage, Dank)",
    "/barter demo request  Fenster für Buff-Anfragen",
    "/barter demo city     eingeklappte Liste in einer Hauptstadt",
    "/barter demo all      alles auf einmal (ein Screenshot zeigt alles)",
    "/barter demo off      Demo beenden",
  }
  L.HELP = {
    "/barter            Einstellungen öffnen",
    "/barter toggle     Symbole an/aus",
    "/barter minimap    Minimap-Symbol an/aus",
    "/barter list       Buff-Liste an/aus",
    "/barter icons      Symbole über den Köpfen an/aus",
    "/barter preview    Flüsternachricht für dein Ziel anzeigen",
    "/barter testrequest Anfrage-Fenster mit dir als Absender anzeigen",
    "/barter demo       Beispielszenen für Screenshots (/barter demo zeigt die Liste)",
    "/barter stats      Statistik",
    "/barter lang de|en Flüstersprache für dein Ziel",
    "/barter bind TASTE Taste, die den Spieler unter der Maus bufft (sonst Ziel)",
    "/barter unbind     Taste wieder entfernen",
    "/barter bindnext TASTE Taste, die den nächsten Spieler der Buff-Liste bufft",
    "/barter debug      Klick-Diagnose an/aus",
    "/barter scan       Buffs (mit Spell-ID) auf Ziel oder dir auflisten",
    "/barter spells     deine bekannten Buffs auflisten",
    "/barter camp F ID  Lagerbuff-ID als schwächere Form von Familie F eintragen",
    "/barter friendly   freundliche Namensplaketten einschalten",
    "/barter strangers  Knöpfe für Spieler außerhalb der Gruppe an/aus",
    "/barter reset      Einstellungen zurücksetzen",
  }
end
