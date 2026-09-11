---
name: release
description: >-
  Cuts a release: confirms main is what should ship, runs the Draft Release
  workflow, walks the draft through review, and publishes it only on explicit
  confirmation. Use when asked to release, ship, tag, or publish a version.
when_to_use: >-
  Trigger phrases: cut a release, ship it, publish a release, tag a version,
  release what's on main, is main ready to release.
allowed-tools: Read Grep Glob Bash
---

`docs/ReleaseProcess.md` has the reasoning; this is the runbook. The version
is decided by the commits and `GitVersion.yml`, and the binaries were built
by CI when the commit landed — you choose *whether* to release, never what
number or what bits.

## Before drafting

1. Confirm `main` is what should ship: `git fetch`, `git log origin/main -1`,
   and `gh run list --branch main --limit 3` to see that the CI run for that
   commit succeeded. Red or still running means wait.
2. Work out the version the draft will carry: `gh release list --limit 5`
   for the last tag, `git log <last-tag>..origin/main --oneline` for what
   has landed since, and `docs/ReleaseProcess.md` for which commit types
   bump what. If that is not the version wanted, stop — either CI already
   built the wanted one on `main`, in which case pass it as `version` below,
   or the fix is a commit (`+semver:` in a body, or `next-version` in
   `GitVersion.yml`), and CI has to build it before a release can carry it.
3. If that version is already tagged, stop. It has been published, and the
   workflow refuses to replace it.

## Draft

`gh workflow run draft-release.yml --ref main` — the same as `Actions` →
`Draft Release` → `Run workflow` → `main` in the web UI. Find the run with
`gh run list --workflow draft-release.yml --limit 1` and `gh run watch` it.

To ship an earlier `main` build than the tip, add `-f version=<x.y.z>`; the
workflow finds the CI run that built it, and refuses if that build's
artifact is gone — nothing is rebuilt.

Re-running replaces the draft for that version rather than adding a second,
so a failed or wrong attempt costs nothing.

If the notes open with an HTML comment instead of a paragraph, the summary
model was unavailable — `COPILOT_PAT` missing or expired, or the service
down. The draft is still good: write the paragraph by hand at review, or
delete the draft and re-run later.

## Review

`gh release list` shows the draft; `gh release view <tag>` shows its body
and assets. Report each of these and wait for the human to confirm them:

- the version is the one worked out above;
- the CI artifacts are attached;
- the notes read correctly, and every breaking change is explained.

If anything is wrong, `gh release delete <tag>` removes the draft. Nothing
else has happened.

## Publish

Publishing is the deployment. It creates the tag, which is what the next
version is calculated from, and fires the repo's `publish-release.yml` if it
has one. It cannot be undone: the tag is protected by ruleset and
the published assets are immutable.

Never publish without explicit confirmation in this conversation. Then
`gh release edit <tag> --draft=false`, and report the release URL.
