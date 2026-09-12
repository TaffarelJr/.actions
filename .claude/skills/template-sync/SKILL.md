---
name: template-sync
description: >-
  Reviews and resolves a Template Sync pull request - the automated merge that
  brings changes down from this repo's parent template. Use when a
  "Merge changes from template repo" PR appears, when one carries the
  "needs fix" label, or when asked why a sync is failing.
when_to_use: >-
  Trigger phrases: template sync PR, sync from the template, needs resolution,
  why did the template sync fail.
argument-hint: "[optional PR number]"
allowed-tools: Read Grep Glob Bash
---

Template Sync merges the parent template's `main` into a `template-sync`
branch and opens a PR. Read [docs/TemplateChain.md][chainFile] first — it has
the model and the full ownership list, and unlike `scripts/`, it is present in
leaf repos too.

## 1. Find out what it wants to change

`gh pr list --head template-sync` then `gh pr diff <n>`.

Say what the PR contains before touching it. Three shapes, and they need
different responses:

- **Nothing.** A clean sync opens no PR at all. A PR with an empty diff means
  something odd happened — investigate rather than merge.
- **Genuine upstream changes.** The parent improved something. This is the
  normal case.
- **Conflicts** — the PR carries the `needs fix` label. The workflow pushed
  the branch with conflict markers still in it.

## 2. Resolve conflicts by asking who owns the file

This is the whole judgement, and getting it backwards is how a repo loses its
own customizations or drifts from its template.

- **Everything under `scripts/` except a layer's own `New-Repo-<NN>-<slug>.psm1`
  and `tests/New-Repo-<NN>-<slug>.Tests.ps1` — the template, always.**
  These must stay byte-identical at every layer. If this repo edited one, that
  edit was the mistake; move it into a `New-Repo-<NN>-<slug>.psm1` instead.
- **`.github/settings.yml` — this repo.** It declares only its own deltas.
  The rest is inherited through `_extends` at runtime, not through the file.
- **`.github/workflows/template-sync.yml` — the template, always.** It carries
  no per-repo values: `TEMPLATE_REPO_URL` and `TEMPLATE_SYNC_STRATEGY` are
  repo variables, so it cannot legitimately differ from the parent's.
- **`.github/workflows/continuous-integration.yml` — the template in a
  template layer, the leaf in a leaf.** The test runner discovers its files,
  so a template layer's copy cannot legitimately differ from the parent's.
  A leaf has no `scripts/` — scaffolding deleted the template's workflow
  with them — so the one it carries is its own; keep it.
- **`README.md` — split.** This repo owns the diagram highlight and its own
  tables; the template owns the shared structure.
- **`LICENSE` — this repo**, if it is private and carries the proprietary
  notice. Otherwise the template.
- **`New-Repo-<NN>-<slug>.psm1` and its `.Tests.ps1`, `.claude/`, `docs/` —
  whichever side changed.** These are additive, so a conflict usually means
  both sides edited the same line. Read both before choosing.
- **Anything else — prefer the template**, and treat the conflict as a signal
  that this repo customized something it should not have.

Resolve locally: check out the branch, fix the markers, and verify before
pushing. Never resolve by taking one whole side blindly. The authoritative
version of this list is in [docs/TemplateChain.md][chainFile] — if the two
disagree, that one wins.

## 3. Verify before merging

- `git grep -n '<<<<<<<'` finds nothing.
- `scripts/tests/Run-Tests.ps1` passes, if this repo has a `scripts/` folder.
- The required checks pass on the branch.
- The result is still byte-identical to the parent for the files the table
  says the template owns. Diff them explicitly, leaving out only this layer's
  own module and its tests:
  `git diff template/main -- scripts ':(exclude)scripts/New-Repo-[0-9]*' ':(exclude)scripts/tests/New-Repo-[0-9]*'`
  should be empty.
- If the PR carried `needs fix`, remove it: `gh pr edit <n> --remove-label
  'needs fix'`. The workflow only clears it on its own next run, so a PR
  resolved by hand keeps a stale label otherwise.

## 4. Merge, then check the next layer

Merge the PR. If this repo is itself a template, its own descendants will not
see the change until *their* sync runs — so say which repos are now behind,
and offer to dispatch their syncs.

## If the workflow itself failed

Read the run: `gh run view <id> --log-failed`. The usual causes are a
`TEMPLATE_REPO_URL` variable that is unset or names the wrong repo
(`gh variable list` shows both it and `TEMPLATE_SYNC_STRATEGY`), a ruleset blocking
the push of the `template-sync` branch, or the parent having no `main`.

<!-- Source Code URIs (folders first, then files; each alphabetical) -->

[chainFile]: ../../../docs/TemplateChain.md
