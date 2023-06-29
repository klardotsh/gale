# Contributing to Gale

Currently, the advice is mostly "don't", but this document exists to those who
disregard such advice (thanks for taking the leap of faith!), and to start
laying the groundwork for some future where, maybe, things are in a better
state to contribute to. It also helps remind *myself* of some things...

## Style Guides

See [the universal style guide for Gale](STYLE_GUIDE.universal.md) and [the Zig
style guide for Gale](STYLE_GUIDE.zig.md) for now. Neither are strictly
enforced yet, and especially the Zig one needs some updates to reflect the
reality that has organically grown in the codebase, but it's a start.

## Version Control And Maintenance Hygiene

> To a great degree, this guidance is inspired by [Zulip's Commit Discipline
> guide](https://zulip.readthedocs.io/en/latest/contributing/commit-discipline.html),
> which out of everywhere I've worked and all the codebases I've read in
> professional or hobbyist contexts, had probably the most readable and
> functional Git log. Read that guide to understand the context and
> inspirations for this one, if you're so interested.

- Commits must follow the message wording guide described in the subsection
  below. This will be enforced with tooling
  ([`gitlint`](https://jorisroovers.com/gitlint/) or perhaps a bespoke
  analogue) wherever feasible.
- Commits should be as small as feasibly makes an individual reviewable unit,
  and no smaller. A brand new component can often come through in one commit,
  but when refactoring existing code to set things up for cleanly adding a
  feature, the refactor should almost always live separately from that new
  feature.
- Tests must all pass on each commit, and thus updated and/or net-new tests
  should always be included in the same commit as the work that neccessitated
  them. It is never acceptable to retain "flakey" tests (those that only work
  sometimes, and perhaps break depending on the time of day or the availability
  of a network connection): if discovered during patchset review, they must be
  fixed before the work can be merged. If discovered on a trunk or integration
  branch, they should be fixed as soon as possible (ideally by the original
  author of the test, if possible).
- As a general rule, merge commits are unacceptable anywhere other than
  integration branches, and should only be made by project maintainers (for
  now, that means @klardotsh). Patchsets including merge commits (*especially*
  merge commits pulling from the patchset's target branch) will be rejected:
  the net-new commits should always be cleanly rebased on top of the target
  branch.
- GPG and/or SSH signatures for commits are strongly encouraged (see, for
  example [this article about signing with SSH
  keys](https://blog.dbrgn.ch/2021/11/16/git-ssh-signatures/)).

### Commit Messages

Commit messages should take the format of:

```
section[/subsection]: Provide succinct active-voice description of changes.

Details go in the body of the commit message and can wax poetic about the hows
and whys as the author sees fit. The title, however, should be no more than 72
characters long unless it's impossible to condense further without losing
crucial information (in which case, the *hard* limit is 100 characters).

You can use tags like these as necessary:

Refs: https://example.com/link/to/bug/tracker/1234
Co-authored-by: My Shadow <shadow@example.com>
```

Examples of sections might include `docs:` or `devxp:` or `perf:`, or some
section of the codebase, like `word_signature:`. Often, subsections may be
useful, for example: `std/fs: Add docstrings throughout.`.
