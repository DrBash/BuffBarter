# BuffBarter

![BuffBarter](art/BuffBarter_banner_1200x400.png)

**Buff strangers. Get buffed back.**

BuffBarter makes buffing in WoW Forever quick and friendly. It shows who nearby is missing one of your buffs, buffs them with one click, removes diseases, poisons, curses and magic, warns you before you get PvP flagged and lets every class ask others for buffs. Between BuffBarter users a request even arrives as a window with a buff button. A statistics window shows how much you gave, how much you got and who returned the favor.

Made for **WoW Forever**, including its new camp buffs.

## Who can use it

| Your class | What you get |
|---|---|
| Paladin | Blessings, respecting "one blessing per paladin" (shows when a click would replace your own blessing), Cleanse or Purify |
| Priest | Power Word: Fortitude, Divine Spirit for mana users, Dispel Magic, Cure or Abolish Disease |
| Mage | Arcane Intellect (never offered to warriors and rogues), Remove Lesser Curse |
| Druid | Mark of the Wild, Thorns for players with the tank role, Remove Curse, Cure or Abolish Poison |
| Shaman | Cure Poison, Cure Disease |
| Every class | One-click buff requests, thank-you whispers and statistics |

## Features

### Buff icons above players
- Shows the first buff a player is missing, based on sensible class rules (no Wisdom for warriors, no Might for casters, Kings first for tanks).
- **Click the icon to buff.** BuffBarter briefly targets the player, casts and switches back to your previous target.
- **The right rank for every level:** low level players automatically get the highest rank they can receive.
- **Orange "Camp":** the player only has the weaker camp version. Your buff replaces it.
- **Yellow timer:** your own buff runs out soon.
- **Purple "Swap"** (paladins): a click would replace your current blessing on that player.
- Faded icons for players out of range, and a generous click area for players on the move.

### Buff list and "next" key
- A fixed, movable list of everybody nearby who needs a buff, yourself included, with class colors and levels. Click a row to buff that player.
- Bind a key with `/barter bindnext KEY` and press it repeatedly to buff everyone in range from top to bottom.
- Buttons in the list header switch the icons above players and the request icons on or off, or fold the list.

### Remove debuffs
Out of combat, BuffBarter also shows diseases, poisons, curses and magic you can remove, in their type color. One click cleanses the player with your best removal spell.

### PvP warning
If a player is PvP flagged and you are not, the icon shows a faction emblem and a red frame. The first click only unlocks it, a second click within a few seconds buffs. The "next" key never picks PvP flagged players. You can also skip them completely.

### Camp buff aware
WoW Forever camps hand out weaker copies of class buffs that do not stack with the real ones. BuffBarter treats them as "upgrade possible", or as "already buffed" if you prefer.

### Buff requests (every class)
A small "ask" icon appears next to priests, mages, druids and paladins near your level who can give you a buff you are missing or that runs out soon. One click sends a friendly whisper. A paladin who already blessed you is not asked for a second blessing, and nobody is asked for a buff they cannot have yet at their level (no Kings before 20, no Wisdom before 14).

### Buff requests between BuffBarter users
If the player you ask also uses BuffBarter, they do not just get a whisper: a small window pops up on their screen with your name, the buff and a **Buff** button. One click and you are buffed, no targeting needed. "No thanks" closes it. Requests are limited to one per player every two minutes and can be switched off in the settings. Try it yourself with `/barter testrequest`.

### Thanks and asking back
- When someone buffs you, BuffBarter can thank them with your own whisper or a /thank emote.
- Optionally (off by default) it asks players you buffed for their buff in return.
- Buffs are sent as clickable spell links, so everyone sees the right spell in their own language.
- At most once per player every 30 minutes, never inside instances, and not to your group or raid unless you want to.

### Statistics
`/barter stats` (or right click on the minimap icon) opens a window with:
- buffs given and received
- **buffed back rate:** how many of the players you buffed buffed you too
- **answer rate:** how many of your requests were answered
- breakdowns by class, race and buff with icons, and your most frequent buff partners

### Calm in crowded places
- In capital cities the icons above players and the request icons are off and the buff list starts folded. Unfold it or switch the icons on for that visit with one click.
- Optional off switches for dungeons, raids, battlegrounds and arenas.

## Settings

Type `/barter`, left click the minimap icon or open *Options > AddOns > BuffBarter* to:
- switch icons, one-click buffing, the buff list, request icons, debuff removal and the minimap icon on or off
- choose how camp buffs and PvP flagged players are handled
- set how far below your level a player may be to still be asked, and how little time a buff may have left before you ask again
- write your own whisper texts in English and German (placeholders: `{name}`, `{buff}`, `{ask}`, `{me}`)
- choose where BuffBarter switches off

## Commands

| Command | What it does |
|---|---|
| `/barter` | Open the settings |
| `/barter toggle` | BuffBarter on or off |
| `/barter list` | Buff list on or off |
| `/barter icons` | Icons above players on or off |
| `/barter minimap` | Minimap icon on or off |
| `/barter stats` | Statistics window |
| `/barter bindnext KEY` | Key that buffs the next player from the list |
| `/barter bind KEY` | Key that buffs the player under your mouse |
| `/barter preview` | Show the whisper your target would get |
| `/barter testrequest` | Show the buff request window with yourself as sender |
| `/barter demo` | Example scenes with invented players, e.g. `/barter demo all`. Nothing is cast or sent. |
| `/barter lang de` / `en` | Whisper language for your target |
| `/barter scan` | List buffs with spell IDs on your target |
| `/barter camp FAMILY ID` | Register a camp buff, e.g. `/barter camp KINGS 123456` |
| `/barter help` | All commands |

## Good to know

- **Fair play:** every cast needs your click or key press. BuffBarter never casts on its own.
- **Combat:** icons and the list are hidden in combat and come back afterwards.
- **Instances:** addons cannot whisper inside instances, and friendly nameplates may not be available there. The buff list still works.
- **Camp buffs:** if a camp buff is not recognised yet, use `/barter scan` near the camp and register it with `/barter camp`. Please post the IDs in the comments so they can be built in.

## Languages

English and German. Translations are welcome.

## Feedback

Found a bug or have an idea? Leave a comment on CurseForge or open an issue on GitHub.

## Releasing

Change the version in `VERSION` and push to `main`. GitHub creates the tag, builds the zip and uploads it to CurseForge. Versions with `beta` or `alpha` in the name are uploaded as beta or alpha files.
