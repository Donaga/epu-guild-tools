# EPU Guild Tools

A guild helper for **E Pluribus Unum** on WoW: Forever. It covers the time before the guild has a real guild bank, and stays useful after.

## Install
**Recommended:** install it with the CurseForge app from https://www.curseforge.com/wow/addons/epu-guild-tools (click **Install**, pick your Forever install). The app keeps it updated. WowUp (Install from URL with the GitHub link) and the EPU updater work too; use just one.

**By hand:**
1. Unzip so the folder is `World of Warcraft\_forever_\Interface\AddOns\EPUGuild\`. The `_forever_` folder name may differ; it's the folder for the Forever client. Inside it you should see `EPUGuild.toc`.
2. Restart the game or type `/reload`.
3. If the AddOns list says **Out of date**, run `/dump select(4, GetBuildInfo())` in game and put that number on the `## Interface:` line of `EPUGuild.toc`. You can also tick "Load out of date AddOns" instead.

Everyone in the guild should install it. The more members who have it, the more complete the data is.

## Upgrading to 0.10

Update the addon for everyone and update the Discord companion on the officer PC together, then `/reload` and `/epu sync`. Log onto each alt once to confirm its main/alt relationship. Unverified claims from older clients are no longer used as proof of ownership. Existing Discord links need `/link` followed by officer approval using `/approve_link user: character:`; each character is verified separately.

Automated simulations cover this version. Live Forever client testing remains recommended before a guild-wide rollout.

## Guild activities (0.12+)

Open **Guild activities** in `/epu`, or use `/epu activities`. Choose a board
from the toolbar. Search covers titles, descriptions, member names and zones;
**Mine** shows your own posts and activities you responded to. **My level**
uses an activity's suggested level range, or helpers within five levels.
These filters do not apply to starter-kit templates.

- **Quest / elite help:** post what you need, the zone, a suggested level range,
  planned group size and a lifetime of 15–240 minutes. Edit your open post or
  close it when finished. Officers can also close a post.
- **Dungeon groups:** post a dungeon and any preferences. Choose your role and
  respond **I'm ready** or **Tentative**, add a note, or **Withdraw**. Ready and
  tentative interest and role totals are separate. Levels are suggestions and
  interest can exceed planned slots; the organiser chooses the group and
  manually invites members. A signup is not a confirmed group slot.
- **Available helpers:** choose **My availability**, select tank, healer, DPS,
  crafter and/or mentor, and set a note and duration. This is opt-in, appears
  only while online, expires automatically and does not restart at login.
  It does not enable map location sharing.
- **Starter kits:** officers can copy the bag, First Aid or Tailoring examples,
  customise item quantities, choose bank supplies or craft work per line, and
  save a reusable guild template. **Prepare kit** previews the recipient and
  requires a guild crafter with a shared recipe for each craft line. It creates
  one Project with normal bank/craft requests, which retain the existing
  approval, exact-mail and delivery tracking. The same kit cannot be launched
  again for the same member while its project remains active. Finish or cancel
  its requests and archive the old project before repeating it. Retiring a
  template preserves projects already created from it. An officer confirms the
  starter-kit checklist step after reviewing delivery progress.

New features require the updated addon on participating members' clients.
Posts expire, draft fields survive background refreshes, and actions do not
announce themselves to guild chat. Recent records can sync from their author
when a member joins even without an officer online. Officer sync recovers
missed guild data; old activity records are removed after 30 days. Starter-kit
templates are retained until retired, and retirement records are retained to
prevent old copies reappearing. The Discord companion does not manage these boards.

## One mail for a member's bank requests

With a mailbox open, view an approved bank request and choose **Fill mail for
this member**, or open the recipient's Roster details and choose **Fill member
mail**. `/epu mail <member>` prepares the same combined draft directly.

The preview lists approved bank requests for that exact recipient. **Fill mail**
combines their remaining quantities, including several requests for the same
item, up to the game's attachment limit. Requested items must already be in
the bank character's bags; the addon cannot mail directly from bank storage.
It preserves an existing draft and uses the same exact-quantity safeguards as
single-request mail. Review the attachments and click **Send** yourself.
Only quantities actually sent are counted, oldest selected requests first.
Missing stock or quantities beyond the attachment limit stay open, and requests
that arrive after preparation do not consume this draft's delivery credit.

## Crafting projects

The **Projects** page lets officers create a named guild goal, then **Add craft task** for each shared recipe. Shift-click an output item (or enter its item ID), choose a crafter who knows it, enter the quantity and recipient, and **Assign**. Each task creates a normal craft request: the crafter accepts or declines, and deliveries advance project progress. Multiple tasks can cover a larger guild goal such as bags for recruits or equipment for several members.

