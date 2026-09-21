---
applyTo: "**/*.{yml,yaml}"
description: YAML, GitHub Actions, and settings.yml conventions
---

# YAML

- Quote a value only when it needs it.
- When a value is quoted, use `'` rather than `"`, except where `"` is
  required (a value containing `'` itself, or an escape sequence). VS Code
  enforces this on save via `yaml.format.singleQuote` in
  [.vscode/settings.json][vscodeSettingsFile].
- Put the schema comment on the first line where one exists,
  so editors validate the file:
  `# yaml-language-server: $schema=https://json.schemastore.org/...`
- Comment anything non-obvious —
  what a cron expression means, why a version is pinned —
  and link the source when there is one.

## GitHub Actions

- Declare `permissions:` on every job, granting the least it needs,
  with a trailing comment explaining why each one is there.
- Pin third-party actions to at least a major version tag
  (`uses: owner/action@v8`).
- Name every job and step. The name is what a reader sees in a failed run.
- Keep `env:` at the top of the workflow, for the values someone is most
  likely to want to change — except a value that reads a secret, which must
  be declared at the job level instead, since secrets aren't in scope in a
  workflow-level `env:`.
- Prefer a shared action or reusable workflow over copying steps into
  another repo: a whole job becomes a reusable workflow
  (`on: workflow_call`), a set of steps becomes a composite action.
- Thread a computed `${{ }}` value through a step's own `env:` rather than
  interpolating it directly into `run:`. GitHub's own
  [security hardening guide][securityHardeningDocs] names this as the
  mitigation for script injection via untrusted input; applying it to every
  non-literal value, not only ones a value's own source is known to be
  safe, means never having to judge case by case which values are safe to
  skip it for.

## settings.yml

[.github/settings.yml][settingsFile] is applied by the [Settings app][ghSettings],
and resolves `_extends` **recursively**,
so it inherits the whole template chain.
Declare only what differs from the immediate parent.

<!-- Source Code URIs (folders first, then files; each alphabetical) -->

[settingsFile]: ../settings.yml
[vscodeSettingsFile]: ../../.vscode/settings.json

<!-- Public URIs (alphabetical) -->

[ghSettings]: https://github.com/repository-settings/app
[securityHardeningDocs]: https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions
