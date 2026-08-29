# .actions <!-- omit from toc -->

Reusable GitHub Actions and workflows shared across all TaffarelJr repos.

Every repo used to carry its own copy of this machinery,
inherited through the template chain.
Keeping it here instead means one copy to fix,
and it lets a leaf repo delete `scripts/` entirely
while still being able to version and release itself.

#### Table of Contents <!-- omit from toc -->

- [Getting Started](#getting-started)
  - [version](#version)
  - [changelog](#changelog)
  - [release-artifacts](#release-artifacts)
  - [template-sync](#template-sync)
  - [validate-codecov](#validate-codecov)
- [Versioning](#versioning)
- [Contributing](#contributing)
- [Support](#support)
- [License](#license)

## Getting Started

Reference an action by its folder, pinned to a major version:

```yaml
- uses: TaffarelJr/.actions/version@v1
```

Each one is a composite action, so it runs inside the calling job
rather than costing a whole extra runner.

### version

Calculates the SemVer version for the current commit,
using [GitVersion][gitVersion] and the repo's own `GitVersion.yml`.
It reads git history only, so it is not specific to any language.

```yaml
- uses: actions/checkout@v7
  with:
    fetch-depth: 0 # GitVersion needs all the history and tags

- id: version
  uses: TaffarelJr/.actions/version@v1

- run: echo "Building ${{ steps.version.outputs.semVer }}"
```

Most outputs forward GitVersion's own. The exception is `tag`,
which encodes the tag convention — `v` plus the version —
so no workflow has to build that string itself
and none of them can disagree about it.

Set `summary: false` where the version is only a fallback,
so the job summary does not announce a number that was not used.

### changelog

Builds release notes and a changelog from the git history,
covering everything since the last version tag.

```yaml
- uses: TaffarelJr/.actions/changelog@v1
  with:
    version: ${{ steps.version.outputs.semVer }}
```

The notes lead with a prose summary and fold the full commit list
beneath it. Pass `summary-path` to supply that prose;
without it a placeholder HTML comment is written instead,
which stays invisible if the release is published unfilled.

The script and its module travel with the action,
so the calling repo needs nothing of its own.

### release-artifacts

Finds the CI run that built this exact commit and downloads its artifacts,
so a release ships bit-for-bit what was tested instead of rebuilding.

```yaml
- id: artifacts
  uses: TaffarelJr/.actions/release-artifacts@v1

- if: steps.artifacts.outputs.found == 'true'
  run: echo "Shipping ${{ steps.artifacts.outputs.version }}"
```

Nothing here fails the caller.
A missing run, an expired artifact or a missing `version.txt`
all report through the outputs,
because a release workflow wants to decide for itself
whether to fall back or stop.

### template-sync

Opens a pull request bringing a parent template's changes down.

```yaml
- uses: actions/checkout@v7
  with:
    fetch-depth: 0
    token: ${{ secrets.TEMPLATE_SYNC_PAT }}

- uses: TaffarelJr/.actions/template-sync@v1
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

### validate-codecov

Checks a `codecov.yml` against Codecov's own validator.

```yaml
- uses: actions/checkout@v7
  with:
    fetch-depth: 1

- uses: TaffarelJr/.actions/validate-codecov@v1
```

Codecov silently falls back to its defaults when the file does not parse,
so a typo fails nothing —
it just quietly stops enforcing the thresholds.
This turns that into a failed check,
and puts the validator's own reason in the log
so it says *what* is wrong rather than only *that* something is.

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

<!-- Public URIs (alphabetical by name) -->

[gitVersion]: https://gitversion.net/docs