Project details show the remaining recipe materials and bank counts. **Stock materials** raises standing material reserves in Needs; approved bank-funded craft requests add their own consumption to Shopping so the reserve is maintained after crafting. Reagent quantities use the addon's existing recipe calculation; check recipes that produce multiple items per craft. Enchants are services and must be marked made manually after the trade. Completed project requests retain their history. Finish or cancel active tasks before archiving a project.

## Getting started checklist

**Getting started** shows your checklist; officers can review everyone's progress. Members confirm their own rules and setup steps. Officers confirm Discord identity and record a public mentor/starter-supply note. **Edit instructions** beside a checklist step changes the guild's instructions; officers can add steps using a new Step ID and select whether a member or officer confirms them. Confirming a step is a record of a person's acknowledgement, not automatic proof that they read a document or delivered starter supplies.

## Delivery and bank accuracy

Requests now keep **delivered** and **remaining** quantities. A partial shipment leaves the request approved. Mail prepared with **Mail it** counts toward that request only; other deliveries are allocated to the oldest approved matching request first. Reopening a filled request resets its delivery credit and preserves its history. Officers should coordinate before simultaneously sending the same request: an addon cannot make two offline clients' physical deliveries atomic.

Mail preparation leaves an existing draft alone: send or remove its attachments before preparing another request. The helper checks actual attachment quantities after splitting and removes an attachment if it differs from the requested amount. Missing or locked stack information stops preparation. Always review the outgoing attachments before pressing Send.

A guild-bank snapshot is published only after every tab is accessible and has responded. If a scan is incomplete, the previous snapshot remains in use with its previous observation time. Reopen the bank to retry a query that never responded. Recent guild sync does not mean someone recently inspected the physical bank.

## One-time setup (officers)
- **Bank alt:** log onto the bank character and type `/epu bankalt on`, then open its bank once. Give the bank alt a guild rank with "Bank" in its name (e.g. *Bank*), or an officer rank. Otherwise other members' addons ignore its updates.
- **Trust:** by default ranks 0–1 (GM + officers) are trusted. If officers sit at rank 2, type `/epu officerrank 2`. Each player sets this locally, so it's easiest to keep officers at rank 0–1.

## The window
Open it with `/epu` or the minimap bag. It has a sidebar on the left with counts on each section: red for low-stock needs, gold for requests waiting on an officer. The search box at the top filters whatever section you're in. Drag the bottom-right corner to resize; `/epu scale 0.9` makes everything smaller and `/epu resetwindow` puts it back.

**Click any row for details.** From there you can fix mistakes:
- Requests: change the quantity, note or which character it's mailed to. Officers can also set any status (including reopening something filled by mistake) and give a reason when rejecting.
- Needs: change the target or switch between Restock and One-time goal.
- Donations: officers can void one that was logged by mistake.
- Bank and shopping items: request them, or add them as a need.

**Mail it.** With a mailbox open, an officer clicks the mail icon on an approved request (or **Mail it** in its details). The addon fills in the recipient and subject and attaches the right number of the item from your bags, splitting a stack if needed. Check it and press Send; the request turns Filled when the mail goes.

**Crafters and recipes**
- **Crafters** lists everyone's professions and skill. Officers can mark **guild crafters** (for example, our Tailor) from a crafter's details. Guild crafters get a star and are listed first everywhere.
- **Recipes** lists every recipe guild members can make. It's searchable, and you can filter by profession, *Online* (someone who can make it is on now) or *Guild crafters*. Click a recipe to see who can make it, with a Whisper button for each. BoP items are left out, since they can't be passed on.
- A crafter's recipes (with their materials and skill-up colors) are shared the first time they open their profession window with the addon, and again when they learn something new.
- **Materials:** a recipe's details list its reagents and how many the guild bank has, plus how many crafts the bank could cover. Officers can click **Stock mats for 5 crafts** to raise the bank's needs to match.
- **Skill-ups:** a colored **+** after a crafter's name means they'd still get a skill point making it (orange always, yellow usually, green sometimes). The *Skill-ups* filter shows only those, so work goes to the crafters who are still leveling.
- **Craft requests:** in a recipe's details click **Ask ... to craft**, pick the amount and who provides the materials (you, the guild bank, or the crafter). The crafter gets a pop-up and can **Accept** or **Decline**; mailing or trading what they made marks it **Made**. Craft requests appear under Requests (use the *Crafts* filter) and on Discord. They don't count toward the bank's request limit. **Mail materials** fills a mail to the crafter for you.
- **Tooltips:** crafted items show which guildmates make them. Patterns and recipes say whether someone in the guild already knows them, and if not, who has that profession.
- **Coverage:** the Officer page lists professions nobody has and ones without a guild crafter. **Profession coverage** shows each profession's players, best skill and who's online.

