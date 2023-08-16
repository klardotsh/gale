# Contributing to Gale

Currently, the advice is mostly "don't", but this document exists to those who
disregard such advice (thanks for taking the leap of faith!), and to start
laying the groundwork for some future where, maybe, things are in a better
state to contribute to. It also helps remind *myself* of some things...

## On Theming

Gale is a term most frequently associated with weather at sea, but sea stuff has
already been beaten to death by another (quite popular) open source ecosystem,
so note that Gale tools are named after meteorological phenomena: think wind,
clouds, rain, snow, etc. and less parts of boats or sea creatures or waves or
whatever.

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
- Commits (except those authored by `@klardotsh` and signed with his keys) must
  be `Signed-off-by` for acceptance to the tree, indicating the author of the
  commit has read, acknowledged, and agrees to the [Developer Certificate of
  Origin](https://developercertificate.org/). For a bit of a layman's
  explanation of the DCO and how it interacts with `git commit -s` and
  `Signed-off-by`, see [Drew DeVault's blog post on the
  subject](https://drewdevault.com/2021/04/12/DCO.html).

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


### Non-Text Files

Non-text files ("binaries") must **never** be checked into Git directly, as
they bloat the clone size of the repo _forever_, not just for the time that
the version of the file is reachable in the directory tree (since Git stores
objects permanently to allow local checkouts of prior commits, every revision
to, say, an image, must be cloned). Use [Git LFS](https://git-lfs.com/) for non-
text files. Prefer LFS over scripts that download binaries to the developer's
workstation "at runtime", unless licensing or other restrictions mandate that
the files can't be redistributed via LFS.

A great way to avoid checking non-text files in *anywhere* is to only preserve
the plain-text sources that are used to generate said binaries. For source
code, this is already an unwritten expectation within most projects ("hey, maybe
don't check in that unsigned binary you built on a box in your basement?"), but
where this becomes crucial is in imagery: I find this is most often the cause of
bloated Git repos. Anything that can be stored SVG-based vector imagery *should
be*, but anything inherently rasterized (say, screenshots) will have to live
in LFS.

> It should be noted that the canonical repo for Gale
> is hosted on Sourcehut, which [as of 2023 still does not support Git
> LFS](https://lists.sr.ht/~sircmpwn/sr.ht-discuss/%3CCAG+K25NORsCEpUQ%3DMP_iD5yEwn1v259g2jqr4ykjdX6RCZxoXw%40mail.gmail.com%3E)
> despite years of indicating intent. Currently, there's also no binary files
> in the tree. I'll deal with this problem whenever it becomes relevant:
> potentially by finding a dedicated LFS host and configuring the repo to use
> it, or potentially by finding a new Git host (again: there was already one
> quiet migration from GitHub to Sourcehut).
