# Needed mats

Crafters can list the materials they still need, for leveling a profession or a big craft. Everyone in the guild with EPU then sees it on that item's tooltip, so the stack goes to a guildmate instead of a vendor or the auction house:

> Needed by: Tyler (x20), Ana (x5), Bo

Online guildmates are green, an amount shows when one was given, and after three names the line ends with "+N more". Your own characters' entries come first, as "you".

The main window has a **Needed mats** page under **Professions** that lists every material guildmates need, with who needs it and how many. Check it before a vendor or auction house run.

## Adding and removing

- Press **My needed mats** on the Needed mats page, open **Member tools → Needed mats**, or type `/epu mats`. Shift-click or drag a material into the box, type an amount if you want one, and press **Add**. **Remove** takes it off again.
- Or type `/epu mats add [item] 20` (shift-click the item into the chat line). `/epu mats [item]` works too, and the amount is optional.
- `/epu mats remove [item]`, `/epu mats list` and `/epu mats clear` (your whole list).

Each character has its own list, up to 40 materials. EPU fills in the profession from your shared recipes when one of them uses the material. Type it after the amount to choose it yourself: `/epu mats add [item] 20 Tailoring`.

## Already in the guild bank

Press **In the guild bank** on the Needed mats page, or type `/epu mats bank`, to see which needed materials the bank already holds: the in-game guild bank and the bank alts. Each line shows the material, how many are needed and for whom, and where the bank keeps it, for example "In the bank: Guild Bank (Mats) 27, Epu Bank 12". Guild bank tabs show once you've opened the guild bank on that character; before that it shows the guild bank's total.

Each line has one button:

- **Pull** (at the open guild bank): takes what's still needed straight out of the guild bank into your bags, one stack at a time. With no amount on the list it takes one stack. The game decides what you may take: only tabs your rank can withdraw from, and only as many stacks as that tab's daily withdrawal limit has left. What you take counts toward your list, like anything else that arrives in your bags.
- **Request**: when it can't be pulled right now (the guild bank is closed, your rank has no withdrawals left on that tab, or only a bank alt holds it), it files a normal bank request for what's needed, up to what the bank holds. Bank managers see it on the Requests page.
- **Requested**: there's already an open request for it, so the button doesn't make another.

Members get the button on their own entries. Officers and bank managers get it on everyone's: at the open guild bank, **Pull** fills the member's request (making one, or approving the one that was waiting) and moves it into your bags, ready for **Mail it** on the request. With the bank closed, **Request** makes the approved request in the member's name, to send from a bank alt or pull later.

## When an entry comes off

- **You have what you asked for.** With an amount, EPU counts what arrives in your bags after you add it (loot, mail, trades, the auction house). Using some for crafting doesn't undo that progress, and moving your own stock between bank and bags doesn't count. Once the amount is in, it comes off your list and you get one chat line. Without an amount, it stays until you remove it.
- **You remove it,** in the window or with `/epu mats remove`.
- **An officer clears it.** Officers see a **Clear** button on everyone's entries in the Needed mats window. The member is told who cleared what.
- **Nobody has seen the list for 30 days.** Your client re-sends your list when you log in, so it only ages out if that character hasn't been online for a month. Lists from people who left the guild are never shown.

## At vendors and the auction house

- **Auto-sell never sells a needed material.** If a grey item is on anyone's needed mats list (yours included), EPU's auto-sell skips it and says how many it kept.
- **Opening a vendor** prints one chat line listing the needed mats in your bags and who needs them, for example "Needed mats in your bags, so don't sell: [Linen Cloth] (Tyler (x20))".
- **Selling one by hand** (right-click at a vendor) prints who needs it and reminds you that the vendor's **Buyback** tab gets it back. EPU can't stop the sale itself without breaking the game's bag buttons, so the warning comes as you sell.
- **The auction house** warns as soon as you put a needed material in the sell slot, before you post it. On clients with the newer auction house, the warning comes when you post, with a reminder that you can cancel it on the Auctions tab.

Turn these warnings off in the main window under **Settings → Travel, vendor and tooltips** (or `/epu qol`): **Warn Before Selling or Auctioning a Mat a Guildmate Needs**. Auto-sell keeps needed mats either way.

## Sync

Lists sync like shared gathering spots: a member can only publish their own, officers keep the guild's copy and pass it to members who log in later, and `/epu tooltips` turns the tooltip line off along with EPU's other tooltip lines. Guildmates need this version of EPU to see or share lists.

## On Discord

If your officers run the EPU Discord companion, it can post a short **Guild needs** list once a day from these lists (who needs what, and how many), and anyone can type `/neededmats` in Discord to see it. Your character name and your list show there. Setup is in the [companion README](../epu-discord/README.md#daily-guild-needs-post).
