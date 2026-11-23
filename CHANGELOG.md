# BuffBarter

## 1.1.1

- Low level players are no longer asked for buffs they cannot cast yet. A level 12 paladin is asked for Might instead of Kings, and a level 10 priest who buffed you is not asked for a spell they do not have. Players below level 4 are never asked, since even level 1 buffs have to be bought from the trainer first. This applies to the request icons and to asking back.

## 1.1.0

- Buff requests between BuffBarter users: when you ask someone who also runs BuffBarter, a small window with a Buff button opens on their side. One click buffs you. Limited to one request per player every two minutes, can be switched off in the settings.
- `/barter testrequest` shows that window with yourself as the sender.
- `/barter demo`: example scenes with invented players for screenshots (`/barter demo all` shows everything at once). Nothing is cast or sent.
- Debuff colors fixed: magic, curse, disease and poison have their own colors again on the modern client.
- Request icons fall back to the spell texture if the spell info is not cached yet.

## 1.0.0

- Buff list: a fixed, movable list of everyone nearby who needs a buff, yourself included. Click a row to buff.
- "Next" key (`/barter bindnext KEY`): buffs the next player in range from the list.
- Remove diseases, poisons, curses and magic out of combat with one click.
- Low level players automatically get the highest rank they can receive.
- PvP flagged players need a confirming second click.
- Thank players who buff you, with your own whisper text or a /thank emote.
- Asking for a buff back after buffing is now opt-in.
- Capital cities: icons off and the list folded, switchable per visit.
- Minimap icon, sliders for level and remaining time, off switches for dungeons, raids and PvP.
- Statistics window fixes.
