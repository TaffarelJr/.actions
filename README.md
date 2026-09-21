# Custom GitHub Actions Repository <!-- omit from toc -->

Reusable GitHub Actions and workflows shared across all TaffarelJr repos.

#### Table of Contents <!-- omit from toc -->

- [Getting Started](#getting-started)
  - [changelog/build](#changelogbuild)
  - [codecov/upload](#codecovupload)
  - [codecov/validate](#codecovvalidate)
  - [powershell/restore](#powershellrestore)
  - [powershell/test](#powershelltest)
  - [release/draft](#releasedraft)
  - [release/fetch-artifacts](#releasefetch-artifacts)
  - [template/sync](#templatesync)
  - [version/calculate](#versioncalculate)
  - [version/move-aliases](#versionmove-aliases)
- [Versioning](#versioning)
- [Contributing](#contributing)
- [Support](#support)
- [License](#license)

## Getting Started

Reference an action by its folder, pinned to a major version:

```yaml
- uses: TaffarelJr/.actions/version/calculate@v1
```

Each one is a composite action, so it runs inside the calling job
rather than costing a whole extra runner.

`build-workflow` and `artifact-name` both default to `Continuous Integration`
and `packages` — the convention every repo's own CI is expected to follow so
`release/draft` and `release/fetch-artifacts` need no configuration to find
what it built. Override both together if a repo names either differently;
`release/draft` only relays them to `release/fetch-artifacts`, it does not
invent its own defaults.

### changelog/build

Builds release notes and a changelog from the git history,
covering everything since the last version tag.

```yaml
- uses: TaffarelJr/.actions/changelog/build@v1
  with:
    version: ${{ steps.version.outputs.semVer }}
```

The notes lead with a prose summary and fold the full commit list
beneath it. Pass `summary-path` to supply that prose;
without it a placeholder HTML comment is written instead,
which stays invisible if the release is published unfilled.

The script and its module travel with the action,
so the calling repo needs nothing of its own.

`from-tag` rebuilds the notes for an earlier release instead of the most
recent one. `to-ref` and `repository` default to the current commit and
this repo; override them to build notes for somewhere else.

### codecov/upload

Uploads coverage reports found under a folder to Codecov.

```yaml
- uses: TaffarelJr/.actions/codecov/upload@v1
  with:
    token: ${{ secrets.CODECOV_TOKEN }}
```

Installs `codecovcli` itself — a plain binary, not another action — because
that is the only way to make a variable number of differently-flagged
uploads from one composite action: `codecov-action`'s own `flags` input is
one tag-set per invocation, and a composite action's steps are fixed at
authoring time, so neither can loop over a folder discovered at runtime.

Every matching report under `path` uploads together, unflagged, by default.
Pass `group-by-subfolder: true` to upload each immediate subfolder as its
own flagged upload instead — one flag per build target (a .NET TFM, for
example), however many exist, with any loose files outside a subfolder
still going up unflagged. Whether to split at all is a caller's choice, not
something guessed from folder structure, since a nested layout can mean
either "these are separate build targets" or just "this is how the files
happened to be organized."

### codecov/validate

Checks a `codecov.yml` against Codecov's own validator.

```yaml
- uses: actions/checkout@v7
  with:
    fetch-depth: 1

- uses: TaffarelJr/.actions/codecov/validate@v1
```

Codecov silently falls back to its defaults when the file does not parse,
so a typo fails nothing —
it just quietly stops enforcing the thresholds.
This turns that into a failed check,
and puts the validator's own reason in the log
so it says *what* is wrong rather than only *that* something is.

### powershell/restore

Installs the PowerShell modules the other `powershell/` actions need — today
that is Pester, which `powershell/test` uses to measure coverage.

```yaml
- uses: TaffarelJr/.actions/powershell/restore@v1
```

Run it before `powershell/test`. Anything already installed is left alone.
The list is `powershell/RequiredModules.psd1`, and a script that needs one of
those modules checks first: on a developer's machine it offers to install a
missing one, and in a workflow it fails naming this action and the command,
so the fix is the same either way.

### powershell/test

Runs every `*.Tests.ps1` under `test/`, each in its own PowerShell process,
and measures line coverage of every other `*.ps1` and `*.psm1` in the repo.

```yaml
- uses: TaffarelJr/.actions/powershell/restore@v1
- uses: TaffarelJr/.actions/powershell/test@v1
```

A test mirrors the path of the file it exercises —
`changelog/build/New-Changelog-Tasks.psm1` is tested by
`test/changelog/build/New-Changelog-Tasks.Tests.ps1` — and imports it with
`Import-SourceModule`, so the two move together. A file worth splitting
becomes `<Name>.<Aspect>.Tests.ps1` files, which sort together.

Each test file writes a Cobertura report at the same relative path under
`test/coverage/` (`output-path`); Codecov merges them, so nothing has to be
combined here. Coverage is always measured, which is why `powershell/restore`
has to run first. Pass `path` to search another folder, or `show-output: true`
to see every file's output rather than only a failing file's.

### release/draft

Finds the CI run for this exact commit, drafts a GitHub Release from
it, and attaches whatever that run built.

```yaml
- uses: actions/checkout@v7
  with:
    fetch-depth: 0 # the changelog needs all the history and tags

- uses: TaffarelJr/.actions/release/draft@v1
  env:
    GH_TOKEN: ${{ github.token }} # for the AI summary - see below
```

The release is always a draft: nothing is public until a human opens
it and presses Publish. The AI summary needs both `copilot-requests: write`
in the job's `permissions:` and `GH_TOKEN` passed at this level, exactly as
shown - an env var set any deeper (inside `release/draft` itself, or
anywhere below it) does not reliably reach the Copilot CLI, a composite
action several layers down. Without either one (or if the account has no
Copilot entitlement) the notes keep a placeholder instead of a generated
summary, same as any other outage.

By default the draft is for the commit the workflow runs from.
Pass `version` to release an earlier build instead:
the CI run that produced it is found by the version it recorded,
so its artifact must still exist, and there is no fallback.
It must also be newer than the last release,
since the notes run from that tag to the commit that built it.

### release/fetch-artifacts

Finds the CI run that built this exact commit and downloads its artifacts,
so a release ships bit-for-bit what was tested instead of rebuilding.

```yaml
- id: artifacts
  uses: TaffarelJr/.actions/release/fetch-artifacts@v1

- if: steps.artifacts.outputs.found == 'true'
  run: echo "Shipping ${{ steps.artifacts.outputs.version }}"
```

Nothing here fails the caller.
A missing run, an expired artifact or a missing `version.txt`
all report through the outputs,
because a release workflow wants to decide for itself
whether to fall back or stop.

Pass `version` to find the run that built a particular version instead.
The recent successful runs are searched newest first, `search-depth` deep,
reading each artifact's `version.txt`; `sha` reports which commit the match
was built from. The search runs against the branch that triggered the
workflow, or the repo's default branch when triggered from a tag or a
pull request, since neither of those ever has a build of its own.

### template/sync

Opens a pull request bringing a parent template's changes down.

```yaml
- uses: actions/checkout@v7
  with:
    fetch-depth: 0
    token: ${{ secrets.TEMPLATE_SYNC_PAT }}

- uses: TaffarelJr/.actions/template/sync@v1
  with:
    template-url: https://github.com/TaffarelJr/.github.git
    strategy: rebase
    token: ${{ secrets.TEMPLATE_SYNC_PAT }}
```

`strategy` is `rebase` for a template layer,
which replays the parent's commits so history stays linear
and no merge commit of ours can reach a leaf,
or `merge` for a leaf,
which is the end of the chain and so the only place a merge commit belongs.

The token matters: a pull request opened with the default `GITHUB_TOKEN`
cannot trigger workflows, so a required status check would never report
and the PR could never be merged.

### version/calculate

Calculates the SemVer version for the current commit,
using [GitVersion][gitVersion] and the repo's own `gitversion.yml`.
It reads git history only, so it is not specific to any language.

```yaml
- uses: actions/checkout@v7
  with:
    fetch-depth: 0 # GitVersion needs all the history and tags

- id: version
  uses: TaffarelJr/.actions/version/calculate@v1

- run: echo "Building ${{ steps.version.outputs.semVer }}"
```

Most outputs forward GitVersion's own. The exception is `tag`,
which encodes the tag convention — `v` plus the version —
so no workflow has to build that string itself
and none of them can disagree about it.

Set `write-to-job-summary: false` where the version is only a fallback,
so the job summary does not announce a number that was not used.

### version/move-aliases

Repoints the major and major.minor alias tags at a release,
so a consumer pinning `@v1` gets each new `v1.x.y` automatically.
See [Versioning](#versioning) for why these tags exist.

```yaml
- uses: TaffarelJr/.actions/version/move-aliases@v1
```

`tag` defaults to the tag of the release that triggered the workflow,
so a `release: published` trigger needs nothing else.
Pass it explicitly for a `workflow_dispatch` re-run, or to move the
aliases to some other tag by hand.

Each alias is recomputed from every release tag that exists, not just set
to whatever tag triggered the run — so publishing an out-of-order backport
can never move an alias backwards, and a previous bad move corrects itself
on the next publish.

## Versioning

Consumers pin a major version, so `v1` has to keep moving
while released versions stay fixed. Two kinds of tag do that:

- **`v1.2.3`** is a real GitHub Release — immutable, permanent,
  and what the changelog and any assets hang off.
- **`v1` and `v1.2`** are plain git tags that are never attached
  to a release, so they stay movable and can be re-pointed
  at each new release.

Immutability applies to release-backed tags,
which is why the moving ones are deliberately kept out of releases.
Publishing a release moves both automatically; nothing to do by hand.

Every tag here is `v` plus a bare version number, and several actions strip
or rebuild that prefix independently — `version/calculate`'s own `tag`
output, `release/draft`'s and `release/fetch-artifacts`'s `version` input,
and `version/move-aliases`'s `tag` input all start from a different kind of
string, so there is no single place to normalize it once. If the convention
itself ever changes, grep for `#v` across this repo's `action.yml` files
rather than assuming one of them owns it.

## Contributing

Contributions are welcome. Please read
[CONTRIBUTING.md][contribFile] first,
along with the [Code of Conduct][cocFile].

## Support

Need help? See [SUPPORT.md][supportFile].
To report a vulnerability, see [SECURITY.md][securityFile].

## License

[MIT][licenseFile]

<!-- Source Code URIs (folders first, then files; each alphabetical) -->

[cocFile]: ./CODE_OF_CONDUCT.md
[contribFile]: ./CONTRIBUTING.md
[licenseFile]: ./LICENSE
[securityFile]: ./SECURITY.md
[supportFile]: ./SUPPORT.md

<!-- Public URIs (alphabetical) -->

[gitVersion]: https://gitversion.net/docs
