# Contributing <!-- omit from toc -->

First off, thanks for taking the time to contribute! ❤️

All types of contributions are encouraged and valued.
See the [Table of Contents](#table-of-contents) below for different ways to help
and details about how to work in this project.
Please make sure to read the relevant sections before making your contribution,
as it'll make the experience a lot smoother.
We look forward to your help! 🎉

> And if you like the project but don't have time to contribute, that's fine.
> There are other easy ways to support it and show your appreciation,
> which we'd also be very happy about:
>
> - Star the project ⭐
> - Tweet about it
> - Refer to this project in _your_ project's readme
> - Mention this project at local meetups and tell your friends/colleagues

#### Table of Contents <!-- omit from toc -->

- [Code of Conduct](#code-of-conduct)
- [Style Guides](#style-guides)
- [I Have a Question](#i-have-a-question)
- [I Want To Contribute](#i-want-to-contribute)
  - [Reporting Bugs](#reporting-bugs)
    - [Before Submitting a Bug Report](#before-submitting-a-bug-report)
    - [How Do I Submit a Good Bug Report?](#how-do-i-submit-a-good-bug-report)
  - [Suggesting Enhancements](#suggesting-enhancements)
    - [Before Submitting an Enhancement](#before-submitting-an-enhancement)
    - [How Do I Submit a Good Enhancement Suggestion?](#how-do-i-submit-a-good-enhancement-suggestion)
- [Contributing Changes](#contributing-changes)
  - [Quick Code Review Rules](#quick-code-review-rules)
  - [Pull Request Ownership](#pull-request-ownership)
  - [Merging Pull Requests](#merging-pull-requests)
  - [Blocking Pull Request Merging](#blocking-pull-request-merging)
- [Your First Code Contribution](#your-first-code-contribution)
- [Attribution](#attribution)

## Code of Conduct

This project and everyone participating in it
is governed by the [Code of Conduct][cocFile].
By participating, you're expected to uphold this code.
Please report unacceptable behavior to the repo owners.

## Style Guides

This project follows a set of style guides to ensure code quality and consistency.
For detailed information, please refer to the [Styleguides][styleguideFile] document.
All contributors are expected to follow these guidelines when submitting code changes.

## I Have a Question

> If you want to ask a question,
> we assume you've read the available [Documentation][docsFolder]
> and searched the [Wiki][ghWiki] first.
> Searching the internet is also advisable.

All questions, comments, ideas, proposals, and feedback
are addressed using [Discussions][ghDiscussions].
Search for the topic you're looking for
or create a new one if necessary.
Provide as much context as you can,
along with project and platform versions depending on what seems relevant.
We'll respond as soon as possible.

## I Want To Contribute

> ### Legal Notice
>
> When contributing to this project,
> you must agree that you have authored 100% of the content,
> that you have the necessary rights to the content,
> and that the content you contribute may be provided under the project license.

### Reporting Bugs

#### Before Submitting a Bug Report

A good bug report shouldn't leave others
needing to chase you up for more information.
Therefore, we ask you to investigate carefully,
collect information and describe the issue in detail in your report.
Please complete the following steps in advance
to help us fix any potential bugs as fast as possible:

- Make sure you're using the latest version.
- Determine if your bug is really a bug and not an error on your side,
  e.g., using incompatible environment components/versions.
  Make sure you've searched the [Documentation][docsFolder] and [Wiki][ghWiki].
  If you're looking for support,
  you might want to check [this section](#i-have-a-question).
- To see if other users have experienced
  (and potentially already solved) the same issue,
  [check if there is already a bug report for your issue][ghIssues].
- Also make sure to search the internet (including [Stack Overflow][stackOverflow])
  to see if users outside the GitHub community have discussed the issue.
- Collect information about the bug:
  - Stack trace (Traceback)
  - OS, Platform, and Version (Windows, Linux, macOS, x86, ARM)
  - Version of the interpreter, compiler, SDK, runtime environment,
    package manager, etc., depending on what seems relevant
  - Possibly your input and the project's output
- Can you reliably reproduce the issue?
  And can you also reproduce it with older versions?

#### How Do I Submit a Good Bug Report?

> You must never report security-related issues, vulnerabilities,
> or bugs that include sensitive information
> to the issue tracker or elsewhere in public.
> Instead, see [SECURITY.md][securityFile]
> for more information on how to handle sensitive bugs.

We use [Issues][ghIssues] to track bugs, errors, and performance issues.
If you run into an issue with the project:

- Open a new [Bug Report][ghNewBug] or [Performance Issue][ghNewIssue].
- Use a **clear and descriptive title** for the issue to identify the problem.
  Since we can't be sure at this point whether it's a bug or not,
  we ask you not to talk about it being a "bug" yet
  and not to label the issue.
- **Describe the current behavior**
  and **explain which behavior you expected to see instead** and why.
  At this point you can also tell which alternatives did not work for you.
- Please **provide as much context as possible**
  and **describe the reproduction steps** that someone else can follow
  to recreate the issue on their own. This usually includes your code.
  For good bug reports, you should isolate the problem
  and create a reduced test case.
- You may want to **include screenshots and animated GIFs**
  which help you demonstrate the steps or point out the defect.
  It can be helpful to record the problem
  using tools like [LICEcap][licecap] (macOS/Windows)
  or [Silentcast][silentcast] (Linux).

Once it's filed:

- The project team will label the issue accordingly.
- A team member will try to reproduce the issue with your provided steps.
- If there are no reproduction steps or no obvious way to reproduce the issue,
  the team will ask you for those steps and mark the issue as `needs repro`.
  Bugs with the `needs repro` tag will not be addressed
  until they're able to be reproduced.
- If the team is able to reproduce the issue, it will be marked `needs fix`,
  as well as possibly other tags (such as `critical`),
  and the issue will be left to be
  [implemented by someone](#your-first-code-contribution).

### Suggesting Enhancements

This section guides you through submitting enhancement suggestions,
including **completely new features** and **improvements to existing functionality**.
Following these guidelines will help maintainers and the community
understand your suggestion and find related suggestions.

#### Before Submitting an Enhancement

- Make sure that you're using the latest version.
- Search the [Documentation][docsFolder] and [Wiki][ghWiki] carefully
  and find out if the functionality is already covered,
  maybe by an individual configuration.
- Search the [Discussions][ghDiscussions] and [Issues][ghIssues]
  to see if the enhancement has already been suggested.
  If it has, add a comment to the existing thread instead of opening a new one.
- Find out whether your idea fits with the scope and aims of the project.
  It's up to you to make a strong case
  to convince the project's developers of the merits of this feature.
  Keep in mind that we want features that will be useful
  to the majority of our users and not just a small subset.
  If you're just targeting a minority of users,
  consider writing an add-on/plugin library.

#### How Do I Submit a Good Enhancement Suggestion?

Enhancement suggestions are tracked as [Issues][ghIssues],
_after receiving approval in the [Discussions][ghDiscussions]_.
We recommend starting with a discussion to get initial feedback
and decide on the best solution before creating a formal issue.

- Create a [New Feature][ghNewFeature] or [Enhancement][ghEnhancement] request.
- Use a **clear and descriptive title** for the issue to identify the suggestion.
- Provide a **step-by-step description of the suggested enhancement**
  in as much detail as possible.
- **Describe the current behavior**
  and **explain which behavior you would like to see instead** and why.
  At this point you can also tell which alternatives do not work for you.
- **Explain why this enhancement would be useful** to most users.
  You may also want to point out the other projects that solved it better
  and which could serve as inspiration.

## Contributing Changes

Changes will be merged if they improve the project in some way.
All contributions are made via
a [pull request (PR) from a _fork_ of the repo][ghFork]
rather than through direct commits or PRs from other branches _in_ the repo.

Rebasing is encouraged when keeping your fork branch up-to-date
(rather than merging `main` into your branch)
because it keeps the commit history clean.

### Quick Code Review Rules

- Keep PRs short and sweet! This makes them easier to review.
- Don't mix unrelated changes in one pull request.
  For example, a code style change should never be mixed with a bug fix.
- All changes should follow the [styleguides][styleguideFile].
- Use `Draft` pull requests for changes you're still working on,
  but want early CI loop feedback for.
  When you think your changes are ready for review,
  [change the status][ghStatus] of your pull request.

### Pull Request Ownership

The code owners of the project have the final say
when it comes to style, merge, or other conflicts.
While a PR may satisfy all the technical requirements,
a code owner may still make or request additional changes
if they feel it necessary to maintain project consistency and/or integrity.
Code owners reserve the right to alter the code and/or commits
in a PR themselves before approving and merging it.

### Merging Pull Requests

Pull requests will be merged by a code owner
when the following conditions have been met:

- The PR has been approved by at least one code owner
  and any other objections are addressed.
  - You can request another review from the original reviewer.
- The PR successfully builds and passes all checks
  in the Continuous Integration (CI) system.

PRs should never be squashed or rebased when merging.
Including merge commits helps when analyzing the change history.

### Blocking Pull Request Merging

If for whatever reason you would like to move your pull request
back to an in-progress status to avoid merging it in the current form,
you can turn the PR into a draft PR by
selecting the option under the reviewers section.

## Your First Code Contribution

Issues marked with a `good first issue` or `help wanted` label
can be a great place to start if you're interested in contributing.
These issues are typically more straightforward and well-defined,
making them suitable for newcomers to the project.

When picking up an issue to work on,
leave a comment on the issue to let others know you're working on it
to avoid duplication of effort.

## Attribution

This guide is based on the [contributing.md][contrib] website.
[Make your own][contribEx]!

<!-- Source Code URIs (folders first, then files; each alphabetical) -->

[docsFolder]: ./docs/
[styleguideFile]: ./docs/Styleguide.md
[cocFile]: ./CODE_OF_CONDUCT.md
[securityFile]: ./SECURITY.md

<!-- GitHub URIs (alphabetical) -->

[ghDiscussions]: https://github.com/TaffarelJr/.actions/discussions
[ghEnhancement]: https://github.com/TaffarelJr/.actions/issues/new?template=02_enhancement.yml
[ghFork]: https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/creating-a-pull-request-from-a-fork
[ghIssues]: https://github.com/TaffarelJr/.actions/issues
[ghNewBug]: https://github.com/TaffarelJr/.actions/issues/new?template=03_bug_report.yml
[ghNewFeature]: https://github.com/TaffarelJr/.actions/issues/new?template=01_new_feature.yml
[ghNewIssue]: https://github.com/TaffarelJr/.actions/issues/new?template=04_performance_issue.yml
[ghStatus]: https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/changing-the-stage-of-a-pull-request
[ghWiki]: https://github.com/TaffarelJr/.actions/wiki
[silentcast]: https://github.com/colinkeenan/silentcast

<!-- Public URIs (alphabetical) -->

[contrib]: https://contributing.md/
[contribEx]: https://contributing.md/example/
[licecap]: https://www.cockos.com/licecap
[stackOverflow]: https://stackoverflow.com/
