# CmdTab

A macOS application that lets you switch between **windows** by pressing the
`Command+Tab` key combination — much like window switching on a KDE Plasma desktop.

The default macOS `Command+Tab` switches between *applications*. CmdTab instead cycles
through individual *windows*, so two windows of the same app are first-class targets.

## Status

🌱 **Greenfield** — the implementation has not started yet. This repository currently
contains the project scaffold (instructions, CI, and contribution conventions). See
[`AGENTS.md`](AGENTS.md) for build/test/lint commands and the working agreement.

## Goals

- Switch between open windows (not just apps) with `Command+Tab`.
- A Plasma-like switcher overlay showing window thumbnails/titles.
- Fast, keyboard-driven, low-overhead, and unobtrusive.

## Requirements (planned)

- macOS (version TBD).
- **Accessibility** and/or **input-monitoring** permissions, which the app needs to
  observe key events and enumerate/raise windows. These are granted manually by the
  user in System Settings → Privacy & Security.

## Getting started

The toolchain is not chosen yet (likely a Swift Package or Xcode project). Once it
lands, build and test commands will live in [`AGENTS.md`](AGENTS.md). For now:

```bash
git clone <repo-url>
cd cmdtab
# build/test commands: TODO — see AGENTS.md
```

## Contributing

- Read [`AGENTS.md`](AGENTS.md) — the canonical instructions for humans and AI agents.
- Capture each task as a spec using [`specs/TEMPLATE.md`](specs/TEMPLATE.md).
- Install pre-commit hooks: `pip install pre-commit && pre-commit install`.
- Never commit secrets; copy `.env.example` to `.env` for local config.
- Agent execution / sandbox policy: [`docs/agent-execution.md`](docs/agent-execution.md).

## License

TODO — add a license before the first public release.
