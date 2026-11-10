# Guild activities and Discord events

Choose an activity type when creating an event. EPU suggests a title, group size and duration; customized values are preserved when changing type. The current zone is suggested as the meeting place. New events start in about 30 minutes, with shortcuts for 15 minutes, one hour and the next local 7pm. **Group options** expands duration, player count and suggested level range. Dates use the organiser's local timezone and are stored as one shared instant.

Set `events_channel_id` in the companion's private `config.json` to the existing Discord **#events** text channel. The bot needs View Channel, Send Messages, Embed Links and Read Message History. Leave the setting blank to disable posting. No channel permissions or native Discord Scheduled Events are created automatically.

Each upcoming EPU event gets one card with type, localised Discord timestamp, meeting place, level range, organiser and synced EPU signup names/roles. Edits, cancellation and ending update that card. Messages do not ping members. Native WoW calendar attendee snapshots remain local to the viewer and are not included in these cards.

Discord users need an officer-verified `/link` to a current guild character. Choose a role, then **Going**, **Maybe** or **Can't make it**. Each action applies to the first verified linked character, shown in the private confirmation. Repeated choices replace the pending action. Existing game notes and roles are preserved unless a new role is selected. Pending responses are labelled **Awaiting game sync**, never counted as confirmed.

The companion stages responses for an officer or approved shared-folder helper. Install the updated addon and helper, log into a whitelisted character and `/reload` to import. Guild sync distributes the response; another `/reload` or logout exports the result to Discord. Later in-game choices take precedence over older queued Discord actions. Helpers can relay signups without editing organisers' events or gaining bank approval powers.

Older helpers continue receiving invite and bank requests. Event responses are only delivered after an updated helper advertises support with an updated addon installed. Keep using a trusted officer's local bridge until a volunteer has their connection folder shared and running. The game cannot read internet updates continuously during a session.
