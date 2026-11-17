# Quest Partners

Compact party quest comparisons for WoW Forever. Compare each player's objectives, search by quest or objective, and star a small Working on shortlist.

**Early Alpha: 0.6.0-test9.** Targets Forever 1.60.1 / interface 16001, for normal and instance parties of up to five players. All participating players need the addon; using the same version is recommended. Live testing is ongoing. Other WoW clients and raids are not supported.

## Features

- Automatic party quest/objective updates with explicit live, waiting, stale and offline status.
- All/Shared filters, manual selection, region groups and collapsed summaries.
- Quest/objective search and a persistent, expanded Working on shortlist.
- Adjustable opacity, colours, text size and bars; optional level-difficulty badges.
- Per-player counts, behind-player highlights and optional local completion bubbles.

See [the user guide](QuestPartners/README.txt) and [project overview](docs/PROJECT_PAGE.md). The current CurseForge project is [Quest Partners](https://www.curseforge.com/wow/addons/quest-partners), ID 1811599; the initial Alpha file has been submitted and is awaiting moderation, according to the author’s 17 November 2026 update. A public download has not yet been independently verified.

## Install

Use a built addon ZIP, not GitHub's Source code archive. Exit WoW and extract it so `Interface/AddOns/QuestPartners/QuestPartners.toc` exists, then restart and enable the addon. For a source checkout, copy only its QuestPartners folder into AddOns.

Open `/questpartners settings`. Join a party, allow initial sync, choose Shared or All and star the quests you want to work on. `/questpartners status` prints version and sync diagnostics. `/qp` is available only if another addon has not claimed it.

## Develop and validate

Python 3.10 or newer and Lupa with Lua 5.1 support are needed for the isolated mock-client tests:

```sh
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tests -p "test_*.py" -q
python tools/build_release.py
```

The current suite has 117 tests. Simulations cover sync, hostile inputs, resource bounds and shared-addon boundaries; they do not certify the actual game renderer or every addon combination. Test the built archive in the actual client before publishing.

The standard-library builder uses an explicit allowlist and writes `upload/QuestPartners-0.6.0-test9-forever-alpha.zip`. It excludes tests and development documents. Automatic publishing is not configured. See [the update and release process](docs/RELEASING.md) and [release checklist](docs/RELEASE_CHECKLIST.md) for keeping GitHub and CurseForge aligned.

## Feedback and contributions

See [CONTRIBUTING.md](CONTRIBUTING.md). Include the client build, addon version, party size, reproduction steps and relevant sync diagnostics in reports. Remove unrelated chat/account details. Do not include saved character settings or credentials.

No external account or backend is needed by the addon. Party quest data is exchanged with participating clients and preferences are stored per character. The addon does not automatically accept, abandon or turn in quests.

## Licence and credits

MIT, copyright 2026 Christian Reiners. Developed with AI assistance and refined through playtesting. The icon uses generated artwork for branding. Test-character names in this repository are fictional fixtures.
