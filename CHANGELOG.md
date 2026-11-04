# Changelog

## 0.8.3

- Announcements copied from Discord: @everyone/@here pings are left out (so they don't become the title), older posts appear in News quietly instead of popping up one after another, and each keeps its original Discord date.

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
