# Changelog

## Unreleased
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
