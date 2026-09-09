# Conventional Commits

This repo uses [Conventional Commits][cc]
to standardize the format of commit messages.
This enables the automation of versioning
and the generation of changelogs and release notes.

Because versioning is automated, the type you choose has a consequence:
it decides which part of the version number the commit bumps.
The [Release Process][releaseFile] documents that mapping,
and the escape hatch for overriding it.

We follow the standard commit types (feat, fix, docs, style, refactor, etc.)
and additionally use a custom `infra` type for infrastructure changes
such as GitHub settings, Terraform configurations,
and other DevOps-related changes.

## Basic Structure

[Visit the website][cc] for more details about the format;
but essentially, commit messages should follow this pattern:

```text
type[(scope)][!]: description

[body]

[footer(s)]
```

The `type` and `description` are the only two required components;
but here's a quick explanation of all of them:

- `type` - _(Required)_ One of the following values:
  - `build` - A change that affects the build system or external dependencies
  - `chore` - A routine task, maintenance, etc.,
    that doesn't change production code
  - `ci` - A change to CI configuration files or scripts
  - `docs` - A documentation-only change
  - `feat` - A new feature for the user or a significant enhancement
  - `fix` - A bug fix
  - `infra` - A change to infrastructure code
    (Terraform, GitHub settings, DevOps, etc.)
  - `perf` - A code change that improves performance
  - `refactor` - A code change that neither fixes a bug nor adds a feature
  - `revert` - Reverts a previous commit
  - `style` - A change that does not affect code behavior (formatting, spacing)
  - `test` - Adding or correcting tests
- `(scope)` - _(Optional)_ In parentheses,
  indicates the section of the codebase affected (e.g., `ui`, `api`, `auth`)
- `!` - _(Optional)_ Indicates a breaking change
  (alternative to using `BREAKING CHANGE:` in the footer)
- `description` - _(Required)_ A concise, single-line description of the changes
  in imperative, present tense (use "change," not "changed," "changes," or "changing")
- `body` - _(Optional)_ Provides additional contextual information about the changes,
  explaining motivation, reasoning, or notable implementation details
- `footer(s)` - _(Optional)_ References to issues, PRs, or other metadata
  - `BREAKING CHANGE:` - Special footer indicating a breaking change,
    with a description of the change and migration notes

## Commit Message Template

To facilitate all this, a default Git message template
([.gitmessage][messageFile]) is included in the project.
You can activate it by running the following command from the repo root:

```bash
git config commit.template .gitmessage
```

Afterward, whenever you run `git commit` (without the `-m` switch),
the template should be displayed in your configured text editor.
Other Git tooling should pick it up as well.
Simply replace the template with your formatted commit message and save it.

## Additional Information

If you're new to or unfamiliar with [Conventional Commits][cc],
there are several good cheat sheets out there
that can help you get familiar with it:

- [Dash][kapeli]
- [Bengt Brodersen][qoomon]
- [Yaroslav Vorobev][zekfad]

<!-- Source Code URIs (folders first, then files; each alphabetical) -->

[releaseFile]: ./ReleaseProcess.md
[messageFile]: ../.gitmessage

<!-- GitHub URIs (alphabetical) -->

[qoomon]: https://gist.github.com/qoomon/5dfcdf8eec66a051ecd85625518cfd13
[zekfad]: https://gist.github.com/Zekfad/f51cb06ac76e2457f11c80ed705c95a3

<!-- Public URIs (alphabetical) -->

[cc]: https://www.conventionalcommits.org
[kapeli]: https://kapeli.com/cheat_sheets/Conventional_Commits.docset/Contents/Resources/Documents/index
