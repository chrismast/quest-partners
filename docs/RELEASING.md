# Updating Quest Partners on GitHub and CurseForge

GitHub is the source of record. Every downloadable version is built once from a recorded commit and the identical addon ZIP is used for GitHub Releases and CurseForge. Publication is manual initially. A source commit alone does not publish an addon update.

Repository: https://github.com/chrismast/quest-partners
CurseForge project: https://www.curseforge.com/wow/addons/quest-partners
CurseForge project ID: 1811599

## Current state and first-release alignment

The initial 0.6.0-test9 Alpha was submitted to CurseForge and is awaiting moderation, according to the author's 17 November 2026 update. The repository is public and contains the source. Do not upload a second copy of Test9 merely to establish this process. Record the real CurseForge file ID when available.

The expected clean candidate's SHA-256 is:

`f5b90eed5bef57a6c799fe6750f7d3288b37dcde8c4c871058c52072f15b7492`

The expected ZIP is 63,985 bytes, named `QuestPartners-0.6.0-test9-forever-alpha.zip`. These identify the prepared candidate, not independent confirmation of the bytes already uploaded or approved by CurseForge. Confirm those after download.

The original public source commit is `f4773fe10aceeee3f60eb4625dc24057ec119d3c`. Before creating the initial release tag, verify that its runtime files and clean archive match the submitted candidate. Documentation-only commits may differ without changing addon behaviour, but a release must still name its exact source commit. No tag or GitHub release is created by this documentation change.

## 1. Develop in GitHub

Create a short-lived branch for each fix or feature and use a pull request to review it. Keep main as the integration branch; release tags identify the exact shipped source. Track bug reports and enhancement requests in GitHub Issues, while CurseForge comments remain an entry point for users.

Capture a reproducible problem, make the focused change and run relevant regressions. Do not change or remove saved character preferences unnecessarily. Changes to sync messages need mixed-version tests or an explicit requirement for every party member to update.

## 2. Choose a version and release channel

Keep the version in `QuestPartners/Core.lua`, `QuestPartners/QuestPartners.toc`, public changelog, GitHub tag and release title consistent.

| Purpose | Example version | CurseForge channel | GitHub release |
| --- | --- | --- | --- |
| Existing first candidate | 0.6.0-test9 | Alpha | Pre-release |
| Proposed next small fix | 0.6.1-alpha.1 | Alpha | Pre-release |
| Proposed next feature set | 0.7.0-alpha.1 | Alpha | Pre-release |
| Wider test after validation | 0.7.0-beta.1 | Beta | Pre-release |
| Stable version when ready | 1.0.0 | Release | Normal release |

Future numbers are examples, not reserved or scheduled releases. Use tags such as `v0.6.1-alpha.1`. Increment the version for changed public code and never move a published release tag or replace an existing download with different bytes under the same version. A channel promotion alone must not silently change runtime code.

The existing builder names its output as Forever Alpha and records Alpha metadata. It is ready for the current Alpha process. Extend and validate channel support before using it for a Beta or Release; the file form's channel is always an explicit selection.

## 3. Validate and build one artifact

From the repository root:

```sh
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tests -p "test_*.py" -q
python tools/build_release.py
```

At Test9 the suite contains 117 tests. Record the actual count and result for each later release. Automated checks cover mock-client behaviour and resource bounds; live client rendering and addon combinations need live checks.

Test an extracted candidate in the supported Forever client, including a clean install and an update that preserves character settings. Check duo sync, objective updates, reconnect, quest cleanup and the changed feature. Use the larger-party test when the update affects it. An unresolved blocking Lua error or sync regression stops publication.

Merge the reviewed changes when ready and freeze the exact source commit used for the final build. Preserve its ZIP and `BUILD_VALIDATION.json`; calculate/retain the ZIP's SHA-256. Do not edit files inside the archive or rebuild separately for each platform. GitHub's automatically generated Source code ZIP is not the addon installer.

## 4. Prepare the matching GitHub release

Open Releases > Draft a new release. Use the version's tag at the frozen commit, attach the clean installable ZIP and its checksum, and include the public changelog. Mark Alpha and Beta builds as pre-releases. Save a draft while CurseForge review is pending.

Check that the tag points to the intended commit, particularly if main has advanced. Do not assume selecting main later will identify the earlier tested build. Keep draft notes explicit about the pending CurseForge review.

## 5. Submit the same ZIP to CurseForge

For a new version, open project 1811599 > Files > Upload file. Upload the same ZIP prepared for GitHub, enter the same version and changelog, select the intended Alpha/Beta/Release channel, and select Forever / 1.60.1 only unless additional clients have actually been supported and tested.

Review the publication timing option. When offered and desired, select manual/delayed release so approval does not unexpectedly publicize a file. Record the returned file ID and its actual review state in the release receipt. Upload acceptance, moderation approval and public download availability are distinct steps.

Keep the file on the existing project. Never delete/recreate the project for an update. Documentation or gallery edits do not require uploading unchanged addon bytes.

## 6. Verify publication and align both platforms

After approval, check the public page and file download while signed out. Download the approved file, verify its SHA-256 against the frozen artifact, and install that download for the short live smoke test. The check includes loading without Lua errors, preserved preferences and basic party progress sync.

If checks pass, publish the matching GitHub draft release with the exact same ZIP and add the real CurseForge file link to its notes. Update the receipt with both actual links, the tag/commit, checksum, approval state and test evidence. If either platform fails, keep the status honest and pause announcements rather than implying simultaneous availability.

Use `docs/RELEASE_CHECKLIST.md` as a copyable checklist and `docs/releases/0.6.0-test9.json` as the initial receipt. Unknown fields stay null until observed; no placeholder file URL counts as a working download.

## 7. LinkedIn publication condition

The agreed LinkedIn post stays unpublished until all of these are true:

- The CurseForge project and intended file are approved and publicly visible.
- The actual public project link opens while signed out and leads to a working download.
- The downloaded file matches the recorded version and checksum and passes the short installation/party smoke test.
- The post contains the full verified CurseForge project URL and accurately calls the release Alpha, Beta or stable as appropriate.

The expected project URL is `https://www.curseforge.com/wow/addons/quest-partners`. It is not considered verified merely because its format is known. Approval alone does not satisfy the download/test condition. This is a publication rule, not an automatic monitoring or posting service.

## 8. Respond to a broken update

Stop promotion and explain the issue clearly. Preserve the last known-good release, source tag and artifact. Where suitable, restore access to the last approved good file using platform controls without retagging old code as a new build. Ship a tested fix under a new version and link the affected version's notes to it. Keep user settings intact and document any migration requirement.

Never force users to erase SavedVariables as a routine workaround. Do not delete historical artifacts merely to conceal a bad release.

## Later automation

First automate read-only checks, test execution and allowlisted artifact builds on pull requests. A later manual Prepare release action can build from a selected commit and create a GitHub draft. Add CurseForge upload automation only after the manual release flow is proven, using a repository secret for its token and manual publication where supported.

Build once and reuse that artifact. Automated submission must retain the returned file ID; on a timeout or unknown outcome, inspect the existing submission before retrying so it does not create duplicate files. Nothing should publish on an ordinary commit. No workflow, token or upload automation is enabled by this documentation change.

## Platform references

- GitHub releases, drafts, pre-release flags and attached assets: https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository
- CurseForge file channels and submission fields: https://support.curseforge.com/support/solutions/articles/9000197242
- CurseForge upload API, returned file ID and manual-release field: https://support.curseforge.com/support/solutions/articles/9000197321
