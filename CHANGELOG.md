# Changelog

## 0.37.0

A /reload is enough after updating: this version adds no new files.

- **Bank page: sort the list, filter by guild bank tab, and spot items in the wrong tab.** Two new buttons on the main window's **Bank** page (or `/epu banktabs`):
  - **Sort** orders the list **by category** (as before), **by name**, **most in bank**, **best quality**, **item level** or **by bank tab**. By bank tab lists each guild bank tab under its own heading, then each bank character, with what the tab holds and how many items in it look out of place. An item split across tabs shows under each tab with that tab's count.
  - **Where** shows one guild bank tab or one bank character (the count column then shows how many are there), or **Out of place in its tab**. Each item's row now says where it sits, such as "Tab 1: Mats 20 · Donlock 3", and search matches tab names too.
  - **Out of place** is worked out from the tab names: a tab named for something ("Herbs", "Recipes", "Gear", "Potions") holds that, a general "Mats" or "Trade goods" tab holds the trade goods no other tab is named for, and an unnamed tab holds whatever fills at least half of it. An item in another tab is marked, in orange, with the tab it belongs in, or that it's not what its tab is for when no tab holds its kind yet. Category headings say which tab keeps that category, and the item's details say the same. Nothing is moved; the hints are there to help officers keep tabs tidy. `/epu banktabs tidy` opens straight to the out-of-place list. Tabs come from the last time someone on your account opened the guild bank, so open it once after updating.
  - The sort, category, stock, quality and Where choices are saved for each character. **Reset** clears the filters and keeps the sort. On a narrow window the toolbar wraps onto a second row.
