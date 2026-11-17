QUEST PARTNERS - 0.6.0 / RELEASE
Compact party quest tracking for WoW Forever 1.60.1 (interface 16001).

INSTALL
Copy the QuestPartners folder into the active client's Interface/AddOns folder.
QuestPartners.toc must be directly inside QuestPartners, without a second nested
folder. Install the addon on every participating player's client, then restart
WoW. Use /questpartners settings. /qp is an alias when not claimed elsewhere.

USE
Type a title, item or creature in the tracker search. Click a quest's star to
keep it expanded in Working on at the top; star it again to remove/collapse.
The shortlist is saved for your character, while search is temporary. Existing
All/Shared, region and completion filters still apply. Level colours follow
your character's quest difficulty. Settings cycles Badge / Number only / Off.

Join the same normal or instance party (up to five players). Initial sync can
be slower for larger logs. Normal pickup/kill updates are automatic.
Choose All or Shared quests; click titles to expand, or use region groups.
Settings controls opacity, colours, text size, sorting and local completion
bubbles. Sound is off by default. Right-click a quest for permitted actions.

COMMANDS
/questpartners              Show/hide
/questpartners settings     Options
/questpartners quests       Quest manager
/questpartners regions      Region controls
/questpartners sync         Recovery sync request
/questpartners status       Version and diagnostics
/questpartners reset        Reset position/size
/questpartners demo         Clearly labelled fictional progress

COMPATIBILITY AND LIMITATIONS
Every player whose progress you want to compare needs Quest Partners; use the
same version where possible. Other WoW clients, raids and other addons' sharing
protocols are not supported. Large logs can reach the bounded sync payload.
Unknown/offline/stale values are labelled. Exact client/addon combinations may
still expose issues; please report reproducible problems. Bubbles are local screen overlays, not chat
messages or world-space speech bubbles. The addon never auto-accepts, abandons
or turns in quests. Native sharing is an explicit click and may be unavailable.

FEEDBACK
Report the version, client build, party size, steps and /questpartners status
from affected players through the project feedback channel. Remove unrelated
personal information. Do not include passwords, API tokens or whole WTF folders.

MIT License; see LICENSE.txt. No external account or paid dependency required.
