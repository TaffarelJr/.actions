# Custom GitHub Actions Repository <!-- omit from toc -->

Reusable GitHub Actions and workflows shared across all TaffarelJr repos.

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

<<<<<<< HEAD
- id: version
  uses: TaffarelJr/.actions/version@v1
=======
Shared composite actions live in the separate
[TaffarelJr/.actions][actionsRepo] repo, not under `.github/` here — each
workflow below marked *via* is a thin trigger that calls one.
>>>>>>> template/main

- run: echo "Building ${{ steps.version.outputs.semVer }}"
```

<<<<<<< HEAD
Most outputs forward GitVersion's own. The exception is `tag`,
which encodes the tag convention — `v` plus the version —
so no workflow has to build that string itself
and none of them can disagree about it.
=======
| Workflow                                                                           | Description                                                                              |
| :---------------------------------------------------------------------------------- | :---------------------------------------------------------------------------------------- |
| 📁[.github/][githubFolder]                                                         |                                                                                           |
| &nbsp;└─📁[workflows/][workflowFolder]                                             |                                                                                           |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;├─📄[Continuous Integration][ciWorkflow] | Runs the [scaffolding scripts'][scriptsFile] tests on both platforms                     |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;├─📄[Draft Release][draftWorkflow]       | Entry point for [cutting a release][releaseFile], via [TaffarelJr/.actions][actionsRepo] |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;├─📄[Template Sync][syncWorkflow]        | Brings changes from a template repo, via [TaffarelJr/.actions][actionsRepo]              |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;└─📄[Validate Codecov][codecovWorkflow]  | Checks `codecov.yml` against Codecov's validator, via [TaffarelJr/.actions][actionsRepo] |
>>>>>>> template/main

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

<<<<<<< HEAD
=======
[claudeFolder]: ./.claude/
[claudeFile]: ./.claude/CLAUDE.md
[githubFolder]: ./.github/
[ghAgentsFolder]: ./.github/agents/
[instructionsFolder]: ./.github/instructions/
[issueFormsFolder]: ./.github/ISSUE_TEMPLATE/
[issueChooserFile]: ./.github/ISSUE_TEMPLATE/config.yml
[workflowFolder]: ./.github/workflows/
[ciWorkflow]: ./.github/workflows/continuous-integration.yml
[draftWorkflow]: ./.github/workflows/draft-release.yml
[syncWorkflow]: ./.github/workflows/template-sync.yml
[codecovWorkflow]: ./.github/workflows/validate-codecov.yml
[codeOwnFile]: ./.github/CODEOWNERS
[codecovFile]: ./.github/codecov.yml
[copilotFile]: ./.github/copilot-instructions.md
[dependabotFile]: ./.github/dependabot.yml
[fundingFile]: ./.github/FUNDING.yml
[prTemplateFile]: ./.github/pull_request_template.md
[settingsFile]: ./.github/settings.yml
[vsCodeFolder]: ./.vscode/
[docsFolder]: ./docs/
[aiFile]: ./docs/AiInstructions.md
[chainFile]: ./docs/TemplateChain.md
[releaseFile]: ./docs/ReleaseProcess.md
[styleguideFile]: ./docs/Styleguide.md
[styleguideFile-commit]: ./docs/Styleguide.md#commit-messages
[scriptsFolder]: ./scripts/
[scriptsFile]: ./scripts/README.md

[editorConfigFile]: ./.editorconfig
[gitAttributesFile]: ./.gitattributes
[gitIgnoreFile]: ./.gitignore
[gitMessageFile]: ./.gitmessage
[agentsFile]: ./AGENTS.md
>>>>>>> template/main
[cocFile]: ./CODE_OF_CONDUCT.md
[contribFile]: ./CONTRIBUTING.md
[licenseFile]: ./LICENSE
[securityFile]: ./SECURITY.md
[supportFile]: ./SUPPORT.md

<!-- Public URIs (alphabetical) -->

[gitVersion]: https://gitversion.net/docs
