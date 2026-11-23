# Needed mats

Crafters can list the materials they still need, for leveling a profession or a big craft. Everyone in the guild with EPU then sees it on that item's tooltip, so the stack goes to a guildmate instead of a vendor or the auction house:

> Needed by: Tyler (x20), Ana (x5), Bo

Online guildmates are green, an amount shows when one was given, and after three names the line ends with "+N more". Your own characters' entries come first, as "you".

## Adding and removing

- Open **Member tools → Needed mats** in the sidebar, or type `/epu mats`. Shift-click or drag a material into the box, type an amount if you want one, and press **Add**. **Remove** takes it off again.
- Or type `/epu mats add [item] 20` (shift-click the item into the chat line). `/epu mats [item]` works too, and the amount is optional.
- `/epu mats remove [item]`, `/epu mats list` and `/epu mats clear` (your whole list).

Each character has its own list, up to 40 materials. EPU fills in the profession from your shared recipes when one of them uses the material. Type it after the amount to choose it yourself: `/epu mats add [item] 20 Tailoring`.

## When an entry comes off

- **You have what you asked for.** With an amount, EPU counts what arrives in your bags after you add it (loot, mail, trades, the auction house). Using some for crafting doesn't undo that progress, and moving your own stock between bank and bags doesn't count. Once the amount is in, it comes off your list and you get one chat line. Without an amount, it stays until you remove it.
- **You remove it,** in the window or with `/epu mats remove`.
- **An officer clears it.** Officers see a **Clear** button on everyone's entries in the Needed mats window. The member is told who cleared what.
- **Nobody has seen the list for 30 days.** Your client re-sends your list when you log in, so it only ages out if that character hasn't been online for a month. Lists from people who left the guild are never shown.

## Sync

Lists sync like shared gathering spots: a member can only publish their own, officers keep the guild's copy and pass it to members who log in later, and `/epu tooltips` turns the tooltip line off along with EPU's other tooltip lines. Guildmates need this version of EPU to see or share lists.
