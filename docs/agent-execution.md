# Agent execution & sandbox policy

How AI coding agents (Claude Code, Codex, opencode, pi, etc.) and automation should
execute commands in this repository. Vendor-neutral; pick the option that fits your
environment.

## Principles

1. **Least privilege.** Agents run with the narrowest access needed for the task.
2. **No surprise side effects.** Network access, global installs, and changes outside
   the repo require explicit human approval.
3. **Secrets stay out.** Real secrets live in `.env` (gitignored), never in the repo,
   prompts, or logs. See `.env.example`.
4. **Reproducible.** Prefer pinned toolchains and committed lockfiles
   (`Package.resolved`).

## Recommended sandbox options

Run agents inside a sandbox so a mistaken or untrusted command cannot affect the host:

- **[LINCE](https://lince.sh)** — lightweight isolated command execution for agents;
  good default for running agent-issued commands safely on your machine.
- **Dev container** — a `.devcontainer` gives a reproducible, disposable workspace
  isolated from the host.
- **OS-level sandbox** — macOS `sandbox-exec` / `seatbelt` profiles, or running the
  agent as a restricted user.
- **Hosted / ephemeral VM** — run the agent in a throwaway cloud VM or CI runner; the
  blast radius is the VM.

> macOS note: CmdTab needs Accessibility / input-monitoring permissions at runtime.
> Granting those is a manual, user-approved step and should **not** happen inside an
> automated agent run.

## Safe-to-run command list

Agents may run these without asking (read-only or repo-local, no network):

```bash
git status
git diff
git log --oneline -n 50
ls / find / cat / grep        # inspection within the repo
swift build                   # once the toolchain exists
swift test
swiftlint
swift format lint --recursive Sources
```

## Ask-first command list

Require explicit human approval:

```bash
# installs / mutations beyond the repo
brew install ...
swift package ...   # adding/updating dependencies
git push
rm -rf ... (outside the repo)
# anything touching the network or system permissions
```

When in doubt, stop and ask.
