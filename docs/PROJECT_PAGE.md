# Quest Partners

## Less coordination. More questing together.

Who still needs one more drop? Which quests do we both have? What should we work on next?

Quest Partners brings your party's quest progress into one compact, adjustable tracker for **WoW Forever**. Compare objectives by player, focus on shared quests, and keep the quests you are working on within easy reach.

**Early Alpha:** the current build is 0.6.0-test9, targeting Forever 1.60.1 / interface 16001. Every player whose progress you want to see needs Quest Partners installed. Using the same version is recommended.

## See what everyone still needs

- **Progress for each player:** expand a quest to compare objective counts and progress bars in one tracker.
- **Automatic updates:** participating clients exchange quest and objective changes while you play.
- **Useful status indicators:** distinguish live, waiting, stale and offline data. Missing progress is labelled rather than presented as a zero count.
- **Behind-player highlights:** identify the lowest confirmed progress when another quest holder is further ahead.
- **Party support:** designed for normal and instance parties of up to five players, including you.

## Find the next quest without managing a long list

- **Shared or All:** show quests you share with at least one synced partner, or browse known party quests. When playing solo, see your own quests.
- **Search by quest or objective:** search a quest title, item or creature mentioned in an objective, including objectives supplied by other synced players.
- **Working on shortlist:** click the star beside a quest to keep it at the top and expanded. Your shortlist is remembered for your character.
- **Region groups:** collapse or hide quest-log categories, or switch to a flat list. These groups follow the quest log; they are not a navigation or routing system.
- **Compact summaries:** other quests start collapsed. Open the ones you need or allow temporary expansion when progress changes.
- **Sorting and selection:** sort by level, title, recent progress or ready-to-turn-in status, and choose individual quests when needed.

Search and visibility settings affect your display; hidden quests continue syncing. Existing filters also apply to the Working on shortlist. Turned-in quests are removed when the client reports their removal, and the hide-finished setting helps keep completed entries out of the active list.

## Make it fit your screen

Adjust background opacity, colours, font size, progress-bar height and spacing. Use a compact display for larger parties and scroll long lists inside the panel.

Quest levels can use the game's difficulty colours in a small badge or on the level number alone. Colours are relative to your character's level; quest titles keep your chosen heading colour. Difficulty colouring can also be switched off.

## Optional completion notifications

Short speech-style bubbles can show when you or a synced party member completes an objective. They identify the player, quest and completed objective. An additional notification can mark when all confirmed quest holders are ready to turn in.

These are local notifications near the top of your screen. They do not post to party chat or appear above characters in the world. Sound is optional and off by default.

## Getting started

1. Install Quest Partners on every participating player's client.
2. Join the same party and allow the initial sync to finish.
3. Choose Shared or All at the bottom-left of the tracker.
4. Search for an objective and star the quests you want to work on.
5. Open `/questpartners settings` to adjust readability and notifications.

For manual installation, exit the game and extract the addon ZIP so that `Interface/AddOns/QuestPartners/QuestPartners.toc` exists. Avoid an extra nested QuestPartners folder. Restart the game and enable the addon.

## Useful commands

- `/questpartners` - show or hide the tracker.
- `/questpartners settings` - appearance and behaviour settings.
- `/questpartners quests` - quest selection and visibility.
- `/questpartners regions` - region grouping and visibility.
- `/questpartners sync` - request fresh party data.
- `/questpartners status` - version and sync diagnostics.
- `/questpartners reset` - reset panel position and size.
- `/questpartners demo` - clearly labelled fictional progress preview.

The shorter `/qp` command is available when another addon has not already claimed it.

## Compatibility and Alpha feedback

This build targets **WoW Forever 1.60.1 / interface 16001**. Other WoW clients and raids are not supported. No external account, backend or additional addon is required. Quest data is exchanged with the current party, and preferences are saved per character.

Quest Partners does not exchange progress with other quest-sharing addons. It does not automatically accept, abandon or turn in quests. Explicit quest-sharing actions follow the client's normal restrictions.

The build has passed 117 automated Lua 5.1 tests, including sync, long-list, hostile-input and shared-interface checks. Live testing is ongoing; this does not establish compatibility with every addon combination. Large initial exchanges or client message throttling can delay updates. Current sync limits are 100 quests per participant and 20 objectives per quest.

If you encounter a problem, include the addon version, client build, party size, steps to reproduce and `/questpartners status` from the affected players. Remove unrelated chat and personal information from screenshots. Until a public issue tracker is linked, use the project's CurseForge comments.

## Why Quest Partners?

The project started when two brothers returned to World of Warcraft around twenty years after playing the original game. Playing together from Thailand and Europe revealed a simple need: spend less time comparing quest logs and more time enjoying the game together.

Developed with AI assistance and refined through playtesting. The project icon uses generated artwork for branding; it is not a gameplay screenshot. Distributed under the MIT License.