**Helping out without opening the window**
- **Tooltips:** hover any item and you'll see "Guild bank needs 40 more" (or how many the bank holds, or your request's status).
- **Bag coins:** items the bank needs get a small gold coin in your bags. It works in Blizzard's bags and in Baganator; in Baganator you can move it under its icon corner settings.
- **Donate at the mailbox:** a panel opens next to the mailbox listing the needed items you carry. Choose how many of each with - / + (shift for 10), the mouse wheel, or **Max** (what the bank still needs; click again for all you have). Nothing is added unless you pick it. **Fill mail** addresses it to the bank and attaches your picks; you check it and press Send. "Show everything I carry" lets you give other things too.
- **Pop-ups:** you get a notice when your request is approved, filled or declined. Officers also get one for each new request.
- Turn any of these off with `/epu tooltips`, `/epu markers`, `/epu donate`, `/epu notices` (officers: `/epu officernotices`). `/epu welcome` shows the welcome tips again.

**Roster and News**
- **Roster** lists every member with level, class, zone (when online) or when they were last seen. Filters: *Online*, *Near my level* (online and within 3 levels, for finding leveling partners) and a role dropdown. Click someone to whisper or invite them.
- **My profile** (on the Roster page): tick Tank, Healer and/or DPS and add a short "looking for" note, like "LF Deadmines". Alts without their own profile show their main's.
- **News** shows officer announcements, then guild milestones: every 10 levels, first mount, profession ranks (75/150/225/300), big donations (5g+, or 20+ of something the bank needs) and new members. Guildmates online get a pop-up; turn them off with `/epu milestones`. `/epu milestonechat` also announces your own in guild chat.
- **Announcements** pop up for everyone the next time they log in, until they click Got it. Officers post them from News, or from Discord with `/announce`.

