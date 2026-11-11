# Activities and the WoW guild calendar

Open `/epu activities` or `/epu calendar`. Choose **Activities**, then **New event**. Select Dungeon, Leveling, Quest / elite help, Fishing, Profession, Farming or Other. Enter the meeting place, helpful details, local start time, duration, player count and suggested level range. **Pick date** provides a month grid; the time stays editable. Plan up to 28 days ahead, for 15 minutes to eight hours.

The board's **Type**, **Mine** and **Calendar** controls combine with search. The calendar numbers count upcoming activities on each local date. **All dates** clears the date filter. Quick quest help and quick dungeon boards remain available for short-lived posts.

Open an activity to volunteer as Going or Tentative, choose a role and leave a note. Helper, Crafter and Mentor are available as well as Tank, Healer and DPS. Signups express interest; the organiser confirms the group. EPU does not automatically invite players or enforce the planned player count. Followed activities and signups use the existing reminder settings.

## Optional WoW calendar copy

EPU events are not automatically published to WoW's calendar. **Create event** saves the EPU activity only. **Create + WoW calendar** also prepares a native guild signup draft when supported. Review it and press WoW's **Create** button to publish it for members without EPU. Opening the calendar alone does not publish an activity.

For an existing activity, the organising character can open **WoW calendar > Prepare WoW draft**, then press WoW's **Create** button. Other characters see the organiser's full name and instructions to ask them to publish; they cannot create a linked copy on the organiser's behalf. EPU never presses Create or changes a currently open native event/draft. An EPU signup alone does not confirm that a WoW copy exists.

If preparation is unavailable, create a guild signup event manually using **Copy title** and **Copy details**. Select each field and use Ctrl+A / Ctrl+C. Keep the `[EPU:...]` marker in the description, and match the organiser, copied title and server start time exactly. WoW's native form limits its title to 31 characters and description to 255; EPU retains the full activity text and shortens only the calendar copy. Native availability, guild permissions, date limits and event locks still apply.

## Signups between calendars

Open the matching event in WoW's calendar. EPU reads its attendee list when the game supplies it; **Refresh open event** retries after it finishes loading. The activity shows one row per guild member, including calendar participants without EPU. A current native response takes priority over that person's EPU status; their EPU role and note remain. Standby is tentative, not a confirmed place. People with no native response retain their EPU signup.

These native snapshots are local to the viewing player, held only for this session and valid for three minutes. They are not broadcast as another member's authored EPU response. Other viewers refresh the native event themselves. The screen labels the source and snapshot age; after expiry it returns to EPU signups. This is a combined view with explicit own-response actions, not continuous background two-way synchronization.

With the linked event open, **Going in both**, **Tentative in both** and **Decline in both** send your own response to WoW and save your EPU response. Check WoW's acknowledgement; a server rejection or required approval can leave the two statuses different. EPU never changes somebody else's response. Ordinary Going/Tentative buttons affect EPU only. Native changes alone do not rewrite EPU roles, notes, following preferences or reminders.

Event edits and cancellations are separate. Update both copies. An EPU title or time change stops matching native attendees until the WoW copy is corrected. Review the calendar before creating a second copy; draft preparation blocks a same-title event on that date, but does not search all dates for manually moved events.

## Validation and API reference

Automated tests cover sync ownership, types, roles, level ranges, date filtering, actual form controls, leap dates, native matching, attendee deduplication, partial lists, expiry, locked/restricted responses and draft safeguards. Native publishing and rendering still need confirmation in the live Forever client.

The bridge follows Forever's [generated Calendar API](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/CalendarDocumentation.lua) and [native Calendar UI](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_Calendar/Mainline/Blizzard_Calendar.lua). Features are checked at runtime; source availability is not proof that every server/account supports publishing.
