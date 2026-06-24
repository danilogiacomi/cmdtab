# AGENTS.md

Canonical instructions for AI agents and human contributors working in this repo.
Other agent tools (Claude Code, Codex, opencode, pi) read this file; `CLAUDE.md` is a
symlink to it.

## Project overview

**CmdTab** is a macOS application that lets you switch between open windows with the
`Command+Tab` key combination — a window switcher in the spirit of the KDE Plasma
desktop, rather than the default macOS app switcher.

> Status: greenfield. The implementation does not exist yet. Commands below are
> **templated placeholders** — replace the `TODO` markers once the build system is in
> place (likely a Swift Package or an Xcode project).

## Build · Test · Lint

```bash
swift build            # build all targets
swift test             # run the CmdTabCore unit tests
./Scripts/bundle.sh    # assemble CmdTab.app (added in Task 5)
swift format lint --recursive Sources   # lint (requires swift-format)
```

## Code style

- Swift, targeting macOS. Follow the official
  [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Formatting and linting are enforced via `swiftlint` + `swift format` (see
  `.pre-commit-config.yaml`). Run them before committing.
- Prefer small, focused types; keep window-management side effects isolated behind
  testable interfaces.

## Project structure

Greenfield — to be established. Suggested layout once code lands:

```
Sources/         application source
Tests/           unit / integration tests
specs/           task specifications (see specs/TEMPLATE.md)
docs/            developer & agent documentation
.github/         CI workflows
```

## Safe to run / security

- **Safe without confirmation:** read-only inspection and the build/test/lint commands
  above (`swift build`, `swift test`, `swiftlint`, `git status`, `git diff`).
- **Ask first:** anything that installs global tooling, changes system accessibility /
  input-monitoring permissions, modifies files outside the repo, or touches the network.
- This app will likely need macOS **Accessibility** and/or **input-monitoring**
  permissions to observe and switch windows — treat granting those as an explicit,
  user-approved step, never automated.
- Never commit secrets. Copy `.env.example` to `.env` (gitignored) for any local
  configuration. See `docs/agent-execution.md` for the full sandbox/execution policy.
