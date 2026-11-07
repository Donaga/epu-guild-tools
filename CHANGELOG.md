# Changelog

## 0.9.9

- **Donate panel at the guild bank vault.** The same panel now opens beside the guild bank, listing needed and useful items by category. Pick items and amounts, then press **Deposit**: they go into empty slots of the tab you're viewing (part of a stack if that's what you picked). Officers' addons record deposits from the guild bank log as donations, as before.
- **Give gold in set amounts.** +5s, +10s, +20s and +1g buttons on the donate panel (right-click takes it back off). At the mailbox the gold goes into the mail, and the letter lists what's being donated. At the vault it's deposited.
- **The donate panel closes when the mailbox (or guild bank) closes.**
- **Fewer announcement pop-ups at login.** One pop-up at most: the newest announcement if you haven't read it, plus how many others are unread. If you've read the newest, you just get a line in chat. The message of the day no longer pops up, since the game already shows it in chat.
- **Fewer repeat syncs.** Members no longer re-ask for data every 15 minutes when the newest record the officer holds is their own.

## 0.9.8

- **Suggestions as you type.**
  - **For box (officers):** guild members whose first or last name starts with what you've typed, online first.
  - **Item box (requests and needs):** items the guild deals with (bank stock, needs, recipes and their materials, past requests and donations, your bags). Shown with icons and how many the bank has.
  - **Picking one:** Tab or a click fills it in. Up/Down choose, then Enter. Enter alone picks it only when there's one match.
- **Fixed: the request form's boxes overlapped** when the officer For box was showing. The boxes now size to fit, and the item box's hint shortens when space is tight.
- **Officers' sidebar status** now reads "Officer copy" instead of "Waiting for guild data". Members sync from your copy.

## 0.9.7

- **Officers can make requests for other members.**
  - On the Requests page, officers get a **For** box. Type a guildmate's name and the request is filed under their name.
  - Part of a name works if it matches only one member. If it matches several, the addon lists them.
  - These requests are approved right away and marked with who added them. The member gets a notice, and the request shows up as theirs.
  - From the **Roster**, open a member and click **Request for [name]** to open the form with their name filled in.

## 0.9.6

- **Fixed: a bank character's bank wasn't counted, only their bags.** Newer game clients number bank bags differently (and add a reagent bag), so the addon now asks the game which containers are the bank. Open the bank once on the bank character to record it; it's remembered between visits and updated each time you go back. The account-wide bank isn't counted.

## 0.9.5

- **Donate panel at the mailbox, reworked.**
  - It now lists what the bank needs (always first), crafting materials, recipes, consumables (potions, elixirs, scrolls, bandages, food), bags and quivers, gems, reagents, ammo, and green-or-better Bind on Equip gear.
  - Soulbound items, quest items and the Hearthstone are never listed.
  - Items are grouped by category (Bank needs, Cloth, Leather, Metal & Stone, Herbs and so on).
  - The panel is taller and scrolls with the mouse wheel, so nothing gets cut off.
  - "Show everything (+N)" adds the rest of your tradeable items, such as white gear and grey junk.
  - To change an amount with the wheel, hold Ctrl.

## 0.9.4

- **Fixed: Needs, Shopping, Bank, Requests, Donations and Recipes wouldn't load for some players.** Their game only has the newer item functions (`C_Item`), and the addon used the old names, which exist only when the game's "deprecated API" fallback is on. The addon now uses the new ones and falls back to the old.
- **Clearer errors.** If a page can't load, it says which page, what went wrong in plain words, where in the addon, and the addon version, so a screenshot is all an officer needs. The same details go to chat.
- One odd item in the synced bank data can no longer take down the whole Bank page.

## 0.9.3

- **Fixed: the Needs page was blank for some players** (or kept showing the last page you had open). It used a game function that WoW: Forever has moved. A page that ever hits an error now says so instead of showing stale rows.
- **Syncing runs by itself.** At login the addon keeps trying until the guild has loaded, then asks for updates. It asks again when an officer comes online, after an officer's 15-minute check-in shows something new, and every 15 minutes while it's still missing data. `/epu sync` is only a backup now.
- **Fixed: officer data could be thrown away right after login** if it arrived before the guild roster had loaded. It's now held until the roster loads.
- **Sync arrives in pieces, most important first:** needs and bank, then requests and donations, then announcements, then crafters and recipes. Each piece is kept as it arrives, so a lost message only costs that piece, and it's re-asked automatically.
- **No officer online? Guildmates help.** A member who already has the guild's data passes it on to someone who has none. It's marked **Unconfirmed** in the sidebar and footer until an officer's addon checks it. Passed-on data only fills gaps, never overrides real data, never pops up announcements, and is never passed on again. Anything an officer doesn't have is dropped.
- **New Sync tab:** when each member last synced, from whom, what came across, and their addon version (older versions in red). *This PC* shows your own sync history. Hover the status at the bottom of the sidebar for details; click it to sync now.

