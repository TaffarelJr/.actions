# Template Chain <!-- omit from toc -->

This document describes how my personal template repos are related,
how a change travels between them, and who owns which file when the two disagree.

#### Table of Contents <!-- omit from toc -->

- [The shape](#the-shape)
- [Why merge and not a template](#why-merge-and-not-a-template)
  - [The evidence](#the-evidence)
- [How a change travels down](#how-a-change-travels-down)
  - [Rebase down the templates, merge at the leaf](#rebase-down-the-templates-merge-at-the-leaf)
  - [The sync branch keeps itself current](#the-sync-branch-keeps-itself-current)
- [Who owns which file](#who-owns-which-file)
  - [Verbatim](#verbatim)
  - [Additive by file](#additive-by-file)
  - [Additive by section](#additive-by-section)
  - [Edit in place](#edit-in-place)
  - [Owned locally](#owned-locally)
- [Settings inheritance](#settings-inheritance)
- [Re-parenting](#re-parenting)

## The shape

`.github` is the base repo.
Every other repo is derived from it, directly or through a template layer:

```text
.github                     the base: files every repo gets
 ├─ .template-dotnet        + everything a .NET repo needs
 │   └─ .template-nuget     + everything a published package needs
 │       └─ my-project      a leaf: real code
 └─ my-service              a leaf derived straight from the base
```

Each repo has a `template` remote pointing at its **immediate parent**,
and the [Template Sync][syncFile] workflow merges from it.
A leaf repo is a leaf because nothing is derived from it —
that's the only difference.

## Why merge and not a template

GitHub's own "Use this template" is a **one-shot copy**
with no ongoing relationship.
The whole point here is that a change made in `.github` keeps flowing downstream.
So scaffolding deliberately creates an *empty* repo
and populates it from the `template` remote instead.

That choice rules out the other obvious approach.
Render-based scaffolders — Copier, Cookiecutter, Yeoman, `dotnet new` —
expand placeholders into a fresh tree,
and combining one with `git merge template/main` does not work:
the child renders `name: {{ repo_name }}` to `name: my-service`,
and every later sync tries to put the placeholder **back**,
conflicting on those lines forever.
Git cannot tell that the render was intentional.

The two models are mutually exclusive.
Adopting a render tool would mean replacing Template Sync
with that tool's update command, not running both.

### The evidence

Reproduced in a scratch repo: a template file holding `name: {{ repo_name }}`,
rendered in the child to `name: my-service`,
conflicts on **every** later sync that touches those lines —
and the incoming side always tries to put the placeholder back:

```text
CONFLICT (content): Merge conflict in config.yml
<<<<<<< HEAD
name: my-service
=======
name: {{ repo_name }}          ← the template wants its placeholder back, every time
>>>>>>> template/main
```

|                              | Placeholders                                   | Propagation                                   | Per-repo values                    |
| :--------------------------- | :--------------------------------------------- | :-------------------------------------------- | :--------------------------------- |
| **Merge model** _(used here)_ | none — children get the template's files as-is | `git merge template/main` → PR                | the scaffolder writes them as commits |
| **Render model**             | yes, natural                                   | re-render + apply the diff (`copier update`)  | an answers file                    |

The render model avoids the conflict by never letting a placeholder reach the
child: it re-renders the *old* and *new* template with the same stored answers,
diffs those two renderings, and applies only that diff.
Verified to apply cleanly on the same scenario.

Two more roads not taken:

- **Terraform or Pulumi for repo settings.** The [Settings app][ghSettings]
  already owns them, and a second declarative system pointed at the same
  fields invites the two to overwrite each other — for a state-management
  burden that a handful of personal repos cannot justify. Worth revisiting
  only for a setting the app genuinely cannot express.
- **Switching wholesale to the render model** (Copier being the obvious
  candidate) is genuinely undecided. It became a live option once template
  repos no longer needed to be runnable. The deciding question is whether
  Copier supports **chained** templates — each layer independently
  updatable — which must be verified, not assumed. Flattening the chain into
  one parameterised template with feature flags is the other serious
  alternative. Settings inheritance is unaffected either way: the Settings
  app resolves `_extends` server-side, whatever templates the files.

## How a change travels down

1. Change lands in a parent's `main` branch.
2. Template Sync runs in each child repo — on a schedule, dispatched by hand, or
   automatically once at the end of scaffolding.
3. It builds a `template-sync` branch carrying the parent's new work
   and opens a PR titled *Merge changes from template repo*.
4. You review and merge it.

### Rebase down the templates, merge at the leaf

Step 3 does one of two things, and which one is a property of the repo:

- **A template repo layer rebases.** The parent's commits are replayed
  on top of this repo's `main`, so its history stays linear.
  That is the point: a template's merge commits must never reach a leaf,
  where they would be indistinguishable from the leaf's own merge commits.
- **A leaf repo merges.** Nothing is derived from a leaf,
  so its merge commits reach nobody else.
  Leaves are the only repos that have them.

That is also why template layers keep the linear-history ruleset
and allow only rebase merging,
while a leaf allows merge commits and switches that ruleset off.
Inheritance is additive, so a leaf can disable an inherited ruleset
but can never remove it — which is why the leaf's `settings.yml`
carries it, disabled, with a comment saying why.

A consequence worth understanding:
rebasing gives the parent's commits **new ids** on the way down.
So a child does not share commit ids with its parent for long,
and the question "which commits am I missing" would answer *all of them*.
Sync therefore compares by **patch**, not by commit id —
which is what actually converges,
and why applying the same change twice is a no-op rather than a duplicate.

### The sync branch keeps itself current

The sync branch and its PR are rebuilt whenever either side moves,
so an unmerged PR does not go stale:

- Nothing new on either side → the branch and PR are left exactly as they are.
- The parent gained more commits → they are added, still linear.
- This repo's `main` advanced → the branch is rebuilt on top of it.

Because rebuilding force-pushes the branch,
a conflict resolution pushed to it survives only while neither side moves.
Resolve and merge in one sitting.

Two more consequences:

- **It is one hop at a time.** For example, merging into `.template-dotnet`
  does not touch `.template-nuget`; that repo's own sync has to run next.
  A change reaches the bottom of a three-layer chain only after three merges.
- **A clean sync opens no PR.** A freshly scaffolded repo
  already carries every patch its parent has, so there is nothing to bring down.
  A PR appearing right after scaffolding means something diverged unexpectedly.

The `/template-sync` skill walks through reviewing and resolving one.

## Who owns which file

When a sync conflicts, this is the question to ask.
Getting it backwards is how a repo either loses its own customizations
or drifts from its template.

Every file follows one of these patterns,
and knowing which one decides the answer before the diff is even read.
The pattern is a property of the file's *shape*,
so a file usually announces which one it is.

| Pattern                 | What it means                                    | On conflict                                  |
| :---------------------- | :----------------------------------------------- | :------------------------------------------- |
| **Verbatim**            | Byte-identical at every layer                    | Take the template, always                    |
| **Additive by file**    | A layer adds whole new files, edits none         | Keep both; a conflict is a coincidence       |
| **Additive by section** | A layer contributes a block to an inherited file | Keep both blocks, in the file's own order    |
| **Edit in place**       | A layer must change specific keys                | Take the incoming shape, re-apply local keys |
| **Owned locally**       | A layer or leaf owns the file outright           | Keep the local copy                          |

### Verbatim

The shared machinery: the scaffolding scripts, the modules they share and
their tests, the version and release workflows, and the version configuration
itself. A per-layer edit to any of them conflicts on every future change,
forever.

A layer that needs different behavior does not edit these.
Layer-specific *scaffolding* goes in an additive module of its own.
Layer-specific *build* behavior goes in that layer's own CI workflow —
which is why the release workflow needs no per-layer variant: it builds nothing.

### Additive by file

Anything whose contribution is a whole file rather than an edit:
per-layer scaffolding modules and their tests, AI agents, skills,
per-file-type instructions.
A conflict here usually means both sides genuinely edited the same line,
so read both.

### Additive by section

Dotfiles assembled from named blocks.
Each layer contributes its own blocks and never rewrites what it inherited,
so a conflict resolves by keeping both.

Where a new block *goes* depends on the file,
and it matters — putting one in the wrong place makes every later sync conflict:

- Some of these files are **sorted**, usually alphabetically by section name.
  A new block is inserted into that ordering rather than appended,
  so a layer's additions can land in the middle of the file.
- Others are **appended**, each layer's block below the last.
  There the order is itself the record of which layer contributed what.

Which rule a file follows is recorded in the
[dotfile-templates skill][dotfileSkill], not in the file itself —
read that rather than trusting a memory of it.

### Edit in place

The awkward case: a format with no `include` or `extends` mechanism,
so it cannot be assembled from blocks and every layer edits one shared structure.

Ownership is then per *key* rather than per block —
the base owns thresholds and reporting,
a toolchain layer owns the paths it excludes,
and a layer with projects in it owns the per-project breakdown.
Resolve by taking the incoming structure and re-applying the local keys.

### Owned locally

- **Repo settings — this repo.** It declares only its own deltas;
  the rest is inherited through `_extends` at runtime, not through the file.
- **The CI workflow — this layer.** It is where a toolchain lives,
  so each layer that builds something owns its own.
- **The template sync and test workflows — the template.** Neither carries a
  per-repo value: which parent to sync from, and how, are repo variables,
  and the test runner discovers its own files.
  So both are identical at every layer, and cannot conflict.
- **The README — split.** A template owns its diagram highlight and its own
  file tables — each layer lists what it adds, since a template's included
  files rarely change, so a hand-maintained table stays accurate. The base
  owns the shared structure the tables sit inside.
  A leaf replaces the file outright,
  because a project README should describe the project, not the chain.
- **The license — this repo**, if it is private
  and carries an all-rights-reserved notice. Otherwise the template's.
- **Anything else — prefer the template**, and treat the conflict as a signal
  that this repo customized something it should not have.

## Settings inheritance

Each derived repo's `settings.yml` carries
`_extends: <the repo it was derived from>`,
so it only states what differs — description, homepage, topics, name,
and visibility when private.
The base repo (`.github`) has no parent and so no `_extends`;
its `settings.yml` is the one place everything is declared in full.

The [Settings app][ghSettings] resolves `_extends` **recursively**:
it follows each parent's own `_extends` until one has none.
So a repo derived from `.template-dotnet` also inherits everything
from `.github` through the chain. Nearest layer wins.

Things to know before editing a shared layer:

- **Editing a parent does _not_ re-sync its children.** The Settings app
  only runs when a push touches *that repo's own* `.github/settings.yml`.
  After changing a shared layer, each downstream repo
  needs its own `settings.yml` touched to pick the change up.
- Inheritance is **additive only** — a child cannot remove a label or ruleset
  an ancestor contributed. Keep shared layers minimal.
- Same-named rulesets merge, but their **inner** arrays
  (`rules`, `bypass_actors`, `conditions.ref_name.include`)
  concatenate without dedupe.
  Define each ruleset in exactly **one** layer,
  or give child rulesets distinct names.
- If a layer is **unreachable** — renamed, or private and not visible
  to the app's installation — the chain **truncates silently**.
  No error, just partially applied settings. Keep every layer accessible.
- Scaffolding emits a **bare** `_extends`, meaning the same owner.
  Don't hand-edit one to point at another owner:
  every hop resolves against *this* repo's owner rather than the parent's,
  so a cross-owner chain truncates unless every level spells out `owner/repo`.

## Re-parenting

Moving a repo to a different parent is two edits and a merge:

1. Repoint the `template` remote, and the `TEMPLATE_REPO_URL` repo variable,
   at the new parent.
2. Change `_extends` in [settings.yml][settingsFile] to match.
3. Run Template Sync and resolve the merge using the ownership list above.

Because propagation replays real commits rather than rendering placeholders,
git can tell which patches the repo already carries,
so a new parent that shares history with the old one converges cleanly.
Only genuinely new content conflicts.

<!-- Source Code URIs (folders first, then files; each alphabetical) -->

[dotfileSkill]: ../.claude/skills/dotfile-templates/SKILL.md
[syncFile]: ../.github/workflows/template-sync.yml
[settingsFile]: ../.github/settings.yml

<!-- GitHub URIs (alphabetical) -->

[ghSettings]: https://github.com/repository-settings/app
