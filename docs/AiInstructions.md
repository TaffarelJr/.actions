# AI Instructions <!-- omit from toc -->

One set of rules, several tools.
This document records which file each AI tool reads,
so a rule never has to be written twice.

It describes the arrangement, not the inventory.
For what currently exists, open the folders it links to.

#### Table of Contents <!-- omit from toc -->

- [Layout](#layout)
- [Why AGENTS.md is the canonical file](#why-agentsmd-is-the-canonical-file)
- [What belongs where](#what-belongs-where)
- [Instructions, skills, and agents](#instructions-skills-and-agents)
  - [Skills reach further](#skills-reach-further)
  - [Agents are for isolated, read-only work](#agents-are-for-isolated-read-only-work)
  - [Sizing a review](#sizing-a-review)
  - [Copilot parity](#copilot-parity)
  - [What deliberately isn't an agent](#what-deliberately-isnt-an-agent)
  - [Adding one](#adding-one)
- [Adding a file type](#adding-a-file-type)
- [Adding a tool](#adding-a-tool)
- [Known limits](#known-limits)

## Layout

| File                                            | Read by                                             | Contains                                         |
| :---------------------------------------------- | :-------------------------------------------------- | :----------------------------------------------- |
| 📄[AGENTS.md][agentsFile]                        | Copilot, Codex, Cursor, Zed, Jules, and most others | Every rule that always applies                   |
| 📄[.claude/CLAUDE.md][claudeFile]                | Claude Code                                         | An import of `AGENTS.md`, plus Claude-only notes |
| 📁[.github/instructions/][instructionsFolder]    | Copilot (all surfaces), agents that follow a link   | Rules scoped to one file type                    |
| 📄[.github/copilot-instructions.md][copilotFile] | Copilot                                             | A pointer, for surfaces that need one            |
| 📁[.claude/agents/][agentsFolder]                | Claude Code, VS Code Copilot                        | Specialist reviewers, read-only                  |
| 📁[.github/agents/][ghAgentsFolder]              | Copilot cloud agent, VS Code                        | Thin mirrors of the above                        |
| 📁[.claude/skills/][skillsFolder]                | Claude Code, all Copilot surfaces                   | Procedures, loaded only when used                |
| 📁[docs/][docsFolder]                            | Humans; agents on demand                            | The reasoning behind the rules                   |

Nothing is duplicated:
each rule is stated in exactly one of these files,
and everything else points at it.

## Why AGENTS.md is the canonical file

[AGENTS.md][agents] is the cross-tool convention,
and it is the only instruction file
that today's tools either read natively or can import:

- **GitHub Copilot** reads `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` directly,
  in addition to `copilot-instructions.md`.
- **Claude Code** reads only `CLAUDE.md`,
  but `CLAUDE.md` can `@`-import another file,
  and the import is expanded into context at session start.
  That is real transclusion, not a hint,
  so `CLAUDE.md` carries almost nothing of its own.
  It lives in `.claude/`, the other place Claude Code looks for it,
  which keeps the repo root clear and — since Copilot only reads a
  root `CLAUDE.md` — means Copilot sees `AGENTS.md` once, not twice.

Instruction files must **state** each rule, not merely link to it.
Agentic tools will follow a Markdown link to `docs/`,
but Copilot code review and inline completion won't:
they get the instruction text injected and nothing more.
So the rule goes in the instruction file
and the rationale goes in `docs/`.

## What belongs where

- A rule that applies to every file → [AGENTS.md][agentsFile].
- A rule that applies to one file type →
  [.github/instructions/][instructionsFolder].
- The explanation, the how-to, the links, the tables → [docs/][docsFolder].

## Instructions, skills, and agents

Instructions say *how to write code*.
Skills and agents say *how to do a job* —
and they are separate mechanisms with different reach.

### Skills reach further

A skill is a procedure in [.claude/skills/][skillsFolder],
invoked by name or chosen by the model from its description.
That one path is read by Claude Code **and** by every Copilot surface,
including code review,
which makes a skill the closest thing to a write-once artifact here.

Skills also load lazily: the body costs nothing until it runs.
That makes them the right home for anything
that has grown out of `AGENTS.md` into a sequence of steps.

A skill can opt out of automatic invocation
when it should only ever run on request.
Most are better left discoverable,
so the model can reach for one on its own.

### Agents are for isolated, read-only work

A subagent gets its own context window and returns a summary.
That pays off when the work is **self-contained, verbose, and parallel** —
which describes a review and very little else.

The reviewers in [.claude/agents/][agentsFolder] are split by *lens*,
one concern each, because a single reviewer asked to consider everything
reliably reports on whatever it happened to notice first.
Verification is deliberately separate from design review:
folded together, test quality is reviewed by nobody in particular,
which is how it quietly rots.

Every reviewer is declared read-only in its own front matter.
That restriction is the point:
a reviewer that can edit will quietly fix what it found
instead of telling you, and you lose the review.

### Sizing a review

Reviewing is scaled to the change, not run at full width every time:
a small diff is read inline with no subagents at all;
a larger one gets only the lenses the diff implicates;
everything runs before a pull request,
or when the change touches
authentication, crypto, input parsing, secrets,
workflow permissions, or a public API.
The skill states which reviewers ran and which were skipped,
so the depth is visible and can be corrected.

That matters because parallel subagents are expensive — see
[why nothing here is a developer or architect agent](#what-deliberately-isnt-an-agent)
for the figure. The cost is worth it for a release candidate
and ridiculous for a renamed variable.

### Copilot parity

Skills need nothing:
`.claude/skills/` is read by Claude Code **and** every Copilot surface.

Agents need a little.
`.claude/agents/` covers Claude Code and VS Code,
but the Copilot **cloud** agent reads only `.github/agents/`.
So each reviewer has a thin mirror there
whose body points back at the `.claude/` file as the single source of truth.
Only the description is duplicated,
because that field is the routing table and has to be inline.

Copilot has no deny-list, so the mirror simply lists no edit tool.
Neither side is airtight — a shell tool can write a file —
so the instruction to report rather than fix is the real guarantee;
the tool lists just remove the temptation.

Custom agents are **not** used by Copilot code review.
A check that has to run there belongs in a skill.

### What deliberately isn't an agent

Anthropic's own multi-agent write-up puts the cost
at roughly 15x the tokens of a chat,
and says the pattern suits "heavy parallelization"
while "most coding tasks lack sufficient parallelizable components".
Work where every participant needs the same context is called out as unsuitable.

So:

- **No developer agent.** The main conversation is the developer.
  A subagent starts with no history
  and would re-derive what you just established.
- **No architect agent.** Design needs back-and-forth,
  which is the one thing a subagent is bad at.
  It is a skill if it is anything.
- **No lead or orchestrator agent.**
  Claude Code's main loop already orchestrates.
  A lead agent adds a context boundary
  and becomes the single point of failure, for nothing.
  Orchestration is expressed as a skill instead.

The lever that actually controls delegation is each agent's description.
Vague ones are why parallel agents duplicate each other's work.

### Adding one

Both are additive per layer, like everything else here:
drop in a file, edit nothing inherited.

Anything that needs a language-specific command or rule
belongs to the layer that owns that language, not to this one.
A .NET layer is the place for a test runner or a coverage procedure;
a packaging layer is the place for anything about public API surface.
This base repo carries only what every repo has.

## Adding a file type

Add one file to [.github/instructions/][instructionsFolder],
named `<type>.instructions.md`, with an `applyTo` glob in its front matter:

```markdown
---
applyTo: "**/*.cs"
description: C# conventions
---
```

This is **additive**: a template layer contributes its own file
and never edits an inherited one, so template merges stay clean.
A .NET template adds one for C#; one with Terraform adds one for Terraform.
This base repo carries only the file types every repo has.

## Adding a tool

Most tools now read `AGENTS.md`, so there is nothing to do.
For one that doesn't, add a file it does read
whose entire content points at `AGENTS.md` —
for example a `GEMINI.md` for the Gemini CLI.
Never copy rules into it.

## Known limits

- **Front matter globs are Copilot's mechanism.**
  Claude Code's equivalent is `.claude/rules/*.md` with a `paths:` list,
  which VS Code Copilot also honors.
  Using it would mean a second small file per file type,
  so instead `AGENTS.md` tells agents
  to read the matching file in `.github/instructions/` themselves.
  Claude is good at this, but it is discretionary rather than automatic.
- **`applyTo` on github.com** applies to Copilot code review
  and the cloud agent. In the IDE it applies everywhere.
- **Instructions are context, not enforcement.**
  Anything that must happen every time
  belongs in a ruleset, a workflow, or a hook — not in a Markdown file.

<!-- Source Code URIs (folders first, then files; each alphabetical) -->

[agentsFolder]: ../.claude/agents/
[skillsFolder]: ../.claude/skills/
[claudeFile]: ../.claude/CLAUDE.md
[ghAgentsFolder]: ../.github/agents/
[instructionsFolder]: ../.github/instructions/
[copilotFile]: ../.github/copilot-instructions.md
[docsFolder]: ./
[agentsFile]: ../AGENTS.md

<!-- Public URIs (alphabetical) -->

[agents]: https://agents.md
