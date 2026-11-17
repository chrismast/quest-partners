# Release checklist

1. Reproduce issues and change the relevant source with regression coverage.
2. Update Core.VERSION and the TOC version together; write an accurate public changelog.
3. Run the full mock-client suite and test affected flows in the Forever client with a partner.
4. Run python tools/build_release.py. Inspect BUILD_VALIDATION.json and the clean ZIP.
5. Verify install/update preserves settings and live sync, notifications and quest cleanup work.
6. Upload the built archive manually to CurseForge project 1811599, with accurate Alpha/Beta/Release and Forever/1.60.1 tags. Review publication timing.
7. Verify the moderated download and public metadata. Record outstanding limits before wider announcements.

Automated upload/packaging is not configured. Do not use a GitHub-generated source archive as the addon installer. Media must show real current gameplay or be clearly labelled as a demonstration.
