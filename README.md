## Apollo GraphOS Runtime APM Templates

This repository hosts the documentation and template artifacts to aid in setting up an APM solution
that monitors your Apollo GraphOS Runtime deployment.

Each template is provided within a subdirectory matching the name of its APM provider. Detailed
instructions for each provider can be found in the README of said subdirectories.

**The code in this repository is experimental and may be subject to change based on feedback
received during the experimental period. Given that, all feedback is welcome. If you need help or
have suggestions or feedback, please file an issue on this repository.**

### Development

This repository uses [`mise`](https://mise.jdx.dev/) to manage tooling and tasks. Currently, these
are just markdown linting and spell-checking. After installing it, run `mise trust` and then
`mise install` to install the tools. To verify your commit will pass PR checks before pushing, run
`mise pr-all`. Any errors can be fixed with `mise fix-spelling` or `mise format-markdown`.
