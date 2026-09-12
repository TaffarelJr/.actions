# Instructions for Copilot

The rules are in [AGENTS.md][agentsFile], which Copilot reads directly.
This file exists only for surfaces that look for
`copilot-instructions.md` and nothing else.

Path-scoped rules are in [.github/instructions/][instructionsFolder]
and are applied automatically by their `applyTo` globs.

Reference material lives in [docs/][docsFolder].
See [docs/AiInstructions.md][aiFile] for how the pieces fit together.

<!-- Source Code URIs (folders first, then files; each alphabetical) -->

[instructionsFolder]: ./instructions/
[docsFolder]: ../docs/
[aiFile]: ../docs/AiInstructions.md
[agentsFile]: ../AGENTS.md
