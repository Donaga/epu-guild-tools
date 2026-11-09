# Maintaining the Forever guide library

`data/guide_sources.json` is the reviewed source registry. Run
`python tools/build_guide_catalog.py` after editing it; commit the resulting
`EPUGuild/GuideCatalog.lua`. The game reads this offline catalog and never
downloads web pages. Summaries are original, short descriptions, with credited
authors and copyable full-source links. Do not reproduce complete articles,
talent allocations, quest routes or material tables.

## Selection and coverage

The initial review on November 7, 2026 compared Forever-specific class,
leveling, talent and profession sources from Mobalytics, Method, Icy Veins,
WoW-Professions and 60.tools. The catalog has 107 sources; a player sees only a
small relevant subset. Creator-authored Mobalytics class routes are the default
leveling source. Method offers an alternative. Icy Veins adds class references
and matching specialization routes. 60.tools supplies class planners and
profession routes. These choices prioritize coverage and useful explanations
for a casual leveling guild, and are editorial choices rather than universal
rankings.

Several sources still contain beta/pre-launch assumptions despite a recent
page date. Preserve those labels. WoW-Professions explicitly describes its
Forever routes as beta-derived; these are optional alternatives. Some Method
crafting pages describe coverage only through skill 225: keep them capped at
224 and choose an applicable broader route from 225 onward. Do not trust a
1–300 title over the actual article. 60.tools currently identifies launch data
build 1.60.1.70790; a data snapshot is not proof of later tuning compatibility.
Some general zone pages have stale or inconsistent ranges and were excluded.
Do not substitute Classic, Season of Discovery or Retail advice for Forever.

The November 9 review corrected Method Skinning to skill 224 and Herbalism to
204: their later sections are explicitly unfinished or speculative. Leatherworking
retains a beta disclaimer. A `focus` label identifies a class leveling path aimed
at one playstyle; it remains a labelled option before a playstyle is chosen and
is hidden when a different focus is chosen. A stricter `spec` entry requires a
matching chosen/detected specialization. Saved guides bypass neither filter.
Short `notice` fields flag verified conflicts or announced changes without
inventing post-hotfix builds.

November 10 Enhancement tuning remains announced as of this review. Blizzard
advises collecting Strength/Attack Power equipment now; some linked material
still prioritizes Intellect. Show the caution, then recheck after the hotfix.
Do not guess new talent allocations. The full automated check found 98 accessible
sources and nine Mobalytics HTTP 403 responses; blocked pages were checked with
the web tool. No broken links were confirmed. Icy Veins text was unchanged even
where raw-page hashes differed. Beta route table edits were read but no recipe
quantities are copied into the addon.
Blizzard also confirmed a November 8 hotfix increasing dungeon enemy kill XP by
50%; class leveling sources now carry a dated note about older route comparisons.
Source: https://us.forums.blizzard.com/en/wow/t/dungeon-enemy-xp-increased-november-8/2406595/1

Player relevance is mandatory: current class, level, learned profession IDs and
skill range, and matching talent focus for specialization entries. Never show
other classes or unlearned professions through saved guides or alternatives.
Use live skill APIs, not another character's cached profession data. Where a
recognized active specialization is unavailable, let the player choose a focus
from their own class; never infer a Classic tree from a Retail numeric index.
Private bookmarks, notes and progress stay in the per-character saved variables.

## Weekly review procedure

The chat automation **Review EPU Forever guides** runs Mondays at 9 a.m.
America/Indianapolis. This is an external Codex task, not an addon timer or a
GitHub workflow. Local automation needs the computer and Codex app running.

1. Read repository instructions and inspect the worktree. Preserve unrelated
   work. Review current official Blizzard Forever hotfixes and class tuning;
   `patchSources` records starting references, not a permanently current feed.
   In particular, November 10 tuning was announced but had not landed at the
   initial review. Do not describe future changes as already live.
2. Run `python tools/check_guide_sources.py --output /path/to/report.json`.
   This read-only report fetches approved HTTPS hosts with bounded requests.
   A changed text hash is a review signal, not evidence that advice changed.
   Dynamic navigation, ads and timestamps can also change the hash. The checker
   does not modify the registry or make content decisions.
3. Read changed/relevant source sections and compare actual live coverage,
   talent/skill ranges, author update dates and official changes. HTTP 401/403/429
   means access is restricted, not that the guide is dead. Try a normal browser
   or another verified source; report what remains unverified. Confirm 404/410
   results and replacements manually before disabling a source.
4. Update only verified facts, original summaries, coverage, source URLs and
   metadata. `updated` is the publisher's date; `reviewed` is the date of actual
   editorial review, not merely a successful request. Update `pageHash` after
   examining the page. Use `needs_review` or `unavailable` to suppress an unsafe
   source when warranted. Flag uncertainty instead of inventing exact builds.
5. Regenerate the catalog and run `python tools/build_guide_catalog.py --check`
   and `python tests/test_guides.py` with the project's test dependencies, plus
   relevant regressions. Inspect the diff and privacy/relevance behavior.
6. For substantive verified corrections, bump the TOC patch version and
   changelog, create a focused PR, wait for all checks, merge, wait for main
   checks, and publish the next patch release using the established release
   process. Verify Release workflow success and addon, companion, updater and
   release.json assets. Do not release merely to advance review dates.
7. Report checked sources, actual changes, remaining uncertainty and the PR or
   release link. If nothing needs changing, report that without making a release.

The UI shows each source's status, publisher date and editorial review date;
after fourteen days it labels review as due. That label is an age indicator,
not proof that the guide became wrong. Full guides open through a copyable URL;
the addon does not execute downloads, apply talents or silently change advice.