## 0.9.2

- Fixed: "Interface action failed because of an AddOn". Announcements and update notices now use the addon's own pop-up instead of Blizzard's shared dialog boxes, which an addon can taint for Blizzard's own dialogs. The addon also no longer changes the guild window's "Show offline members" setting.

## 0.9.1

- **Fixed: members saw empty pages.** The game limits how fast an addon can send messages (a short burst, then about one a second). The addon sent faster than that and didn't notice when the game refused a message, so the big first sync to a member lost pieces and was thrown away. It now paces itself under the limit and resends anything refused. Officers especially should update, since their addon is what sends the guild's data.
- Empty pages tell members when they're still waiting for guild data, and that `/epu sync` asks again.

## 0.9.0

- EPU Guild Tools is on CurseForge: https://www.curseforge.com/wow/addons/epu-guild-tools — now the recommended way to install and stay updated. Every release uploads there automatically.
- The in-game update notice, Discord how-to, `/download`, release posts and READMEs point to CurseForge first; WowUp and the updater still work.

## 0.8.9

- Fixed: shift-clicking an item didn't fill the item box on Forever. It now works without clicking into the box first.
- Fixed: dragging an item onto the box. You can also click the box (or anywhere on the bottom bar) with an item on your cursor.

## 0.8.8

- A guild bank with no tabs and no gold isn't listed as an empty "Guild Bank" holder anymore.
- Gold shows as gold, silver and copper (it was rounded down to whole gold on Forever).

## 0.8.7

- Bank page: items grouped by category (Cloth, Herbs, Metal & Stone, Consumables, Bags, Weapons & Armor and so on), most plentiful first, with a category dropdown.
- Discord: the status post groups the bank the same way, with an emoji per category.

## 0.8.6

- Bank stock leaves out soulbound items (Hearthstone, bind-on-pickup gear) and quest items, since they can't be given away.
- Discord: the status post lists what's in the bank.

## 0.8.5

- Fixed: Crafters showed "No profession data yet" on WoW: Forever. Professions are now read the way Forever lists them, and update when you learn or skill up a profession.
- Recipe scanning falls back to the modern profession window when the old one has nothing.

## 0.8.4

- Fixed: "EPUGuild has been blocked from an action only available to the Blizzard UI". The addon no longer rewrites Blizzard's pop-up dialog table or replaces Blizzard's mail functions; it hooks them the safe way instead. Mail donation logging and auto-fill work as before.

## 0.8.3

