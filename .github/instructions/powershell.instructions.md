---
applyTo: "**/*.{ps1,psm1,psd1}"
description: PowerShell conventions
---

# PowerShell

- Open every file with `#Requires -Version 7.0`.
  If comment-based help follows it, leave a **blank line** between them:
  help adjacent to another comment is ignored, which silently breaks `-?`.
  A plain header comment is not help — it carries no `.KEYWORD` — so it needs
  no blank line, which is why the modules open straight into one.
- Set `Set-StrictMode -Version Latest`
  and `$ErrorActionPreference = 'Stop'` in every module.
  Module scope does not inherit the caller's preference.
  Without the second line, a failing cmdlet is non-terminating,
  and the next `Write-Ok` reports a success that never happened.
- Name functions `Verb-Noun` using an approved verb (`Get-Verb`).
  Skip decorative prefixes; the noun should carry the meaning.
- Give every function comment-based help: `.SYNOPSIS` always,
  then `.DESCRIPTION` and `.PARAMETER` only where they add something.
  Add `.EXAMPLE` only where the call isn't obvious.
- Phrase `.SYNOPSIS` as a third-person verb phrase, matching what
  `Get-Help` shows for a built-in cmdlet: "Returns the...", "Writes the...".
  Never a bare noun phrase.
- **One command per statement.** Don't chain a pipeline across continuation
  lines: assign the first command's result to a variable, then filter or
  sort it in the next statement. Hoist a long argument array into a
  variable too. The formatter de-dents pipeline continuations, so a wrapped
  pipeline ends up looking like separate statements anyway.

  Exception: a single query - filter, project, or aggregate in one coherent
  pipeline, wrapped on its own `|` characters and assigned or returned as one
  expression - reads fine at two or three stages
  (`$strip = ($lines | ForEach-Object { ... } | Measure-Object -Minimum).Minimum`).
  The rule targets disguising several DIFFERENT operations as one statement,
  not a pipeline that genuinely is one.
- When a call is too long for one line, break at parameter boundaries and
  put each parameter on its own continuation line.
- Pass arguments to native commands as an explicit array —
  `& git @('-C', $path, 'status')`.
  Loose tokens such as `-C` bind as PowerShell parameters instead,
  silently and without an error.
- After deliberately tolerating a failed native command,
  reset `$global:LASTEXITCODE` so a later check doesn't see a phantom failure.
- **git writes progress and status to stderr even when it succeeds**, which
  PowerShell surfaces as an error and which aborts the rest of a compound
  command. Run git steps as separate statements, and judge them by
  `$LASTEXITCODE`.
- **`(?m)$` does not match before a CRLF line ending** - the `\r` is in the
  way. Prefer `[^\r\n]` and `[ \t]` over `.` and `\s`, and `\r?$` when an
  anchor is genuinely needed. A bare `.` matches `\r`, so a careless replace
  quietly converts the file to LF.
- **`Split-Path -Parent` returns a backslash path.** Normalize it with
  `-replace '\\', '/'` before joining it to a forward-slash relative path,
  or `..` resolution eats the whole prefix instead of one segment.
- Section breaks are three lines — a rule, the title, a rule —
  followed by a blank line.
- Use `-LiteralPath` for a filesystem cmdlet call on a variable path, never
  `-Path` — a path containing a wildcard character shouldn't be treated as one.
- Prefer `[Parameter(Mandatory)]` over `[ValidateNotNullOrEmpty()]` for a
  required parameter; Mandatory already rejects `$null` and an empty string.
  Add `[ValidatePattern('\S')]` only to also reject whitespace, and
  `[AllowEmptyString()]` only when blank is itself a legitimate value.
- There is no `Write-Error` helper. A failure is a `throw`, rendered once by
  the caller's own failure-reporting function.
- When a function must always return an array, even one element, even empty,
  return it with a leading comma (`return , $result`). A caller of such a
  function must never wrap the call in `@()` — that nests the array instead
  of leaving it flat.

## Scaffolding scripts

If this repo has a `scripts/New-Repo.ps1`,
read `scripts/README.md` before touching anything in there.
Everything in `scripts/` except a layer's own `New-Repo-<NN>-<slug>.psm1`
(and its test file) is inherited verbatim by every layer
and must stay byte-identical across them;
layer-specific behavior belongs in an additive `New-Repo-<NN>-<slug>.psm1`.

- Every module has a `scripts/tests/<Module>.Tests.ps1`, on the
  `TestKit.psm1` harness. A new module gets one; a changed one keeps its
  tests true. Write each case as Arrange / Act / Assert, marked as such.
- Run `scripts/tests/Run-Tests.ps1` before opening a pull request.
  CI runs it on Ubuntu and Windows for anything under `scripts/`.
- Say what a step is about to do with `Write-Doing`, and how it went with
  `Write-Done` (or `Write-Done -Skip`). Several outcomes in one step get
  `Write-Doing` once, then `Write-Ok` or `Write-Skip` per outcome.