- **Also in this release: the pop-out Messenger's typing box can go at the bottom.** 0.36.1 wasn't released on its own, so its change ships here: a **Typing box: Top / Bottom** button in Chat settings (the messenger's **Opts** button, **Settings > Pop-out chat and log windows**, or `/epu logs`) moves the box and **Send** below the messages, the way most chat apps have it. Top stays the default.

## 0.36.1

A /reload is enough after updating: this version adds no new files.

- **Chat: put the typing box at the bottom of the pop-out Messenger.** A new **Typing box: Top / Bottom** button in Chat settings (the messenger's **Opts** button, **Settings > Pop-out chat and log windows** in the main window, or `/epu logs`; also **Pop-out typing box** in the Chat page's settings) moves the box and **Send** below the messages, the way most chat apps have it. The channel tabs stay at the top, the messages fill the space between, and **Find** opens its search box in the same place. It applies to the tabbed window and to one-window-per-person windows, takes effect at once, and is saved for each character. Top stays the default. Pair it with **Messages: Oldest on top** to keep the newest messages right above the box.

## 0.36.0

A /reload is enough after updating: this version adds no new files.

- **Rate bar: your session's live rates on a small toolbar** (`/epu bar`, the **Rate bar** tile in **Member tools**, or **Show rate bar** on the **Session** tab of Personal trackers). A small strip you can leave on screen while you play, instead of opening the trackers window. By default it shows **XP per hour**, **time to level** at that rate, **gold per hour** (looted coin plus the vendor value of looted items) and **session time**.
  - **Pick the stats** in its settings (right-click the bar, or `/epu bar settings`): also XP this session, level progress, rested XP, kills per hour, kills to level, net gold per hour (the change in the gold you carry, after spending), reputation per hour and honor per hour. XP stats hide themselves on a max-level character. Kills are the kills that gave you XP, counted from the game's "dies, you gain" XP message.
  - **Make it bigger or smaller** with **Smaller** and **Bigger** (60% to 200%) or `/epu bar scale 1.3`, lay it out **across** or **stacked**, and change how see-through the background is.
  - Drag it where you want it and **Lock in place** (`/epu bar lock`, `/epu bar unlock`). Where it sits and whether it shows are saved for each character; the stats, size and lock are the same on all of them. Hover for the full numbers, left-click for the Session tab, right-click for the settings.
  - It uses the Session tab's farming session, so **Pause**, **Resume** and **Reset Session** there (or `/epu bar pause`, `resume`, `reset`) act on the bar too. XP per hour no longer drops a level's worth of XP when you level up mid-session, and the Session tab now shows kills that gave XP.

## 0.35.0

**After updating, fully restart WoW once** (a /reload isn't enough): this version adds a new file to the addon.

- **Mail tools: Take all from one mail, and AH gold only** (`/epu mailtools`, or the **Mail tools** tile in **Member tools**).
  - **Take all** sits above a mail you open. It takes that mail's gold and then each of its items, one at a time, waiting for the server between takes, and leaves the rest of your inbox alone. It stops when your bags are full (and says what's still in the mail), when the server doesn't hand something over after a second try, or when you close the mailbox. It never pays cash on delivery: a COD mail keeps the button off and points you to Blizzard's Accept. Press **Stop** to stop partway.
  - **Collect AH gold** sits above the inbox (or **Collect AH gold now** in the Mail tools window, or `/epu ahgold` at a mailbox). It takes only the gold from auction house mail, sales and outbid refunds, and leaves expired, cancelled and won auctions in your inbox with their items. Auction mail is told apart by its invoice, the game's own auction subject lines and the fact that it can't be replied to, so gold players send you is never touched. When more mail waits on the server than the inbox shows, it says to reopen the mailbox and collect again.
  - The Mail tools window explains both and turns either button off or on.

## 0.34.1

- **Release announcements post again, and in the channel you pick.** The Discord companion waited for CurseForge to approve each release before announcing it, and when it couldn't see the approval it waited forever: EPU Guild Tools is unlisted on CurseForge, which the public mirror it asks (CFWidget) likely can't read, so 0.33.0 and 0.34.0 were never posted. Now it posts anyway once a release has been on GitHub for 12 hours without the bot seeing it approved (`"curseforge_wait_hours"`, `0` posts at once), and says once in its console why it couldn't ask CurseForge. A new `"release_channel_id"` setting sends release posts to a channel such as `#updates`; blank keeps the request channel. If the bot can't see that channel, the release stays unannounced and posts once it can.
- **The Discord companion updates itself.** When a new release comes out, the bot moves its git clone to it, reinstalls its Python packages if they changed and restarts on the new version, within half an hour and without anyone touching it. It only does this when it runs from a git clone that's on `main` with no local changes, and through `start.bat`; otherwise it logs why and keeps running the version it has. If the new version won't install or load, it goes back to the old one and waits for the next release. `config.json`, `state.json` and the bot's other local files are never touched. Each update is logged in `epu-discord/updates.log`. `"auto_update": false` turns it off. Update the bot by hand one last time to get this version (stop it, `git pull`, start `start.bat`); later releases arrive by themselves.
- **The companion keeps itself running.** `start.bat` now restarts the bot after a crash (waiting 10 seconds, up to 5 minutes if it keeps crashing), and a second copy refuses to start, so two windows never post everything twice. Run `Install-Autostart.ps1` once to start it minimized whenever you log in to Windows. Setup: [epu-discord/README.md](epu-discord/README.md#updates-and-starting-at-logon).

## 0.34.0

- **Rested XP across your alts.** A new **Rested XP** tab in Personal trackers (`/epu rested`, or the **Personal trackers** tile in **Member tools**) shows how much rested XP each of your characters on this realm has built up: as a share of a level, in bubbles and in XP, with how long until it's full. Each character saves its rested XP, level and whether it was resting when it logged out, and EPU estimates the rest from the classic rates: 5% of a level every 8 hours in an inn or city, a quarter of that anywhere else, up to 1.5 levels. The character you're on shows its real rested XP. Max-level characters are listed last. A character shows up once you've logged in on it with this version.
- **Spell rank checker** (`/epu ranks`, or the **Spell ranks** tile in **Member tools**). Forever doesn't put a new spell rank on your action bars when you train it, so buttons keep casting the old one. The checker compares every spell on your bars with the highest rank in your spellbook and lists the buttons that are behind, by bar and button, with the rank they can go to. **Update** puts the highest rank on one button and **Update all** does every listed button; both work only out of combat. For a lower rank you use on purpose, **Keep this rank** stops it being flagged on that character, and **Stop keeping** undoes it. After you log in and after you train, EPU says in chat once when a button is behind; **Remind me in chat** in the window turns that off. Macros aren't checked.
- **Quick groups ping guildmates near the level.** A new "Now" group on the Groups page (`/epu lfg`) now notifies guildmates whose level is within 3 of the group's range, the same way run requests already did. It follows your notification settings (instant, digest or off, quiet hours and mutes), and an edit to the group doesn't notify again. Help posts are unchanged.
- **The dungeon board on Discord.** The Discord companion posts quick groups, help posts and run requests from the Groups page as cards, with the levels, who's signed up by role and when the group ends, or the times a run request suits. Cards update as people sign up and grey out when the group closes, expires or becomes a guild event; guild events keep their own cards. It's on by default in the events channel, or the milestones channel if you have no events channel; `group_board_channel_id` picks another and `"group_board_post": false` turns it off. The bot sees posts when the game data on its PC is saved (logout or `/reload`) or when a sync helper uploads, so update sync helpers to carry board posts too. Setup: [epu-discord/README.md](epu-discord/README.md#dungeon-board-on-discord).
- **Leveling board** (`/epu levelboard`, or the **Leveling board** tile in **Member tools**). Who in the guild gained the most levels this week, Monday to Sunday, with each character's start and end level and alts shown with their main. **Last week** shows the week before. A level counts when your game sees it on the guild roster, so levels gained while you were offline count in the week you next log in. EPU now keeps three weeks of each guildmate's level changes instead of the last eight, so fast levelers are counted in full.
- **Weekly leveling board on Discord.** The Discord companion posts last week's board every Monday at 19:00 (this PC's clock), top three marked, in the guild needs channel unless you pick another, and skips a week when nobody gained a level. `/levelboard` shows this week so far privately. It's on by default; settings `leveling_board_post`, `leveling_board_channel_id`, `leveling_board_day`, `leveling_board_time` and `leveling_board_max` are in [epu-discord/README.md](epu-discord/README.md#weekly-leveling-board).
- **Bank gear for you** (`/epu bankgear`, **Gear for you** on the main window's **Bank** page, or the **Bank gear for you** tile in **Member tools**). Lists the weapons and armor the guild bank and bank alts hold that this character can use: the required level is yours or up to five levels ahead, the armor is the type your class wears (plate for warriors and paladins and mail for hunters and shamans from level 40), and the weapon is a type your class can train. Each item shows its slot and item level, whether you can wear it now or at which level, and whether it beats what you wear in that slot by item level (an empty slot counts as an upgrade). Upgrades come first, and **Upgrades only** hides the rest. Gear more than ten levels below you only shows when it's an upgrade. At the open guild bank **Pull** takes it into your bags, from tabs your rank can withdraw from; otherwise **Request** asks the bank managers for it. Details: [docs/bank-gear.md](docs/bank-gear.md).
- **Keys and attunements reach the whole guild.** Each member's dungeon keys, raid attunements, raid status (level, role, Drakefire Amulet, Fire Resistance) and camping stations now sync like needed mats: officers keep everyone's and hand them to whoever logs in later, so the **Readiness** tab shows guildmates who were offline when someone ticked a key. Before, they only reached whoever was online at that moment. Guildmates still on 0.33 keep seeing ticks from this version.
- **Keys and attunements tick themselves.** Keys in your bags, the Drakefire Amulet, and the Molten Core and Blackwing Lair attunement quests are picked up at login, when you turn in a quest and when your bags change. Custom Forever chains the game can't confirm stay a tick-box. Each new key or attunement is a guild milestone in **News** and on the Discord companion's milestones channel; the first scan after updating adds none, so existing keys don't flood the feed.
- **Raid attunements on the Readiness tab.** A section lists Onyxia's Lair, Molten Core and Blackwing Lair with your status, who in the guild is attuned and how many level 55+ guildmates still need each one.
- **Guild reputation.** The Readiness tab lists guildmates' standing with Argent Dawn, Timbermaw Hold, Cenarion Circle, Thorium Brotherhood, the Hydraxian Waterlords, Zandalar Tribe, Brood of Nozdormu and the Wintersaber Trainers. Turn sharing your own standing off with **Stop sharing** on the same page.
- **Dungeon waypoints fixed.** Hall of Thanes, The Drowned City, Krol'dok Stronghold, Blackmaw Hold and Shaper's Terrace pointed at placeholder spots; they now point at their entrances, in the Readiness tab and the zone guide. Quest givers in a city or another zone (Tinkmaster Overspark, Nogg, Varimathras, Nara Wildmane and others) now get a waypoint on their own map instead of the dungeon's zone.

## 0.33.0

- **Personal trackers** (`/epu trackers`, or the **Personal trackers** tile in **Member tools**). One window with five tabs for your own characters on this realm:
  - **Lockouts:** raid and dungeon lockouts for every character you've logged in, with boss progress and time to reset. `/epu lockouts` opens this tab.
  - **Cooldowns:** long profession cooldowns (Arcanite and the other transmutes, Mooncloth, Salt Shaker) for each character, with time left or READY, and a chat line at login for any that are ready. `/epu cds` opens this tab. A character's cooldowns are read when you log in on it and a few seconds after a cooldown changes, never during combat.
  - **Session:** a farming session with time played, XP per hour, gold looted and the vendor value of looted items, gold per hour, and the uncommon or better items you looted. Pause, Resume and Reset Session control it. It doesn't count kills, because the game no longer sends the message that would.
  - **Consumables:** a checklist of consumables with a target count each, showing how many you carry and how many your other characters hold, with quick presets for common potions, flasks and bandages.
  - **Rep & PvP:** reputation gained per faction this session, per hour and how far to the next rank, plus this session's honor and honorable kills.
- **Name mentions ignore contractions.** A mention word like "don" no longer matches "don't".

## 0.32.0

**Before you update (officers).** This version moves the Discord inbox into its own small addon, so do these in order:

1. On the PC that runs the Discord companion (bot), update EPU to this version first, then update the companion to this version and restart it. Once it sees this EPU installed, it makes the `EPUGuild_Inbox` addon folder and moves anything waiting in the old file.
2. Fully restart WoW once after that first run (a /reload isn't enough), so the game finds the new addon. Keep **EPU Guild Tools: Discord inbox** enabled in the AddOns list.
3. If other officers' PCs should carry Discord too, add `"officer": true` to each of them under `sync_helpers` in the bot's config.json, and have them install this version's sync helper.
4. Optional: turn on the daily guild needs post with `"guild_needs_post": true` and `"guild_needs_channel_id"` in the bot's config.json.
5. Optional: for the most reliable "approved on CurseForge" check before release announcements, add `"curseforge_api_key"` (from console.curseforge.com) and `"curseforge_project_id"` to the bot's config.json. Without them the bot uses a public mirror of the CurseForge page.

**Everyone:** if you used guild-paid auto-repair in 0.30.x or 0.31.x, it's now off until you turn it on again in **Travel, vendor and tooltips** (`/epu qol`).

- **Needed mats.** Crafters can list the materials they still need (`/epu mats`, or the new **Professions → Needed mats** page in the main window). Everyone in the guild sees it on the item's tooltip, for example "Needed by: Tyler (x20), Ana", so the stack goes to a guildmate instead of a vendor or the auction house. Lists are per character, up to 40 materials, with an optional amount; an entry comes off by itself once that many have arrived in your bags. Officers can clear entries, and a list ages out after 30 days without its character logging in. Details: [docs/needed-mats.md](docs/needed-mats.md).
- **Needed mats already in the bank.** **In the guild bank** on the Needed mats page (or `/epu mats bank`) lists every needed material the guild bank or a bank alt holds: how many, which guild bank tab, and who needs it. One button does the rest. At the open guild bank, **Pull** takes what you need straight into your bags, from tabs your rank can withdraw from and within today's withdrawal limit. Otherwise **Request** files a bank request for the bank managers. Officers and bank managers get the button on everyone's entries: Pull fills the member's request (approving it if it was waiting) and leaves it ready for **Mail it**. Details: [docs/needed-mats.md](docs/needed-mats.md#already-in-the-guild-bank).
- **Needed mats are safe at vendors and the auction house.** Auto-sell never sells a material on anyone's needed mats list. When a vendor opens, EPU lists the needed mats in your bags and who needs them; selling one by hand names who needed it and points you to the Buyback tab; and putting one in the auction sell slot warns you before you post. Turn the warnings off in **Settings → Travel, vendor and tooltips** (`/epu qol`).
- **Every tool opens from the main window.** **Member tools** has tiles for the **Zone guide**, **Leveling and dungeons** and **Gold and budget**. **Settings** has rows for the pop-out chat and log windows, **Info bars**, and **Travel, vendor and tooltips**. The slash commands still work.
- **Release announcements wait for CurseForge.** The Discord companion now posts a new EPU version once CurseForge has approved its file, instead of as soon as the GitHub release appears, so the CurseForge app already offers the update when guildmates see the post. It checks every 30 minutes and only marks a version announced once it has posted it. It reads CurseForge's own API when `curseforge_api_key` and `curseforge_project_id` are set, and otherwise a public mirror of the project page (CFWidget). `"announce_after_curseforge": false` posts at once, as before. Details: [epu-discord/README.md](epu-discord/README.md).
- **Daily guild needs post on Discord.** The Discord companion can post a short list once a day of the materials guildmates need, from their needed mats lists: most-wanted first, grouped by profession, with who needs each one and how many. `/neededmats` shows the same list privately any time. It's off until an officer turns it on in the bot's config.json (`guild_needs_post`, `guild_needs_channel_id`, `guild_needs_time`). Setup: [epu-discord/README.md](epu-discord/README.md#daily-guild-needs-post).
- **Guild-funded auto-repair is off until you turn it on.** 0.30.0 switched it on for everyone with repair rights, so the guild bank paid at every vendor without asking. If you want it, turn it on again in **Travel, vendor and tooltips** (`/epu qol`). When it's on, EPU checks what the guild can actually pay (today's limit and the gold in the bank); if it can't cover the repair, you pay instead of the repair failing. Bank alts never auto-sell or auto-repair.
- **The Combat Log window is gone.** It listened for combat messages the game no longer sends, so it never showed anything. Its window, its tab in the combined log window, its Chat Settings checkbox, its source for custom tabs, and `/epu combatlog` and `/epu logs combat` are removed. Settings it saved are cleared the first time you load this version; custom tabs keep their other sources.
- **EPU updates can't wipe what's waiting from Discord.** The Discord companion used to keep requests, approvals and guild chat from Discord in `EPUGuild\Inbox.lua`, and every update through CurseForge, WowUp or a folder copy replaced that folder, leaving the empty file EPU ships. The companion now keeps them in a small addon of its own beside EPU, **EPU Guild Tools: Discord inbox** (`Interface\AddOns\EPUGuild_Inbox`), which no EPU download contains. Update the companion with this version; it makes the folder and moves anything left in the old file. Restart the game once afterwards so WoW finds the new addon, and keep it enabled. EPU still reads the old file, so an officer on an older companion keeps working, and each update is applied once. The Officer page shows if the inbox addon is turned off, and officers get a chat reminder at login. Sync helpers move to it the same way. If Windows won't let the companion make the folder, see "Folder permissions" in the companion's README.
- **Any officer's PC can carry Discord, not only the one running the bot.** Discord approvals, `/announce`, onboarding steps and helper whitelist grants used to reach the game only when the officer whose PC runs the bot logged in, and in-game announcements, milestones and the guild MOTD reached Discord only from that officer's game. The organiser can now mark an officer's sync helper with `"officer": true` in the bot config; that helper carries the officer actions too and sends announcements, milestones and the MOTD back. They apply only on an officer's character. When several officers carry the same action, it changes one record, so Discord gets one post, and the bot drops it from its queue once any officer's game has applied it. Officers need the updated sync helper; older helpers keep getting member actions only. The bot itself still runs on one PC. Setup: [docs/guild-invites.md](docs/guild-invites.md#officer-helpers-any-officers-pc-can-carry-discord).
- **A guild bank deposit counts once when two officers log it.** When two officers or bank managers opened the guild bank close together, each logged the same deposits before the other's records arrived, so every gift showed twice in Donations, counted twice for top donors, and got two News shout-outs and two Discord thank-yous. Every client now spots the second copy (same person, item and amount within the log's 3-hour slack, logged by a different officer) and leaves it out of the list, the counts, News and Discord. It stays in the data so nobody logs it a third time. Two real identical gifts logged by one officer both still count, and one officer alone still logs everything. The donation's details show "also logged by another officer" on a hidden copy.
- **Dungeon readiness and raid prep reach the guild.** Since 0.29.0 they used the same message kinds as the guild map and quest sharing, so nobody ever received them. Everyone needs this version for readiness and raid status to show. A guildmate can no longer overwrite someone else's record.
- **Officer run log counts each run once.** Only one officer in the group logs a boss kill (before, each officer logged it, tripling attendance), runs only count when sent on officer chat, and entering a new instance starts a new run.
- **Raid prep and guild stats read roles from profiles**, so tanks and healers are counted again and the squad builder shows how many guildmates it's working with.
- **Leveling advisor** no longer stops with an error when a bank alt holds a listed item, and finds crafters again.
- **Gold tracker: gold you move isn't spending.** Gold mailed to (or taken from mail sent by) your own characters, and gold put in or taken out of the guild bank, no longer count as income or spending or against your daily and weekly budget. They show on their own "Moved, not earned or spent" line, in the breakdown and in the transaction list. Postage still counts as mail spending.
- **Gold tracker labels:** grey items sold at the same visit as a repair stay under Vendor, and the repair goes under Repairs.
- **Windows no longer grow over a long session.** The gold tracker (every time your gold changed), info bar settings, travel and vendor settings, chat settings, zone guide, leveling tools and needed mats window made new frames each time they redrew. They now reuse them, so memory use stays flat.
- **Slash commands typed in EPU chat run.** With "Enter key -> EPU chat" on, `/inv Name` or `/dance` typed in the EPU box was posted as text; now it runs.
- **Chat and log windows stay where you scrolled** while new lines arrive, and only follow new lines when you're at the newest one. Custom tabs set to oldest on top keep showing new lines after 100.
- **Log windows you moved in 0.29.x** reopen on screen instead of clamped to an edge.
- **Flight timer** waits until you're on the flight path before timing it, so it learns route times.
- **Hearthstone cooldown, tooltip sell price and stack size, and alt class colors** show again. The info bar Guild widget opens the online roster instead of the help text.
- **World Map guide button** shows and hides with the map during combat.

## 0.31.1

- Guide notices explain the five dungeon entries per hour limit and the Vampiric Embrace group healing adjustment.
- Method Skinning is available through skill 299 after review of its added later sections.

## 0.31.0

- **Gold & Budget tracker** (`/epu gold` or `/epu budget`). EPU sorts the gold you earn and spend into Loot & Quests, Vendor, Repairs, Auction House, Mail, Training & Riding, Flight Paths, Player Trade, Guild Bank and Other. Look at this session, today, 7 days, 30 days or everything, for this character or all of them, with a spending pie chart, a bar graph and a 7-day in-and-out trend. You can set a daily and weekly spending budget and get a chat warning when you reach it. The info bar Gold widget shows today's in and out and the budget left; right-click it to open the tracker.
- Floating log windows reopen where you left them after a reload.

## 0.30.1

- **Whispers in the pop-out chat window:** on the Tells tab, the conversation list shows whispers only, most recent first, with each person's online or offline status.

## 0.30.0

- **Info bars** (`/epu bars`). Add a bar to the top, bottom, left or right edge of the screen and choose what it shows: FPS, latency and addon memory, gold (with your alts' totals and this session's net), durability, bag space, currencies, reputation, XP and item level, clock, zone and coordinates, movement speed, Hearthstone, guildmates and friends online, mail, EPU chat and events, and volume. Each has a tooltip and a click action. Bars can be resized, faded, hidden in combat or shown only on mouseover.
- **Travel, vendor and tooltips** (`/epu qol`): your and the cursor's coordinates on the World Map, waypoints with `/epu way x y [label]` (and `/epu way clear`), a flight timer that learns how long each route takes, auto-sell grey items and auto-repair at vendors (hold Shift to skip), and item tooltips with how many your alts and banks hold, the sell price and the stack size.

## 0.29.4

- **Chat order:** messages sent in the same second by the same person no longer swap places.
- **Class-colored names** in chat and in custom pop-out tabs.
- **Log windows** stay under your bags and panels, aren't closed by Esc, can be resized from the corner, and remember their size, place and whether they're open. Chat Settings can combine them into one window with tabs.

## 0.29.3

- **Enter key to EPU chat** (optional, in Options and Chat Settings): Enter opens EPU's chat box instead of the game's.
- Chat and log windows scroll to new lines whichever way they're sorted.
- The pop-out Chat Settings window has every chat setting, with three more fonts: Inter SemiBold, 2002 and 2002 Bold.
- Class icons in the chat conversation list show properly.
- The World Map guide button no longer causes "blocked action" pop-ups.

## 0.29.2

- **More chat channels:** Say, Yell, Instance/Battleground and WorldDefense can be kept too (off until you turn them on in Chat settings), each with its own row, color, sound and reply box.
- **Pop-out chat window:** choose which kept channels get a tab, and open Chat Settings from its **Opts** button.
- **Custom pop-out tabs:** make your own tab and pick any mix of channels and log streams for it.
- **Floating log windows** (`/epu logs`): movable windows for XP & reputation (with XP per hour this session), and server and loot messages. A Combat Log window was also added, but it never showed anything and has since been removed.

## 0.29.1

- **Public chat:** General, Trade, LookingForGroup and LocalDefense can be kept in EPU chat (off until you turn them on in Chat settings), each with its own row, pop-out tab, color, sound and reply box.
- **Sort order:** choose newest or oldest messages on top, and newest or oldest conversations first, in Chat settings.

## 0.29.0

- **Zone Visitor's Guide** (`/epu zone [name]`, or the guide button on the World Map, which follows the zone you're viewing): 43 WoW: Forever and Classic zones with level ranges, flight paths, fishing, trainers, vendors and their recipes, guildmates there now, gathering spots, quests colored by level, and waypoints you can click.
- **Leveling tools** (`/epu leveling`): zones and dungeons for your level and milestones to aim for, with quest items you might be missing checked against the guild bank and crafters, so you can ask for them in one click.
- **Dungeons** (`/epu dungeons`): a warning when someone in your group is 12 or more levels apart (they'd get no XP), keys and attunements, quests to pick up first, and who in the guild has done each dungeon and who still needs it.
- **Gear** (`/epu gear`): dungeons and notable drops for your level, class and role.
- **Writs** (`/epu writs`): Waylaid Crates and Craftsman's Writs, with waypoints, a bag check against the guild bank and crafters, and the daily writ cooldown.
- **Camping blueprints** (`/epu camping`): where Tier 2 and Tier 3 blueprints drop, which you've learned, and which camping stations the guild covers.
- **Raid prep** (`/epu raid`) for December 9: Barrow Deeps (10), Hyjal Summit (20) and Onyxia's Lair (40), with Drakefire Amulet and fire resistance tracking, a squad builder and raid consumables for the bank.
- **Guild run log for officers** (`/epu runs`): dungeon runs logged from boss kills or in one click, who has done what, attendance over 30 days and guild stats.

## 0.28.6

- **Pull for request.** At the guild bank, officers and bank managers can take exactly what an approved request still needs out of the guild bank in one click: **Pull for request** in the request's details (or the bag icon on its row while the guild bank is open). EPU moves whole stacks where they fit and splits one for the rest, one move at a time, into empty bag slots. Then take it to a mailbox and click **Mail it** as usual. It checks your bag space and today's guild bank withdrawal limit first, and if the guild bank has less than is owed it takes what there is and says so. Pulling doesn't mark the request filled; sending the mail does.
- **Taking a requested item out of the guild bank fills the request.** When a member with an approved request withdraws that item from the real guild bank (on any of their characters), the officer or bank manager who next opens the bank credits it to their oldest matching request, as if it had been mailed: delivered goes up, and the request turns Filled once it's all there. Each withdrawal counts once, even when several officers open the bank. Withdrawals made before the request was asked for don't count, and neither do bank alts moving stock out or an officer taking something out for someone else (mailing or trading it to them fills the request, as before).
- **No repeat thank-yous for old guild bank deposits.** EPU keeps the newest 500 donations, but a quiet guild bank tab's log keeps showing its last deposits. Once one of those had dropped off the list, the next officer to open the bank logged it again, with a fresh News shout-out and Discord thank-you. Now, once the list is full, deposits older than the oldest one kept are left alone.
- Officers and bank managers need 0.28.6 for these, since they're the ones who read the guild bank log.

## 0.28.5

- **Moving the bank alt's stock into the guild bank isn't counted as donations.** When a bank alt (current or retired) deposits items or gold into the guild bank, EPU no longer logs each stack as a donation, so there are no News shout-outs and no Discord thank-yous for the guild's own stock. Members' deposits still count as before. The officer who opens the bank sees one chat line saying how many deposits were the guild's own stock.
- The same goes for mail and trades from one bank character to another: they aren't logged as donations.
- Officers and bank managers need 0.28.5 for this, since they're the ones who turn the guild bank log into donation records.

## 0.28.4

- **Search your chat history.** On the Chat page, type in the search box at the top (two letters or more) to find every saved message that matches, in whispers and in the guild, officer, party and raid chat you keep, newest first. It matches what was said and who said it. Click a result to open that conversation at that point: the hour either side of the message, with your search words marked. **Show the latest** goes back to the newest messages. The pop-out chat window has it too: click **Find** in its title bar (in a per-person window it searches that conversation).
- **@mentions.** In EPU's chat boxes, type **@** and the start of a name to pick a guildmate (online first); click one or press **Tab**. It puts in their "Call me" name if they set one, otherwise their main's first name, so it counts as a mention for them.
- **"Call me" name** in My profile: a short name like "Laur" or "Ty". Guildmates see it when they type @, and it counts as a mention of you.
- **Fewer doubled guild lines:** a hidden server copy that came with only a first name ("Luna" for "Luna Graceclaw") or a moment off, and Discord copies of lines with item links, no longer show twice.

## 0.28.3

- **Messages that mention you stand out.** In guild, officer, party and raid chat, a message with your name (any of your characters' first names) or one of your alert words is shown in its own color: gold by default, changeable in **Chat settings → Mentions → Mention color**. It works in EPU's chat and in the game's own chat windows (only the message text changes color; turn that part off with "In the game's chat too"). Your own messages are never colored.

## 0.28.2

- **"with EPU" counts are right.** Home's "N online · M with EPU" (and the EPU mark on Guildmates) only counted guildmates who sent bank or sync reports, so most EPU users were missed. EPU now remembers anyone whose EPU it has heard from in the last 30 days.

## 0.28.1

- **No more "No player named … is currently playing." walls.** When someone logged in, EPU sent them the guild chat they missed in several pieces. If they logged off before it all arrived (a quick bank-alt visit, say), every guildmate who was answering saw that line once per piece. Now EPU stops sending to anyone who has logged off and hides those lines. The message still shows for whispers you typed yourself.
- Switching characters no longer asks guildmates for missed guild chat again within 15 minutes, since your characters already share it.

## 0.28.0

- **Chat is now its own page, like a messenger.** It sits in the sidebar under Quests. Conversations are listed on the left (guild and officer chat pinned on top when you keep them, then one row per person you've whispered, newest first, with unread counts). The open conversation shows on the right with both sides, and a box to **reply** right there (Enter or Send). **New message** starts a whisper to any guildmate, and **Chat settings** has keep, clear and show-after-reload options. Opening Chat jumps to your latest conversation, and the sidebar badge counts unread whispers. Newest messages are on top with the reply box above them, and the conversation gets most of the page width.
- **Pop out:** a small chat window of its own (Chat → Pop out, or `/epu messenger`). Drag it anywhere, resize it from the corner, switch conversations from its title, and **minimize** it to a small round bubble (like the Events bubble) that you can drag anywhere; a green badge counts new whispers and the bubble flashes when one arrives. Click it to open, right-click for the Chat page. It stays where you left it, and reopens after a reload if it was open.
- **Unread counts per conversation:** each person and guild/officer chat shows how many messages you haven't read, and opening one clears only that one. The chat bubble has two counters: green for whispers, blue for guild messages. The Chat sidebar badge counts both.
- **Party and raid chat** are kept too (on by default; turn off in Chat settings) and pinned with guild and officer chat. You can read and reply in each.
- **Tabs in the pop-out window:** Tells, Guild, Officer, Party and Raid, each with its unread count, so you can swap with one click. Tells goes back to the last person you were whispering.
- **Colors follow the game's chat colors** (so they match your chat windows and any changes you made there). In Chat settings you can pick your own color for any chat, including a separate one for whispers you send, and go back to the game's colors in one click.
- **Window choices:** tabs in one window, or **one window per person** (each whisper gets its own window; group chats stay tabbed). Optional: open a window when a whisper arrives. Windows can be dragged from anywhere that isn't a button.
- **Clickable web links:** links in messages are blue; click one and it opens ready to copy (Ctrl+C), since WoW can't open a browser.
- **Copy:** copy a whole conversation as plain text, Discord format or BBCode, or click a message's time to copy just those messages.
- **Sounds and mentions:** pick a sound for each chat, and get an alert (with its own sound) when someone says your name, or any word you add, in guild, officer, party or raid chat. Whole words only.
- **Combat:** chat windows tuck into the bubble when combat starts and come back after (can be turned off). Optional fade when the mouse is elsewhere.
- **Alts show their main**, like "Tyler (Laurelin)", wherever EPU knows it.
- **"typing..."** shows when a guildmate who uses EPU is writing you a whisper (can be turned off).
- **Guild chat from while you were away:** EPU shows the guild (and, for officers, officer) chat history the game keeps on its server, the same history the Guild & Communities window shows. The game only lets addons display those older lines, not save them, so they show for the session you're in; everything said while you're online is saved as usual. Lines are matched by who said them and when, so nothing is doubled and real repeats stay. That history doesn't count as unread. Every message shows its own time (turn it off in Chat settings to show the time once per group). Because of this, keeping guild chat is now on by default (turn it off in Chat settings).
- **Discord messages in guild chat:** messages from the guild's linked Discord channel (linked in the game's Guild & Communities window) show in EPU's Guild chat with a "Discord" tag.
- **Guild chat you missed, from Discord (EPU Discord bot):** the bot reads the last day of the channel linked to guild chat (`#in-game-chat` by default; set `ingame_chat_channel` or `ingame_chat_channel_id` in config.json) and passes it to the game through Inbox.lua. At login or `/reload`, EPU adds the lines it didn't already have. Linked members show under their main; others under their Discord name. Lines typed in Discord keep the "Discord" tag. Update the bot too, and turn on **Message Content Intent** for it in the Discord Developer Portal if it isn't on already.
- **Guild chat you missed, from guildmates:** when you log in, EPU asks guildmates who use it for the guild chat you missed (up to a day) and fills it in, saved like the rest. You answer them the same way. Only guild chat; officer chat is never sent. Turn it off in Chat settings.
- **Chat is shared by all your characters on this PC:** switch characters and your whispers, party and raid chat, guild chat (per guild) and chat settings are all still there. Whispers that came to another of your characters say which one. Chat you saved per character before is moved in automatically.
- **Readable text:** pick the chat font (EPU, the game's font, Arial Narrow, Skurri or Morpheus), make it bigger or smaller, and add an outline, in Chat settings > Text, with a preview.
- **Guildmates coming online and going offline** show as short grey lines in Guild chat (when you keep guild chat). They don't count as unread, and can be turned off.
- **Run requests: Morning, Afternoon and Evening buttons** set the time range in one click (thanks for the idea, Laurelin). They're in Create > Group when you pick a day, and on the run request form.
- Using WIM too? Both would open a window for each whisper; turn one off for whispers.
- **Per-person colors:** give anyone's whispers their own color from their conversation, and reset it in Chat settings.
- Messages are grouped under the sender's name and time, like chat apps, with more padding in the pop-out window.
- Left-clicking the EPU bubble now also closes the window when it is open.
- On a short window the sidebar shows icons only; hover for the name and what each page is for.

## 0.27.2

- **Bank managers.** Officers can now let a rank (or specific characters) run the bank side for the whole guild: publish bank contents, edit needs, approve and mail requests, record donations, and act as a verified sync source. Bank managers can't post announcements, write member notes, manage other people's events or use the Officer tab, and they can't add other bank managers.
- Set it once under **Officer → Bank managers → Choose**. Unlike the officer ranks setting, it's shared with every guildmate's addon, so nobody has to change their own settings. Adding a character also adds its linked alts.
- Guildmates need 0.27.2 or newer to treat bank managers as verified.

## 0.27.1

- **Quests page (new, in the sidebar under Guildmates):** your quest log with how many guildmates are on each quest (and how many are nearby), group quests flagged, and **Questing near you**: guildmates in your zone, most quests in common first. Click a quest to whisper or invite them, or **Ask for help with this** to post a quest help request with the quest filled in.
- **Same quest nearby heads-up:** when a guildmate in your zone (and not on another layer) is on a quest you have, you both get one notification, after combat if you're fighting. It follows your notification settings (category: Same quest nearby).
- **Quest sharing is now on by default.** EPU shares which quests are in your log and the zone you're in with online guildmates; nothing is saved or sent to Discord. Turn it off under Quests → Sharing. Sharing objective progress is still optional, per quest.
- Quests in common also show on **Home** (Same quests as you), in the **Guildmates** table (Quests column) and on guildmates' tooltips.
- **Chat history.** Your whispers are now saved on your PC, so they survive a /reload or logging out. After a reload, the last hour goes back into your chat windows (greyed header, clickable names). Turn on **guild chat** too if you like, and officers can keep **officer chat**. Open it with `/epu chat`, from Settings or Member tools: tabs for each channel, **Whisper back** buttons for recent people, and **Clear**. It is never shared with the guild. Messages the game hides in combat are saved as a placeholder.
- Fixed "Interface action failed because of an AddOn" in combat. EPU read the guild message of the day when the roster updated mid-fight, which the game blocks. It now waits until combat ends.

## 0.27.0

- **Cleaner Home.** Your stats sit in a row of four tiles (online, open groups, your requests, next event). Below them are two columns: **Right now** and **Coming up** on the left, **Who is where** and **Today in the guild** on the right. Section titles are gold with a thin line, and card text no longer overlaps.
- **Tidier sidebar.** Every entry has the same flat look, split into three blocks by thin lines: Home, Groups and Guildmates; Bank, Professions and Guild; Member tools, Settings and Sync. Hover any entry for a one-line description of what it's for.
- **Clearer labels everywhere:**
  - Bank tabs are now Bank stock, Item requests, Bank needs, To buy and Donations.
  - Groups boards are now All groups and events, Dungeons and raids, Scheduled events, Quest help wanted, Groups forming now, Run requests (planned), Guildmates offering help and Starter kits. The filters are now **Only mine** and **Near my level**.
  - Create offers **Group or run · Scheduled event · Ask for quest help · Offer to help**, with **Activity** and **Going for** headings. "Either" is now **Quests or loot**.
- **Run requests are easier to find.** The Groups button in the sidebar always opens on everything. In Create → Group, picking a day instead of **Now** turns it into a **Run request**, and the button changes to **Post run request**.
- **Guildmates is a table:** name, level, zone, layer, group status, EPU and role. One **Show** menu picks who's listed: Online, Everyone, Near my level, Looking for a partner or On my layer.
- **Looking for a partner:** click **I want a partner** and guildmates see it in their list and on your tooltip until you turn it off or log out. It also shows when a guildmate is in a group.
- **Right-click a guildmate** to whisper, invite, set a waypoint to them (when they share their location) or ask to join their layer.
- **Dungeons and raids board** on Groups: every dungeon and raid with its level range, how many guildmates are online in range, and open groups or run requests for it. Dungeons in your range are green, and **Near my level** shows only those. Click one to see who's in range, jump to its groups, or **Start a group now** / **Request a run** with the dungeon already filled in. Classic dungeons now have suggested level ranges.
- **Raid picker** in Create → Group → Raid. Groups made from it use the raid's real size.
- **Groups button on the floating Events bubble:** click it to find a group, right-click to start one. The bubble's action list also has **Find a group**.
- **Key bindings** (Options → Keybindings → AddOns → EPU Guild Tools): open the addon, open Groups, create a group, open Guildmates.
- Updating: **restart WoW once** (not just /reload) so the new key bindings load.

## 0.26.0

- **Playing together comes first.** **Groups** and **Guildmates** (the Roster, renamed) now sit right under **Home** in the sidebar, instead of being buried under Guild. Guildmates opens on who's online.
- **Guild activities are now the Groups page.** It opens on **Everything**: quick groups, run requests and events together. The board menu still has Events, Quick quest help, Quick dungeon, Run requests, Available helpers and Starter kits. **Calendar** is on the toolbar. The Guild section keeps News, Projects and Invites.
- **New Home dashboard:**
  - the message of the day, and anything that needs your attention
  - at a glance: who's online (and how many use EPU), open groups, your requests and the next event
  - **Right now:** quick groups and help wanted, with role counts
  - **Coming up:** run requests and events
  - **Who is where:** online guildmates by zone, with their levels. Click a zone to see them.
  - **Today in the guild:** joins, level-ups and milestones from the last day, plus new announcements
  - shortcuts to the bank, news and the getting started checklist
- **Everything board:** quick groups, run requests and events this week in one list, sorted into Right now, Later today and This week. **Mine** shows only yours.
- **One Create button** on every Groups board. Its form starts with **Group · Event · Quest help · I can help**, and the event, quest help and helper forms carry the same switcher, so everything is one click apart. Switching from a group to **Event** keeps the dungeon, day and time you picked. A later-this-week group also offers **Pick one fixed start instead**.
- **Group** (in Create):
  - Pick **Dungeon** (from the list), **Raid**, **PvP** or **Other**, then **Quests**, **Loot farming** or **Either**.
  - Pick when: **Now** posts a quick group for 1, 2 or 4 hours. **Today**, **Tomorrow** or a weekday, with a From–To time, posts a run request guildmates can tick times on.
  - Optionally **Tell guild chat**: one line so guildmates without EPU see it too.
- New commands: `/epu groups`, `/epu lfg` (start a group) and `/epu who` (guildmates online). `/epu who <item>` still asks who can craft an item.
- Updating from 0.23.0 or older? Restart WoW once (not just /reload) so the newer fonts and header art load.

## 0.25.0

- **STV pages tab on the Bank page.** It shows every Green Hills of Stranglethorn page grouped by chapter: how many the bank has, which bank character holds them, and how many complete sets each chapter could hand out. Pages the bank has none of are greyed out.
- Pages you're missing are highlighted, and pages you already carry are marked. Chapters you've turned in show as Done.
- Click a chapter to request pages from the bank. The pages you need start ticked, and each page becomes its own request.
- Officers can set **Keep 3 of each page** in one click. Short pages then appear on Needs and first in the mailbox donate panel, so members can send in the duplicates they loot.

## 0.24.0

- **Run requests.** Ask the guild "I want to run this dungeon, anyone else?" without scheduling an event. In **Guild activities → Run requests**, click **Request a run**:
  - pick the dungeon from the list
  - choose **Quests**, **Loot farming** or **Either**, and your role
  - pick up to three days (Today, Tomorrow or later this week) with a time range for each, in 30-minute steps
- Guildmates open the request, choose a role and tick the days that work, narrowing the times if they need to, then click **I'm in**.
- The request shows the **best times**: where most people's times overlap, with tank, healer and DPS counts.
- The requester or an officer can **Schedule** a best time, which turns it into a 90-minute dungeon event. Everyone who picked that time is signed up automatically with their role. Anyone who picked other times gets a message instead.
- Guildmates get a notice when a new run request comes in, and the requester gets one when someone is in. Times show in each player's own time zone. Requests close on their own after their last time passes.
- Everyone posting or responding needs 0.24.0. Players on older versions don't see run requests.

## 0.23.3

- The donate panel at the mailbox has a clearer quantity button. It reads **Need** when the bank still needs some of an item and picks exactly that, then reads **Max** and picks everything you carry. The -, + and Max buttons are a little larger and easier to hit.
- Installs from GitHub, the EPU updater and WowUp report their version over guild sync again, like CurseForge installs. Officers see everyone's version in Sync, and update prompts reach all of them. Local test copies still stay quiet.
- Players on 0.23.0 or older no longer cause dungeon events with role slots to re-sync at every check-in. (They still see those events without the slots until they update.)
- After updating from 0.23.0 or older, restart WoW once (not just /reload) so the new fonts and header art load.

## 0.23.2

- Updated Enhancement leveling guide notices for the live November 12 tuning and documented the November 13 dungeon XP restriction.

## 0.23.1

- The interface uses Inter, a midnight-blue header, and an icon rail with a second navigation column on wide windows. Home brings requests, the next event and pending actions up front. Bank item details show stock at a glance and keep Request item and Mail by profession within reach while you scroll.
- Reorganized the addon into Home, Bank, Professions, Guild, and Member tools. Bank stock and Shopping use separate quantity columns. Bank and Market use the same dark theme and controls, and narrow windows open details with a Back button.
- Every view uses a titled layout. Events put your RSVP before the signup list, the roster puts contact actions ahead of character details, Recipes puts crafters first, and Officer tools puts fulfillment first. Progress meters, detail history, the calendar picker, guide links, map settings, donation controls, toasts, route HUD and the floating badge use the same interface styling.
- Selected buttons have a gold underline, unavailable actions explain why where possible, and crowded toolbars wrap on narrow windows. The minimap button has a smaller guild crest and adjusts its position around nearby buttons.
- Bank, Recipes, Market, and Sync show how many results match the current filters and offer **Clear filters**. Sync has class icons, status filters and sorting, with the transfer details one click away.
- Bank mail shows the recipient and the quantity and stack count for each item as attachments are verified. It flags recipient changes before sending.
- Local and GitHub builds no longer advertise their versions over guild sync. The CurseForge upload receives a separate package marked with its release version.

- Bank Sort lets you filter material recipients by profession, such as Tailoring for cloth. Officers can also use **Mail by profession** from a stocked trade good's details.
- Bank Sort waits for each attachment to settle before adding the next stack. It still removes attachments when the verified item or quantity is wrong.

- The floating Events button keeps the upcoming event count and adds an orange badge for work your character can act on. Click for requests, craft work, event signups, invites and Discord imports, with shortcuts to their details.

- Discord `/chars` shows your verified links, legacy links and expected roles, with a button to get a link code. `/roles` explains skipped checks and scans that found everyone up to date. New class roles use WoW class colors.
- Officers can use `/sync_health` to check the last WoW save, roster and bank snapshot times, and updates waiting for a reload.
- **Officer → Bank fulfillment** groups approved requests by recipient and previews quantities that fit in the next mail.
- Event organizers can copy an event to up to three more weeks and set dungeon role slots. Going signups wait for organizer confirmation when role slots are set. Discord shows confirmed players and the waitlist.
- Market craft details show the estimated up-front cost, a gold cap, and the deposit that could be lost if the batch goes unsold. Enter the deposit estimate from the auction house.
- Role sync checks roster completeness before linking or assigning roles and deduplicates legacy Member-role mappings. Bank mail requires a quantity and protects reserved stock. Recipe sorting puts verified recipients first and labels unverified skill requirements.

- Everyone linked gets the Member role in Discord, whatever their guild rank. Veteran and Initiate are extra roles on top for those ranks. Change it with `member_role` and `rank_roles`.
- The Discord bot uses your server's existing Member, Veteran and Initiate roles instead of skipping them. It never takes over your officer role, a role with moderator permissions, another bot's role, or a role above its own. Only linked members' roles change; everyone else keeps what they have. Set `"adopt_existing_roles": "none"` to turn this off, or `"all"` to adopt existing class roles too.

## 0.23.0

- **Link Discord with a code.** `/link` in Discord gives a private code; type `/epu link CODE` in game once. Every character on that WoW account links itself, and confirmed EPU alts come along, with no officer step. Officers can still approve by hand, and `/link_suggestions` links everyone whose Discord name matches a guild character with one button.
- **Class and rank roles in Discord.** Linked members get a role for each of their characters' classes and a rank role from their main. Only Veteran, Member and Initiate are automated by default; officer ranks stay manual. The bot only manages roles it created, and holds back large removals until an officer runs `/roles confirm`.
- **Officer log.** An officers-only Discord channel can list joins, leaves, returns, promotions and demotions, level 60s, new links and link conflicts.
- **New Discord commands:** `/whois`, `/chars`, `/main` and `/roles`.
- **Sort the bank.** Bank → Sort lists who should get each recipe in the bank or mailbox (highest skill who doesn't know it), which materials give guildmates skill-ups or profitable crafts, and what to sell, by value. Each item has Mail to buttons.
- Bank toolbar dropdowns are a little narrower to make room for Sort.

## 0.22.3

- The Roster shows which guildmates in your zone are on your layer: **same layer** in green or **other layer** in amber. EPU reads your layer from NPCs you target, mouse over or see nameplates for, and shares it with your map location (same opt-out).
- A My layer filter lists only the guildmates you can actually meet in the world.
- A guildmate's details show an Ask to join their layer button when they're on another layer. It whispers them for a group invite; accept the game's prompt once grouped to move over.
- Map marker tooltips also say whether that guildmate is on your layer. Both players need 0.22.3 for layer tags; older versions keep working and simply show none.

## 0.22.2

- Fixes 1 to 2 second freezes. When someone logged in behind on guild data, the officer (or a member passing data on) could freeze for over a second while preparing the reply; it now takes a fraction of a second.
- Sync checks run a few milliseconds per frame instead of all at once, so the 15-minute officer check-in no longer causes a hitch.
- Comparing guild data is faster and gives exactly the same result, so players on 0.22.1 and 0.22.2 still sync normally.

## 0.22.1

- Gathering spots you record are shared with the guild, so one guildmate's recording helps everyone's routes. Type `/epu sharespots off` to keep yours private.
- Members who have left the guild no longer appear as crafters or gatherers, or count toward profession coverage and guild focus goals.
- The Needs list shows who can craft each need. A need's details list the crafters and an Ask a crafter button.
- The guild focus also shows on Gather, and the Discord companion's pinned status post lists it with progress toward each goal.
- Forever's new herbs stay in the Gather list while My skill is on, marked as having an unconfirmed skill requirement.
- Craft tooltips explain that the listing deposit comes back when an item sells.

## 0.22.0

- Market has its own tab in the guild window with three views: Craft, Buy & Craft, and Gather. It reads prices from AHledger, TSM, or Auctionator and shows which one is in use and how old its prices are.
- Craft profit is what you would make now: the sale price is the current lowest listing, less the 5% faction AH cut. Rows say when nothing is listed and a median is used instead.
- Ingredients sold by vendors, such as thread, flux, vials and dyes, use the vendor price. Shopping lists mark them.
- Rows carry a short tag when it applies: Sells now, Slow, Thin margin, No listings, or Loss.
- Craft plans a batch around materials already in your bags, expands known intermediate recipes and compares buying the missing ingredients with buying their base materials. Sort: Skill-ups finds the cheapest orange and yellow recipes for leveling a profession.
- Buy & Craft shows profitable learned recipes with daily sales and sorts by sales volume, profit, profit %, sale price, or both profit and demand. The gold highlight follows the sort you choose.
- Scope: Guild shows everything your guildmates can craft at current prices, with who can make it. Ask a crafter opens the recipe so you can send a craft request. Crafters need this version and must open each profession once before their recipes appear.
- Officers can set a guild focus from Officer, Profession coverage: the professions the guild wants more of, with an optional skill goal. Coverage shows progress toward each goal. Members see the focus in Market with their own skill, and a nudge when they have a free profession slot.
- Gather compares herbs, ores, skins, and fish. Selecting a material shows how many guildmates can gather it. Save your observed units per hour for a material and zone, then sort by estimated gross gold per hour.
- Follow EPU's own movable arrow through recorded herb or ore spots in your zone. Use `/epu route` for herbs and `/epu route ore` for mining. Starter spots cover 19 zones, and GatherMate2 spots are read when installed.
- Gather opens on your current zone when it has recorded spots. Record spot works whatever your skill.
- Open each crafting profession once after updating. If EPU cannot read a profession, it now says so instead of staying on "Open to scan".

## 0.21.4

- The Events bubble uses the EPU guild crest and shows the number of upcoming events.

## 0.21.3

- The /guildevent time zone picker accepts familiar zone names and city searches. The companion uses the offset in effect on the event date.

## 0.21.2

- The pinned Discord status post shows when updates have waited two minutes for a WoW reload. After importing updates, EPU explains how to save the results back to Discord.

## 0.21.1

- Guild invite requests open a prepared /ginvite command in WoW chat. Review the name and press Enter to send the invitation.

## 0.21.0

- Use /guildevent in Discord #events to schedule a guild activity as your verified character. After the bridge imports it, open Guild activities to sign up or prepare its WoW calendar draft.

## 0.20.4

- Member tools puts Your guides, Quest matching, Catch-up, and Notifications together in a visible sidebar page.
- Guild invites now has its own sidebar entry below Roster for characters who can invite guild members. The empty list explains when there are no active requests.

## 0.20.3

- Ignore restricted WoW chat values before reading them, fixing the system-message error in `Comm.lua`. Readable throttle warnings and guild sync messages still work.

## 0.20.2

- Create + WoW calendar saves an activity and prepares its linked calendar draft in one flow. Review the draft and press WoW's Create button to publish.
- Calendar details explain that opening the calendar does not publish an activity and show which organising character must prepare the copy.
- Unsupported calendar forms and events that cannot be prepared now explain why.

## 0.20.1

- A movable Events bubble shows how many guild events are upcoming. Click to open Events, hover to see the next event, or right-click to open notification settings.
- Turn on Announce in guild chat when creating an event to post its title, start time, and the shortcut to sign up.

## 0.20.0

- Choose a dungeon when scheduling a guild event. EPU can fill the title and meeting area, with suggested levels for Forever dungeons. Custom titles and meeting locations stay editable.
- Set the event date and time in one picker with Today and Tomorrow shortcuts, AM/PM controls, and a preview in local time.
- Officers can approve sync helpers by exact guild rank. Explicit character approvals and removals take precedence, and each volunteer still needs a private connection folder.

## 0.19.1

- Default bank and crafting requests to the character placing them. The bank request form has a visible Mail to dropdown with full character names.
- Show the requester and delivery address separately. Officers can choose another recipient and must save that change before preparing mail.
- Send individual request changes ahead of bulk guild sync at the existing send rate. Officers receive alerts for new orders and digest entries for recent orders recovered during sync.

## 0.19.0

- Show Online, Offline, Unknown and short-lived reported presence in the guild invite list. Add an explicit Add to Friends action and permission-gated online alerts with quiet-hour/dismissal support, paced ephemeral sightings and reconnect cooldowns. Never poll /who or automatically change friends/invite anyone.
- Simplify event creation with activity presets, suggested meeting place, quick local start times and collapsed group options. Preserve custom values and drafts when choosing a type or expanding options.
- Mirror EPU guild events to one maintained Discord #events card with dates, plans, confirmed signup names/roles and separately labelled pending responses. Add verified-character signup buttons and role selection through the existing officer/helper bridge. Update cancelled/ended events and disable their buttons; never ping members automatically.
- Gate event actions behind updated addon/helper support so older helpers continue receiving invite and bank requests. Return public EPU events/signups through helpers, preserving newer game decisions. Native WoW calendar attendee snapshots remain local.
- Fix announcement/detail headings retaining a fixed height from the event date preview and overlapping following text.
- Verify officer bank status changes return through helpers without granting approval permission or overwriting newer data.

## 0.18.0

- Add `/guildinvite` in Discord with required first and last name fields, plus strict `Character: First Last` imports from a configured channel. Ignore chat, bot posts, quotes, code examples and ambiguous names; deduplicate requests, handle edits/deletions and expire old requests.
- Alert only characters with the game's guild-invite permission. Add `/epu invites`, manual Invite and a copyable `/ginvite` command. Match native success messages or roster joins before reporting completion; return ✅ to the original Discord message. A button click alone never confirms an invitation.
- Add an officer-controlled, per-character sync-helper whitelist, including explicit alts. Helpers can import invites/new pending bank requests, but cannot change approvals, officer announcements or the whitelist.
- Add a standalone Windows shared-folder helper with folder browsing, optional Windows startup, clear queued/exported/received status, authenticated packets, stale/replay guards and duplicate-safe imports.
- Support OneDrive and Google Drive desktop folders, including mirrored copies for different volunteers. Keep the central Discord token private and transfer only filtered public guild data and verified receipts; preserve local officer inbox actions.
- Hold new inbox kinds until the updated addon is installed. Add filtered public snapshot merging and receipts back to the central bot. WoW still needs login or `/reload`; cloud-provider sharing remains an organiser setup step.

## 0.17.1

- Keep the minimap button outside the actual minimap edge, using its current width, height and reported round/square/corner shape instead of a fixed radius. Reposition when the map resizes; choose a nearby visible edge position when the screen boundary blocks the preferred angle.
- Enlarge the grab area, account for scale while dragging, and prevent a drag release from accidentally opening the addon.
- Add `/epu button` with eight position presets, Closer / Further out, lock, show/hide and Reset. `/epu minimap reset` recovers a hidden or misplaced button; bare `/epu minimap` retains its visibility toggle.
- Link the position controls from `/epu map`. Preserve saved angles, visibility choices and existing click shortcuts. No map-sharing reset or companion update.

## 0.17.0

- Make Activities the default guild board, with Dungeon, Leveling, Quest / elite help, Fishing, Profession, Farming and Other types. Preserve the quick-help boards, helpers and starter kits.
- Add suggested level ranges, type/date filters and a local month picker with daily activity counts. Preserve local/server time displays, upcoming-event reminders and personal drafts.
- Add Helper, Crafter and Mentor signup roles alongside Tank, Healer and DPS. Show participants, tentative responses and volunteer notes.
- Add optional WoW guild-calendar drafts, completed with WoW's own Create button. Fall back to copyable title/details when the client does not support preparation. Never overwrite an open calendar draft or automatically publish.
- Read attendees from the matching open WoW guild event, including members without EPU. Merge the local display by member, prefer calendar status and retain EPU roles/notes. Snapshots are session-only, expire after three minutes and are not relayed as other members' authored responses.
- Offer explicit responses in both systems for your own signup while the linked event is open. Await WoW confirmation; never modify another member's calendar status. Titles, times, cancellation and event approval still require review in both calendars.
- Validate native links using an EPU description marker, organiser, title and realm start time. Do not silently match unrelated or moved events.

## 0.16.2

- Hide sold-out weapons and armor from the bank catalog and request pickers in game and Discord. Keep their history so they return automatically when restocked; preserve existing requests.
- Retain sold-out materials, consumables, bags and other classified non-equipment as restockable catalog items. Unclassified historical items wait for metadata instead of appearing as unknown gear.
- Add In stock, Available now, Awaiting restock and item-quality filters alongside categories, plus Reset to clear filters and search.
- Export item metadata for hidden historical items so the companion can apply the same rule. Stocked gear remains visible regardless of metadata availability.

## 0.16.1

- Correct guide coverage: Method Skinning stops before skill 225 and Method Herbalism before skill 205, where their published routes become unfinished or explicitly speculative. Mark the Leatherworking source as beta-derived.
- Label focused Mobalytics paths accurately and hide them when a different talent focus is selected, including saved sources.
- Refresh verified publisher dates and add an Enhancement gearing caution for announced November 10 tuning; do not describe planned changes as already live.
- Flag the confirmed November 8 increase to dungeon enemy kill XP so older quest-versus-dungeon comparisons are not treated as current.
- Preserve character relevance, private bookmarks/notes and the simplified guide navigation. No game-state, map-reset or bot changes.

## 0.16.0

- Replace square guild-map markers with circular class icons on the world map and minimap. Unknown classes use a round dot; `/epu map` can switch all markers to class-colored dots.
- Enable location sharing and both map displays by default. On the first load of this update, reset those map settings and the icon style to on for all upgraded installations, including prior off settings, as requested for the guild rollout.
- Show a one-time login notice explaining that outdoor locations are shared and where to change it. Preserve each player's choices after this initial reset.
- Keep location expiry, instance withdrawal, private session-only coordinates, paced traffic, hover information and click-to-whisper behavior.

## 0.15.0

- Limit bank requests to currently or previously stocked items, while allowing sold-out items and excess quantities to wait for restock.
- Preserve bank item history across scans, depletion, retirement and legacy snapshot updates, and backfill recorded bank donations.
- Show quantities in the bank browser and request pickers; subtract open bank requests and approved bank-paid crafting materials from available stock.
- Mark waiting quantities on request rows/details and Discord messages. Recheck quantities when stock or requests change; do not claim live reservations.
- Apply matching catalog rules to Discord autocomplete and direct `/request` entries; include unimported Discord requests without double counting.
- Refresh Discord request messages when stock changes, preserve rejected form drafts, and validate starter-kit bank items before creating a project.
- Remove the full-game item download from bot startup. Craft requests and needs still support items outside bank history.

## 0.14.1

- Simplify Your guides to one choice per task: level your class, choose talents, and improve each learned profession.
- Put a recommended guide and copy-link action first. Move other sources, author/review metadata and private notes into detail panels.
- Hide the Topics filter and preserve relevant saved guides without duplicating source rows. Legacy alternative-source preferences do not expand the home screen.
- Prefer actual profession skill routes over general references, retain source cautions in details, and close profession tasks when that profession is unlearned.

## 0.14.0

- Add Your guides under Guild activities, with `/epu guides` access and 107 curated Forever source entries across all nine classes and twelve professions.
- Show only this character's class, level, learned professions and skill range; specialization routes require a matching automatic or chosen own-class talent focus.
- Default to a concise best-fit selection, with optional alternative sources, clear beta/pre-launch labels, author/update metadata and editorial review dates.
- Add copyable full-source links, private saved guides and notes, and progress for the current level/skill bracket. Saved sources never bypass relevance.
- Add a validated offline catalog generator, read-only source-health checker and documented weekly editorial maintenance process. HTTP access restrictions are distinguished from missing guides.
- Retain all existing bank/mail, reagent-bag, map, activity, calendar, quest and notification features. Live Forever visual validation remains pending.

## 0.13.0

- Add casual event planning with local/server time display, going/tentative/declined role signups, organiser edits, officer cancellation and personal reminders.
- Add opt-in matching for up to eight explicitly selected quests, with paced progress updates, withdrawal and transient remote data.
- Add a returning-player catch-up view for unread news, personal requests, active projects, upcoming events and the local digest.
- Add private notification modes, category preferences, quiet hours, sound control, followed/muted posts and configurable reminder lead time.
- Deduplicate reminders, coalesce queued notices, send overflow to the digest and open the relevant item when a notice is clicked.
- Bound sync payloads and private history, preserve forms during refresh, and avoid refreshing bank pages for shared quest progress.
- Preserve existing guild maps, starter kits, combined request mail and exact-quantity safeguards. Live Forever visual validation remains pending.

## 0.12.0

- Add one Guild activities page for quest/elite help, dungeon groups, helper availability and reusable starter-kit templates.
- Support ready/tentative responses, role counts, suggested levels, Mine/My level filters, manual whispers/invites and automatic expiry. Helpers opt in for a limited time and appear only while online.
- Keep activity drafts during background refresh; validate author ownership and recover recent authored records when a new member joins without an officer online.
- Turn starter kits into tracked Projects with bank requests and assigned craft tasks, preview validation, duplicate protection and an officer-confirmed welcome checklist step.
- Combine a member’s approved bank requests into one mail draft with exact remaining quantities and shared same-item attachments. Respect stock/attachment limits, preserve existing drafts, and credit only the selected requests after successful delivery.
- Avoid same-second request ID collisions during batch kit creation.
- Existing guild-map and exact-mail safeguards are retained. Live Forever visual validation remains pending.

## 0.11.0

- Opt-in guild location sharing with world map and nearby minimap markers.
- Shift-click the minimap button or use `/epu map` for separate sharing and display controls; click markers to whisper.
- Slow, disposable updates share the existing network budget, yield to sync traffic and expire after two minutes. No location history is saved.
- Stop sharing in instances, discard queued positions on opt-out or guild changes, and remove offline members. Both members need the updated addon.
- Bundle HereBeDragons 2.18 with Forever map support; live-client validation remains pending.

## 0.10.2

- Prepare request mail for the remaining quantity and verify the actual attachment count after splitting; remove mismatched attachments, including later restacking by mail addons.
- Stop on unknown quantities, locked stacks or failed splits. Preserve existing draft attachments and recipients instead of preparing a second request over them.
- Apply the same exact-quantity helper to craft materials and donation mail. Improve mail simulation to model cursor swaps and attachment quantities.

## 0.10.1

- Reduce EPU's initial sync burst and space outgoing packets. Use increasing cooldowns after rejected sends or a recent-send server throttle warning; pace visible guild posts too.
- Keep large incoming transfers from triggering premature sync retries. Add `/epu net` diagnostics and a visible sync cooldown state without filtering server warnings.
- Make request-status counts follow the search, Mine and Crafts filters, display visible versus total counts, and add a clear-search button.
- Include eligible reagent-bag items in the Donate panel, prepared donation mail and guild-bank deposits using the shared carried-container list.

## 0.10.0

- Track partial mail/trade deliveries by actual quantity and allocate each item once. Keep delivery history and show remaining quantities in game and Discord.
- Validate request ownership, statuses, quantities, bank snapshots, recipes and materials at the receiving client.
- Require character-authenticated, mutually acknowledged main/alt claims. Require officer approval for Discord character links, prevent duplicate ownership and support revocation; legacy unverified Discord links must be reapproved.
- Wait for guild-bank tab responses before publishing a complete inventory; clear confirmed empty tabs and refresh observation timestamps.
- Merge individual needs with deterministic revisions and deletion tombstones; coalesce rapid edits and use digests to recover missed records.
- Bound and expire addon-message fragments, reject malformed payloads, split large sync bundles and retry incomplete syncs.
- Add guild crafting projects with assigned craft requests, material requirements and delivery progress.
- Add configurable member onboarding checklists with officer-confirmed Discord, mentor and starter-supply steps.
- Back up Discord companion state, restore its inbox after addon updates, and stage updater installs with manifest validation, preserved inbox and a previous-install recovery copy.

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
