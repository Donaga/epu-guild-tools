# Changelog

## 0.23.1

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