- Announcements copied from Discord: `@everyone`/`@here` pings are left out (so they don't become the title), older posts appear in News quietly instead of popping up one after another, and each keeps its original Discord date.

## 0.8.2

- The EPU crest replaces the placeholder bag icon: window header, minimap button, the AddOns list, pop-up notices, the welcome card and the mailbox Donate panel.
- Discord: the crest appears on the status post, how-to post, `/download` and announcements.

## 0.8.1

- WowUp: releases now tell WowUp they're for WoW: Forever, so Install from URL finds the right download. Nothing else changed.

## 0.8.0

- **Roster:** everyone in the guild with level, class, zone or last seen. Filters for online, *near my level* and role. Whisper or invite from a member's details.
- **My profile:** set your roles (tank/healer/DPS) and a "looking for" note.
- **News:** officer announcements plus guild milestones (every 10 levels, first mount, profession ranks, big donations, new members), with pop-ups for guildmates online.
- **Announcements:** pop up for everyone at their next login until read. Post from News or Discord's `/announce`; mirrored to Discord, including edits and removals.
- **Officer review:** join date, recent levels, donations and requests, *Inactive* and *Promote?* tags, a review filter on the Roster, and a promotion reminder on the Officer page (labeled boxes plus the rule in plain words).
- **Officer notes and log:** private notes on members, and a log of officer actions. Both stay on the officer channel, so members never receive them.
- The Officer page scrolls, and its tools wrap onto a second line.
- **Pulls in existing announcements:** posts in the Discord announcements channel (recent ones too) are copied into News and pop up in game; edits and deletions follow. The in-game guild message of the day and guild info show at the top of News, the message of the day pops up when it changes, and the bot mirrors it to Discord.
- Discord: milestones post to a feed channel, announcements to an announcements channel, `/announce` for officers, and the how-to post covers the new pages.

## 0.7.0

- **Craft requests:** ask a guildmate to craft a recipe from its details, choosing who provides the materials. The crafter gets a pop-up and accepts or declines; mailing or trading what they made marks it made. Shown under Requests (*Crafts* filter) and in Discord. **Mail materials** fills the mail to the crafter.
- **Materials:** recipe details list reagents, what the bank holds and how many crafts that covers. Officers can stock the bank for 5 crafts in one click. Bank-paid materials for accepted crafts go on the shopping list.
- **Skill-up colors:** see who would still gain a skill point from a recipe, and filter Recipes to those.
- **Tooltips:** crafted items list guild crafters; patterns and recipes show whether anyone in the guild knows them.
- **Profession coverage** on the Officer page: professions nobody has, ones without a guild crafter, and a full breakdown.
- Crafters and recipes show when each crafter's list was last updated.
- Crafters gets the same profession dropdown as Recipes.
- Discord: craft request posts, crafts count on the status post, `/craft` shows materials and skill-ups, and a how-to section on getting things crafted.
- Profession scanning also understands the modern profession window, in case Forever uses it.
- Requests: status filter and sort are dropdowns, so the toolbar no longer runs into itself on smaller windows. Toolbar buttons size to their labels.
- Fixed: dropdown choices could sit under the "click outside to close" layer.
- Fixed: the addon could error at load if the game doesn't have the old Classic crafting events.

## 0.6.1

- Recipes: the profession filter is now a dropdown menu showing every profession with its recipe count, instead of clicking through them one at a time. Click outside or press Escape to close it.

## 0.6.0
- Recipes section: every craftable (non-BoP) recipe in the guild, searchable, filterable by profession, online and guild crafters; details list who can make it with Whisper buttons.
- Crafters share their recipe lists when they open a profession window (and again only when it changes).
- Officers can mark guild crafters per profession; they get a star and are listed first.
- Discord: `/craft` shows who can make an item.

## 0.5.0
- Item tooltips show what the guild bank needs or holds, and your own request's status.
- Gold coin on items in your bags that the bank needs (Blizzard bags and Baganator).
- Donate panel at the mailbox: choose items and amounts with -/+, mouse wheel or Max; Fill mail addresses and attaches only what you picked.
- Pop-up notices when your request is approved, filled or declined; officers get one for new requests (not for old ones caught up at login).
- Welcome card the first time the window opens (with a main-character picker for players with alts).
- Details panel scrolls instead of overflowing on smaller windows; slightly larger minimum window size.

## 0.4.0
- Updates without CurseForge: a one-click Windows updater (optionally runs at startup), an in-game popup when a guildmate has a newer version, Discord release announcements and `/download`, and WowUp support (Install from URL).
- New window: flat dark style, sidebar with counts, search, request filters (status, Mine, sort), real item icons with quality borders, status pills, progress bars, resizable (`/epu scale`, `/epu resetwindow`).
- Details panel on every row: edit requests (quantity, note, deliver-to, any status incl. reopening), edit needs, void mistaken donations.
- Mail it: fills in a mail for an approved request from your bags (splitting stacks); Send marks it filled.
- Officer page: trusted ranks, bank toggle, per-player open request limit (synced), Discord inbox, post needs, full sync, tidy finished requests.
- Discord: `/request` autocompletes every WoW Forever item by name, from the game's item table (via wago.tools), cached weekly with an `items.csv` fallback.
- Discord: requests by Wowhead link show the item name from the link until the game has seen it; posts link to Wowhead's Forever pages.
- Discord: pinned "How to use the Guild Bank bot" post (kept current on each bot start) and `/help`.
- Mains and alts: the addon groups each player's characters (shared with the guild), labels alts, and counts donors per player. `/epu main`, `/epu alts`.
- Requests can be delivered to any of your characters (**For:** button; Discord `/request ... character:`). Auto-fill matches that character.
- Discord: link several characters (linking one pulls in the rest of your group), `/unlink`.
- Discord companion: `testkit.py` for testing the bot against a fake WoW folder before you can log in.
- WoW: Forever two-part names: characters are tracked by "First Surname" everywhere (sync, trust, requests, donations), so two members with the same first name are never mixed up. Mail, trade and guild bank log names fall back to a first name only when exactly one member has it.
- Discord `/link` autocompletes from the guild roster and resolves full or unique first names.
- Discord companion: pinned "Guild Bank Status" post, edited in place on every refresh (needs with stock levels, shopping list, gold, open requests).

## 0.3.0
- Reads the in-game guild bank (all viewable tabs and gold) when an officer opens it, and counts it alongside bank alts.
- Guild bank deposit log becomes donation records, without duplicates.
- Discord companion (`epu-discord/`): request posts that update as requests change, `/request` from Discord, officer Approve/Reject buttons, `/needs`, `/bank`, `/requests`, donation thank-yous.
- `/epu save` to push the latest to the Discord companion.

## 0.2.0
- Needs: restock minimums vs one-time goals (goals close themselves); red flag under 50%.
- Shopping tab: shortfalls plus approved requests, exportable to an Auctionator shopping list.
- Requests: pending, approved or rejected, then filled; officers' requests auto-approve; mailing or trading the item auto-fills.

## 0.1.0
- Needs, Bank, Requests, Donations and Crafters tabs; recipe lookup; guild sync over addon messages.
