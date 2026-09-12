---
name: dotfile-templates
description: >-
  Refreshes .gitattributes and .gitignore from their upstream template
  repositories while preserving local customizations, and adds a new template
  section. Use when asked to update either file, pull the latest templates,
  check whether they are current, or add support for a language or tool.
when_to_use: >-
  Trigger phrases: update .gitattributes, update .gitignore, refresh the
  templates, latest from upstream, add a gitignore section, are our dotfiles
  current, which templates are we missing.
allowed-tools: Read Edit Write Grep Glob Bash
---

`.gitattributes` and `.gitignore` are both assembled from **near-verbatim
upstream templates**, each under a section header naming the tool and the URL
it came from.

The value of that convention is that a refresh is a diff against a known
source rather than an argument about line endings or build output. Preserve it.

| File             | Upstream                              | Ordering                        |
| ---------------- | ------------------------------------- | ------------------------------- |
| `.gitattributes` | [gitattributes/gitattributes][ga]     | `Common` first, then alphabetical |
| `.gitignore`     | [github/gitignore][gi]                | alphabetical throughout          |

`.gitattributes` has a `Common` template that owns the defaults, so it leads.
`.gitignore` has no equivalent, so every section is simply alphabetical.

## The shape

```
#───────────────────────────────────────────────────────────────────────────────
# Visual Studio
# https://github.com/github/gitignore/blob/main/VisualStudio.gitignore
#───────────────────────────────────────────────────────────────────────────────

<template body, near-verbatim>
```

The header URL is the refresh contract. Never add a section without one.

## Superseded sections

When an upstream template is entirely covered by a broader one already
present, keep the **header** and replace the body with a marker:

```
#───────────────────────────────────────────────────────────────────────────────
# Dotnet
# https://github.com/github/gitignore/blob/main/Dotnet.gitignore
#───────────────────────────────────────────────────────────────────────────────

# Superseded by Visual Studio
```

This records a decision that would otherwise look like an oversight — it
answers "did you consider this one?" without duplicating its contents. Use it
for every template deliberately left out on those grounds, not just some.

Name the superseding section; do not write "(below)". Position is implied by
alphabetical order and a positional reference goes stale.

## Refreshing from upstream

1. **Fetch the raw templates**, one per local section, plus any candidates.
   Use the raw URL so the bytes are exact:
   `https://raw.githubusercontent.com/<owner>/<repo>/<branch>/<path>`
2. **Diff each against its local section**, sorting every difference into one
   of these before changing anything:

| Difference                             | Do this                                    |
| -------------------------------------- | ------------------------------------------ |
| Upstream added something new           | Import it, unless it overlaps (see below)   |
| Upstream declares `* text=auto`        | Drop it — `Common` owns that line           |
| Local has a line upstream lacks        | Keep it. It is a deliberate customization   |
| Both changed the same line             | Resolve, and say which way and why          |
| Upstream body now fits another section | Move it, and mark the source superseded     |

3. **Report before writing.** List what changed upstream, what was kept
   local, and every overlap resolved. A silent refresh is how a customization
   gets lost.

## Overlaps

Templates genuinely overlap. A pattern belongs to **exactly one** section: the
one that most obviously owns it.

- The section named after the thing wins: `*.md` to `Markdown`, `*.ps1` to
  `PowerShell`, `*.sln` to `Visual Studio`.
- Except **breadth beats specificity** in `.gitattributes`: `Common` owns
  graphics, archives and documents even when another template lists more of
  them. Move the extras up rather than keeping two lists.
- A pattern appearing in two local sections is a bug. Find which section owns
  it and delete the other.

Obvious resolutions: do them, and note them. **Genuinely subjective ones: stop
and ask.**

## Adding a section

**Always confirm before importing a new template.** Which ones apply is not
inferable from the code — some are for work that has not started yet. Propose
and wait.

Two things worth raising unprompted:

- A template that **directly matches code already in the repo** and is missing.
- A template whose content is already fully covered, which should be recorded
  as superseded rather than silently skipped.

## Per-layer split

Both files are appended to at every template layer, so a section belongs at
the **highest layer where it is still true**:

| Section                                   | Belongs at         |
| ----------------------------------------- | ------------------ |
| OS, editors, agents, backups, VCS noise   | `.github`          |
| `C#`, `Visual Studio`, `Dotnet*`          | `.template-dotnet` |
| `Web`, `Node`                             | a web template     |

A generic improvement made in a lower layer should be **promoted up**, or
every future sibling has to rediscover it. Check for divergence: below
`.github`, each layer's file should be its parent's content plus its own
sections, never a different version of a shared one.

## Deliberate local deviations

Do not "fix" these back to upstream:

- `.gitattributes` `Common` drops upstream's `*.md`, `*.mdx` and `*.ps1` —
  those sections own them.
- `.gitattributes` `Markdown` is deliberately **richer** than upstream, which
  has shrunk to a single line.
- Upstream's commented-out `merge=binary` block in `Visual Studio`, and its
  long explanatory comments, are intentionally omitted.
- `*.slnx` sits in `Visual Studio` with the other project files, even though
  upstream ships it in `CSharp`.
- The `Visual Studio` **gitignore** template carries entries belonging to
  other tools; those have been moved to the sections that own them.
- The two `macOS` gitignore entries containing a **literal carriage return**
  inside a bracket expression — `Icon[<CR>]` and
  `.HFS+ Private Directory Data[<CR>]` — are deliberately absent. They caused
  problems in practice and were removed. Do not re-import them.
- `*.code-workspace` is ignored, even though upstream now un-ignores it with
  `!*.code-workspace`.
- Local `x64/` and `x86/` broad ignores are kept in preference to upstream's
  narrower `[Dd]ebug/x64/` per-configuration list.

## Afterwards

- Line endings stay whatever `.editorconfig` gives these files; an upstream
  import must not flip them.
- A `.gitattributes` change alters how git normalizes everything, so confirm
  it changes nothing already tracked: `git add --renormalize .` should stage
  zero files, then `git reset`.
- A `.gitignore` change can start ignoring something already tracked, which
  git will not tell you. Check with `git ls-files -i -c --exclude-standard`;
  it should print nothing.
- Fit the change into the existing commit that owns the file rather than
  stacking a new one, per this repo's history convention.

<!-- GitHub URIs (alphabetical) -->

[ga]: https://github.com/gitattributes/gitattributes
[gi]: https://github.com/github/gitignore
