---
name: doc-conventions
description: >-
  Writes and reviews README.md and the Markdown documents in docs/ to this
  repo's house style: timeless prose, footnote-style link definitions in
  ordered groups, en-US spelling, and external links in place of
  re-explained third-party material. Use when adding a document, editing
  one, or auditing them for accuracy and staleness.
when_to_use: >-
  Trigger phrases: write a doc, update the docs, update the README, review
  docs/, add a document, are the docs accurate, check the docs for
  staleness, fix the links in a doc.
allowed-tools: Read Edit Write Grep Glob Bash WebFetch
---

Documents in `docs/` explain the *reasoning* behind rules that are stated
elsewhere. Instruction files state rules; these explain them. Never restate a
rule here that an instruction file already owns, and never leave a rule only
here — non-agentic tools get instruction text injected and will never follow a
link.

README.md is not a `docs/` document — it introduces the project rather than
explaining a rule — but it follows the same formatting, language, and
timelessness conventions below.

## Write for a reader two years from now

The single most common defect in these documents is a true statement that
stopped being true. Prefer a sentence that cannot rot.

**Never write down:**

- A count of anything — "all five reviewers", "three lines", "the other two".
  Adding a sixth silently makes the sentence a lie.
- An inventory that lives in a folder — a table of the skills or agents that
  exist. Link the folder and let the reader look.
- Front matter, key names, or flags belonging to another file. Say a reviewer
  is "declared read-only in its front matter", not `disallowedTools: Write,
  Edit`.
- A list of which modules a script imports, or which files a workflow calls.
  Describe what the arrangement achieves.
- Speculation about what might be added later. It reads as a commitment and
  ages into a to-do list nobody owns.
- A number that is enforced somewhere else — a coverage target, a timeout, a
  version. Say the check reports it. Two copies of a threshold is one too many.
- Prices, plan names, or vendor tiers. They change and they date the document.
- What something used to be, or how it worked before a change. A reader
  compares the document only against what is true today; explain the
  current shape and why, not the history that led to it.

**Do write down:** the shape of the system, why it is shaped that way, what
breaks if you do it differently, and how to perform the task.

When something genuinely must be named — a secret, a variable, a workflow the
reader has to click — name it. The test is whether a reader could act without
it.

## Prefer someone else's explanation

If a passage re-explains a third-party tool, standard, or general practice,
replace it with a link and keep only this repo's stance.

Keep local: the type list that feeds a regex here, a threshold this repo
enforces, the reason *this* repo chose a thing. Link out: exception handling
guidance, security checklists, editor menu paths, anything with a vendor's
name on it.

**Verify every URL before committing it.** Fetch it. Vendor documentation URLs
move constantly, and a plausible-looking path is often a 404. If a URL cannot
be confirmed, describe the destination in prose instead of guessing — "check
your editor's documentation for the exact name" beats a dead link.

## Structure

```markdown
# Title <!-- omit from toc -->

One or two sentences on what this document answers.

#### Table of Contents <!-- omit from toc -->

- [First Section](#first-section)
```

- `####` for the table of contents heading is deliberate: it does not deserve
  h2 sizing. Markdownlint is not run here, so its heading-increment rule does
  not apply.
- The document title and the ToC itself are both excluded from the ToC.
- A short document needs no ToC at all.
- Wrap at natural phrasing breaks. See below — this is the rule most often
  got wrong.
- Every fenced block declares a language. Use `text` for anything with no
  better answer.

## Line wrapping

Prose is hard-wrapped by hand, and where the break falls is deliberate.
Two rules, in this order:

1. **Break at punctuation or a phrase boundary** — a comma, a semicolon, a
   colon, an em dash, the end of a clause. Never mid-phrase, and never
   separating a preposition from what it governs.
2. **Then fill the line** — get as close to the target width as rule 1
   allows.

Rule 1 wins, so a line that ends well short of the target because the next
clause would not fit is correct. But do not break early when the phrase
*does* fit: `activities like side-by-side code comparisons,` is one unit and
belongs on one line, even though it runs right up to the target.

```markdown
- **100 characters** is OK once in a while,
  if it's more aesthetically pleasing than wrapping.
```

Not this — the break lands mid-phrase, splitting "pleasing than wrapping":

```markdown
- **100 characters** is OK once in a while, if it's more aesthetically pleasing
  than wrapping.
```

Keep parentheticals, link labels, and quoted phrases whole. Running past the
target is allowed occasionally when the alternative is an awkward break;
past the hard limit, never. `.editorconfig` draws both as vertical rulers,
and `docs/VerticalRulers.md` explains them.

Applying this to an edited paragraph means re-wrapping the whole paragraph,
not just the line you touched.

## Link definitions

Links are footnotes, not inline URLs. That keeps the prose readable, lets one
URL serve several mentions, and groups related destinations.

Groups appear in this order, each under its own comment, separated by a blank
line:

```markdown
<!-- Source Code URIs (folders first, then files; each alphabetical) -->

<!-- GitHub In-Repo URIs (alphabetical) -->

<!-- GitHub URIs (alphabetical) -->

<!-- Public URIs (alphabetical) -->
```

- **Source Code** — paths inside the repo. Sorted the way an editor's explorer
  shows a tree: at each level, folders before files, each alphabetical. So a
  file inside `docs/` precedes a file at the repo root.
- **GitHub In-Repo** — links to *this* repo's own GitHub-hosted pages: issues,
  discussions, wiki, security advisories. Scaffolding retargets these to the
  new repo when a derived repo is created, and they never change again -
  keep them separate from the next group for exactly that reason. A file
  inside `.github`'s own history that touches the general GitHub group would
  otherwise land its diff right next to a line every derived repo has
  permanently different, and a template sync conflicts on every such edit
  for no reason - confirmed live the first time a `.github` PR happened to
  touch that block.
- **GitHub** — every other `github.com` host: `docs.github.com`,
  `gist.github.com`, a different repo (same owner or not). Template-owned,
  so it syncs freely.
- **Public** — every other host, alphabetical by reference name.

Omit a group that would be empty. Use `./` for a sibling in the same folder,
not a bare filename.

## Language

- **en-US** throughout: behavior, honor, summarize, license as a noun.
- Sentence-case prose; the existing per-document heading style wins over any
  preference of yours.
- Functional emoji are welcome as scanning aids. Decorative ones are not.

## Reviewing

A documentation review is a fact-check, not a copy-edit. In order:

1. **Verify every claim against the code.** Counts, file names, key names,
   flags, thresholds. Read the file being described; do not trust the
   description. This finds the real defects.
2. **Check cross-document consistency.** If two documents state the same
   threshold, one of them is wrong now or will be.
3. **Check that every reference resolves** and that no definition is unused.
4. **Fetch external URLs.**
5. Only then, spelling and grammar.

Report findings before editing unless told otherwise, and separate *wrong* from
*stylistically different*. Say plainly when a claim you flagged turns out to be
correct — a false accusation costs the reader more than the nit was worth.
