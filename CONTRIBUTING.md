# Contributing

For day-to-day workflow, build, test, style, and repository layout guidance, see [AGENTS.md](./AGENTS.md).

## Users cannot create GitHub Issues directly

The main and the most important rule: **read the room!**

* Does your patch look like typical commit in the repo?
* Does your commit message look like typical commit message in the repo?
* Does your test look like typical test in the repo?
* etc.

## Submiting bugs and feature ideas

Submit bugs to https://github.com/nikitabobko/AeroSpace/discussions/categories/potential-bugs

Submit feature ideas to https://github.com/nikitabobko/AeroSpace/discussions/categories/feature-ideas

Rules:
* Search for duplicates (in GitHub Issues and Discussions) before creating a new discussion
* Upvote for issues/discussions that you find useful

**Consider including in bug reports**

* `aerospace debug-windows` output, if the problem is about handling some windows
* Screenshots of problematic windows
* Videos of problematic windows
* What did you try to resolve the issue?
* Your config
* AeroSpace version
* macOS version

**Consider including in feature request**

* Use cases!
* Alternative approaches
* Links to docs of similar features in other window managers that you know
* Synopsis, if you suggest a new command
* Mental model description

## Submiting code

One of the most useful thing you can do is to discuss issues/discussions.

Imagine that you were assigned to fix the issue.
Try to suggest the best approach and design on how to fix the issue.
Suggest the synopsis/config format, reason in written form what is good about it, what is bad about it, what are the alternatives, etc.
Basically, see the "Prior discussion" section in [Submit Pull Requests](#submit-pull-requests).

If you have something to contribute to the conversation. Do it!

Please keep the conversation to the point. Discuss one issue at a time, crossreference other issues

You can take a look at the following issues:

* Most voted issues: https://github.com/nikitabobko/AeroSpace/issues?q=is%3Aissue+is%3Aopen+sort%3Areactions-%2B1-desc
* Sometimes conversations happen on old issues that aren’t yet closed. See https://github.com/nikitabobko/AeroSpace/issues?q=is%3Aissue+is%3Aopen+sort%3Aupdated-desc
* Issues that are unclear on how to fix, or issues that require design of the interface (CLI or config interface) are tagged with `design-needed` tag https://github.com/nikitabobko/AeroSpace/issues?q=is%3Aissue+is%3Aopen+label%3Adesign-needed

## Submit Pull Requests

Small and trivial improvements can be submitted without any discussion.

**Prior discussion**. For non-trivial changes, discuss the approach first in GitHub Discussions before opening a PR.

Please create a new discussion and describe you want to do.

Consider including

* What users will observe after your change?
* Feature interaction with existing features or potential future features
* What use cases does it cover
* What is the proposed syntax for the config
* What is the proposed synopsis of CLI command
* How you think it should be implemented (if you can describe it)
* etc.

Discussing that you want to do something doesn't put any obligations on you. If you don't want to start the discussion just because you're afraid that you won't do it. Don't be afraid!

**Commit hygiene**. Keep commits atomic. Do not mix refactors with behavior changes in the same commit, and include the motivation in the commit message when it helps explain the change.

**License Agreement**. By contributing changes to this repository, you agree to license your contributions under the MIT license.

Maintainers can apply your patch with arbitrary modifications.

## Spread the word

Do you like the project? Does AeroSpace finally fix your problems with windows management on macOS? Good to hear it!

* Spread the word in social networks! (Don't forget to share the link :) )
* Talk about AeroSpace to your colleagues and friends
* Write a blogpost about your workflows
* Record a YouTube video

## Share your workflow and tips

Submit your tips to [the Goodies page](https://nikitabobko.github.io/AeroSpace/goodies). The source code of the page can be found in `./docs` directory

## Support the project financially

Supporting the project financially counts as a contribution (even if it's just a $1/month).
You can sponsor the project on GitHub Sponsors page: https://github.com/sponsors/nikitabobko
