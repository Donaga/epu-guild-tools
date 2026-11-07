EPU Guild Tools updater
=======================

Tip: the easiest way to get and update the addon is now the CurseForge app:
https://www.curseforge.com/wow/addons/epu-guild-tools
(click Install, pick your Forever install). If you use CurseForge, you don't
need this updater; to stop it running at startup, run:
"Update EPU Guild Tools.bat" nostartup

1. Unzip this folder somewhere you'll keep it, e.g. Documents\EPU Updater.
   Don't delete it afterwards: the automatic updates run from here.

2. Double-click "Update EPU Guild Tools.bat".
   It finds your WoW: Forever folder (or asks you to pick it once), installs
   the newest version of the addon, and tells you what it did.

3. Optional: double-click "Update automatically at startup.bat" once.
   From then on the addon updates itself quietly whenever Windows starts.
   To stop that, run:  "Update EPU Guild Tools.bat" nostartup

If Windows asks "Do you want to allow this app to make changes?", say Yes.
WoW keeps its addons under Program Files, which sometimes needs permission.

Your requests, settings and saved data are never touched; only the addon's
files are replaced. If WoW is running, type /reload after an update.
0.10 update safety: the updater stages and validates the complete addon before
replacing it, preserves the Discord inbox, and retains the previous installation
in a sibling .EPUGuild-backup-* folder. If recovery is needed, close WoW and the
companion before restoring that folder as EPUGuild. Old backup folders can be
removed once the new version has been checked in game.