**Officer review** (officers only, on the Roster page and each member's details): join date, levels gained in the last 14 days, donations and requests in the last 30 days (across alts), an *Inactive* tag after 30 days away, and a *Promote?* tag for members at the lowest rank who meet the promotion check you set on the Officer page. Officers can leave **notes** on a member. Notes and the **Officer log** (who approved, rejected, voided or changed what, and when) only travel on the officer channel, so members never receive them.

**Officer page** (officers only): which ranks can manage the bank, whether this character is a bank, a per-player limit on open requests, the Discord inbox, and tools to post needs to guild chat, force a sync, or tidy finished requests away.

## What it does
| Tab | What it's for |
|---|---|
| **Needs** | Officers set targets. A **Restock** target is a standing minimum ("always keep 20 healing potions"). A **One-time goal** removes itself once the bank reaches it ("100 Runecloth for the raid push"). Everyone sees progress bars against what the bank alt actually holds, turning red when an item is under half stocked, plus how many of each item **they're carrying** (shown in green). |
| **Shopping** | What the bank needs to buy: every shortfall below target, plus approved requests the bank can't cover. **To Auctionator** saves it as an Auctionator shopping list called "EPU Guild Bank", quantities included, so it can be bought in one pass at the AH. |
| **Bank** | Searchable contents of the **guild bank** and every bank alt's bags and bank, plus their gold, without logging onto the bank alt. The guild bank is read whenever an officer opens it. Its deposit log also feeds the Donations tab. |
| **Requests** | Members ask for items, and the request starts as *pending*. Officers **Approve** or **Reject** it; type a reason in the Note box first to include one. Officers' own requests are approved automatically. When an officer or the bank alt mails or trades an approved item to the requester, the request is marked **filled** automatically. There's also a manual **Fill** button. Requesters can **Cancel**. |
| **Donations** | Automatic log of anything a guild member mails or trades to a bank alt. COD mail and Auction House mail are skipped. Shows top donors for the last 30 days. |
| **Crafters** | Each member's professions and skill levels, filled in automatically. Search by profession or name. **Who crafts?** asks the guild live who knows a recipe. |

Adding an item: click into the item box, then shift-click the item in your bags. You can also drag the item onto the box.

## Commands

The request-status dropdown counts the same search, Mine and Crafts matches as the list. The footer shows how many requests are visible out of the selected status total. Use the X in the search box to clear the search.

The Donate panel includes eligible items in your equipped reagent bag as well as your backpack and regular bags. Prepared donation mail and guild-bank deposits can draw from those containers; stored bank items and soulbound items are not offered as carried donations.

If WoW reports message throttling, EPU pauses and retries with increasing delays rather than rapidly resending. Login syncs and visible guild needs/milestone posts share conservative pacing. `/epu net` reports EPU's queue, accepted/refused sends, recent-send warnings and cooldown for this session. A shared server warning cannot identify which addon caused it; EPU does not hide these warnings.

```
/epu                         open/close the window (or click the minimap bag)
/epu need <item> <qty> [goal]  officers: set a restock minimum, or add "goal" for a one-time goal (qty 0 removes)
/epu shop                    save the shopping list to Auctionator
/epu request <item> <qty> [note]
/epu who <item or name>      who in the guild can craft this?
/epu post                    post the top 5 open needs to guild chat
/epu bankalt on|off          mark/unmark this character as a bank alt
/epu main <name>             choose which of your characters is your main
/epu alts                    list your characters the addon knows about
/epu officerrank <n>         ranks 0..n are trusted
/epu sync                    ask online officers for a full resync (also: right-click minimap button)
/epu save                    save now (a /reload) so the Discord companion sees the latest
/epu minimap                 show/hide the minimap button
```

## How sharing works
- Data travels over hidden addon messages on the guild channel. There's no website or server. Each player's copy is saved in their SavedVariables.
- When you log in, the addon asks for anything new. One online officer answers, and the others stand down.
- Only trusted ranks can publish needs, bank contents and donation records, or approve, reject and fill requests. Anyone can post (or cancel) their own requests and their own professions.
- Each crafter's recipe list is shared with the guild (only theirs; nobody else can publish it). The older "Who can craft...?" button still asks online members live, for anyone who hasn't opened their profession window yet.
- Craft requests can only be accepted, made or declined by the crafter they were sent to (or an officer).

- Join dates start when an officer first runs 0.8.0, so everyone already in the guild shows "in the guild since before" that day. Levels gained come from each officer's own PC, so they start counting from when that officer installed it.
- The Roster page turns on "Show offline members" in the guild list once, so it can see everyone.

## Mains and alts
The addon notices every character you log in with, since its saved data is shared across your WoW account, and tells the guild which characters are one player.
- Alts show as **"Pip Quickfoot (Brenna Ashford)"** in tooltips.
- The donor list counts a player's alts together.
- Your main is the first character you used with the addon. Change it with `/epu main <name>`.
- When you request something, the **For:** button on the Requests tab picks which of your characters it gets mailed to. Officers see that character under **Mail to**. Mailing the item to that character marks the request filled.
- A character joins your group once it has logged in with the addon at least once.

## Discord
The **EPU Discord companion** (a separate download) posts requests to a Discord channel and lets members `/request` and officers Approve or Reject from Discord. Because addons can't reach the internet, changes pass through files when an officer types /reload or logs in or out. See the companion's README.

## Known limits
- Needs at least one officer (or the bank alt) online to sync someone who was offline.
- Guild bank contents are only published when an **officer** opens the guild bank. Members' views stay local, so nobody can fake the counts.
- Bank contents update while the bank alt is online. The bank itself is re-read each time its bank window is opened.
- Mail logging hooks the standard mail functions. A mail addon that loads before this one and grabs mail its own way could slip past. Trades are always caught.
- A guild member who isn't in the roster yet (just joined) won't be credited for donations until the roster refreshes.

## Guild map (0.11+)

Shift-click the EPU minimap button or use `/epu map` to open the guild map controls.
Check **Share my outdoor location** to opt in on this account; it starts off.
You can also use `/epu sharelocation on` or `/epu sharelocation off`.
Showing world map markers and nearby minimap markers can be toggled separately.
Click a marker to whisper; hover for name, level, class, zone, coordinates and update age.

Both players need EPU 0.11 or newer, and the member being shown must opt in.
Updates are approximate, at most once per 30 seconds while moving, with a 60-second
heartbeat while stationary. Busy sync traffic takes priority. Markers expire after
two minutes without an update and disappear when the roster reports the player offline.
Sharing stops inside instances or when coordinates are unavailable. No location
history is saved or relayed by the addon or Discord companion. Guildmates may be
on another layer or phase, so a marker does not guarantee that you can see them.

Map placement uses bundled HereBeDragons 2.18, which supports Forever and handles
parent maps, minimap zoom, rotation and clipping. Live Forever verification is pending.
