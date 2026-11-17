# Contributing

Please open a focused issue or pull request with reproduction steps and the intended behaviour. Target WoW Forever 1.60.1 / interface 16001; do not claim another client is supported without verification.

Install requirements-dev.txt and run the Lua 5.1 mock-client tests from the README. Add a regression when fixing a behavioural failure, then check the affected flow in the actual game. Include what was tested and any remaining limits in the pull request.

Keep runtime APIs and commands guarded and avoid overwriting another addon's globals. Keep party payloads bounded and validate received data. Preserve per-character preferences. Never commit credentials, saved player data or personal screenshots.

Build through tools/build_release.py. Code/version/changelog changes belong together. Publishing is manual and is not triggered by a source commit. Screenshots should show the current real client; clearly label demo data.
