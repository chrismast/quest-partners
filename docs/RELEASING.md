# Release 0.6.0 and later updates

The 0.6.0 Release retains Test9 behaviour. Only the addon version and release documentation change. Keep the original Test9 Alpha and never replace its bytes under the same file version.

## Validate and build

From the repository root:

    python -m pip install -r requirements-dev.txt
    python -m unittest discover -s tests -p "test_*.py" -q
    python tools/build_release.py --channel release

The stable version 0.6.0 defaults to Release and writes upload/QuestPartners-0.6.0-forever.zip. Test9-style prerelease suffixes default to Alpha, beta suffixes default to Beta, and explicit --channel alpha/beta/release is supported. The builder rejects Release packaging when the version still has a prerelease suffix. Keep Core.VERSION and the TOC identical.

The suite comprises 117 addon regressions and 8 packaging checks. Automated mocks do not certify the live game renderer or all addon combinations. A short load/party check remains a human step; existing playtesting does not need to be repeated in full for this metadata-only promotion.

## Publish the same artifact on both platforms

1. Merge reviewed source and record its exact commit.
2. Tag that commit v0.6.0 when creating the matching GitHub release; do not let later main changes move the release target.
3. Use the one validated ZIP and its SHA-256 on both platforms. Never build separately for each upload. GitHub's generated Source code ZIP is not the addon installer.
4. In CurseForge project 1811599 > Files > Upload file, select the clean ZIP, display name Quest Partners 0.6.0, Release type Release, flavour Forever, game version 1.60.1. Paste docs/releases/0.6.0.md and review publication timing before submitting.
5. Keep the matching GitHub release as a draft until the CurseForge Release is approved and downloadable. Attach the clean ZIP and its checksum; 0.6.0 is a normal release, not a pre-release.
6. Verify the public page/download and then App availability. Check the downloaded artifact's checksum and perform a short install/load check. App distribution may need a separate check after file approval.
7. Publish the matching GitHub release with the actual CurseForge link and record both platform URLs/file IDs.

No automatic publishing is configured. Local GitHub CLI authentication and CurseForge author access are separate from source-edit access. Never put upload tokens in addon files or commit them.

## LinkedIn and recovery

The agreed LinkedIn post stays on hold until its full CurseForge project link opens publicly, leads to a working approved Release download and the package is ready for ordinary use. State the supported Forever client and any known limitations accurately. No automatic posting is configured.

If a problem appears, retain the last known-good artifact/tag and ship a tested fix under a new version. Preserve user settings. Do not move published tags or silently replace assets with different code.
