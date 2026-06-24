# 🎯 Agentic Readiness Report — CmdTab

**Mode**: greenfield  **Agents**: claude  **Generated**: 2026-06-22
**Overall Score**: **42/100**  🟡 Partially Ready

## Executive Summary

CmdTab has a clean, freshly-scaffolded agent-ready foundation: a canonical `AGENTS.md`
(bridged to `CLAUDE.md` by symlink), full secret-hygiene `.gitignore`, a documented
execution/sandbox policy, CI + pre-commit baselines, and a spec template. The score is
gated almost entirely by the absence of **source code** — testing, code intelligence,
and module structure can only be earned once implementation begins. That is expected and
healthy for day one.

```
Agent Instructions & Context      ██████████████░░  16.2/18
Navigability & Code Intelligence  █████████░░░░░░░  10.5/18
Testing & Feedback                █░░░░░░░░░░░░░░░   0.8/16
CI/CD, Automation & Governance    ███████░░░░░░░░░   5.8/14
Agent Tooling & Capabilities      ░░░░░░░░░░░░░░░░   0.0/12
Security & Sandbox                ████████░░░░░░░░   5.7/12
Spec-Driven Workflow & Docs       █████░░░░░░░░░░░   2.9/10
```

## Layer Analysis

| Layer | Score | Max |
|-------|-------|-----|
| Portable (any agent) | 39.1 | 94.3 |
| Target-specific (claude) | 2.7 | 5.7 |

The target layer is nearly maxed for its size — the `CLAUDE.md → AGENTS.md` symlink
bridge scores full marks; only `agent_permission_policy` and `custom_commands` remain.
`machine_readable_contracts` is marked **N/A** (a desktop GUI window-switcher has no API
boundaries) and excluded from the denominator.

## Per-Dimension Detail

### 1. Agent Instructions & Context — 16.2/18 (raw 90)
- ✅ `primary_instruction_file` (100): project-specific `AGENTS.md`.
- ✅ `instruction_conciseness` (100): 70 lines, no boilerplate.
- ✅ `cross_agent_bridge` (100): `CLAUDE.md` symlink → one source of truth.
- ⚠️ `instruction_quality` (75): commands are templated TODO placeholders. **Fix** (partial): replace with real `swift build/test` once the toolchain lands. *Effort: Med.*
- ⚠️ `hierarchical_instructions` (75): no subpackages yet; root file is appropriate. Revisit when the repo grows multiple modules. *Effort: Med.*

### 2. Navigability & Code Intelligence — 10.5/18 (raw 58)
- ✅ `file_size_sanity` (100): no oversized files (350 LOC of docs).
- ⚠️ `readme_overview` (75): solid overview; setup steps are TODO pending toolchain.
- 🔸 `repo_map_availability` (50): nothing to map yet; generatable once code exists.
- 🔸 `semantic_nav_amenability` (50): Swift is LSP-amenable (sourcekit-lsp), but no code/config yet. *Effort: High.*
- 🔴 `dependency_structure_clarity` (25): no `Package.swift`/Xcode project. Add one for clear modules + a dependency graph. *Effort: High.*
- ⏭️ `machine_readable_contracts`: **N/A** (no service boundaries).

### 3. Testing & Feedback — 0.8/16 (raw 5) — *highest impact gap*
- 🔴 `test_suite_present` (0), `feedback_quality` (0), `fast_feedback_loop` (0), `coverage_reasonable` (0): no code/tests yet.
- 🔴 `test_commands_documented` (25): `swift test` documented as placeholder. **Fix** (skill): document real commands once a runner exists. *Effort: Low.*
- **Path:** write characterization/unit tests in `Tests/` as code lands; this dimension recovers fast once the suite exists.

### 4. CI/CD, Automation & Governance — 5.8/14 (raw 41)
- ✅ `pre_commit_hooks` (100): detect-secrets + hygiene + swift hooks.
- 🔸 `ci_runs_tests_lint` (50): workflow present but stages are echo-TODO.
- 🔴 `lint_format_automated` (25): swiftlint/swift-format referenced, no config file. **Fix** (skill): add `.swiftlint.yml`. *Effort: Low.*
- 🔴 `governance` (0): no CODEOWNERS / Dependabot. **Fix** (skill): scaffold both. *Effort: Low.*

### 5. Agent Tooling & Capabilities — 0.0/12 (raw 0)
- 🔴 `mcp_declaration` (0): **Fix** (skill): add `.mcp.json` — wire **Serena** for Swift semantic nav. *Effort: Low.*
- 🔴 `nav_comprehension_mcp_servers` (0): register Serena/Context7. *Effort: Med.*
- 🔴 `standard_skills` (0) / `bundled_helper_scripts` (0): scaffold a project `SKILL.md` if repeatable workflows emerge.
- 🔴 `custom_commands` (0, target): optional; Skills preferred.

### 6. Security & Sandbox — 5.7/12 (raw 48)
- ✅ `documented_execution_policy` (100): `docs/agent-execution.md` (LINCE + devcontainer + OS-sandbox + hosted).
- ✅ `injection_hygiene` (100): instructions only in trusted files.
- ⚠️ `secret_hygiene` (75): 100% `.gitignore` coverage + `.env.example` + detect-secrets; enable GitHub secret-scanning + push protection. *Effort: Med.*
- 🔴 `supply_chain_pinning` (25): commit a lockfile (`Package.resolved`) + add Dependabot once deps exist. *Effort: Low.*
- 🔴 `committed_isolation_config` (0): add a `.devcontainer/` with egress allowlist. *Effort: Med.*
- 🔴 `agent_permission_policy` (0, target): author `.claude/settings.json` deny rules. *Effort: Med.*

### 7. Spec-Driven Workflow & Docs — 2.9/10 (raw 29)
- 🔸 `spec_tasks_dir` (50) / `acceptance_criteria` (50): `specs/TEMPLATE.md` present; populate real specs per change.
- 🔴 `issue_pr_templates` (0): **Fix** (skill): add `.github/ISSUE_TEMPLATE/` + PR template. *Effort: Low.*
- 🔴 `adr_decisions` (0): add `docs/adr/` with a template. *Effort: Med.*
- 🔴 `docs_comprehension_signals` (25): add `ARCHITECTURE.md` + `CHANGELOG.md` as the project takes shape. *Effort: Med.*

## Remediation Roadmap

**Quick wins (skill-fixable, do now):**
1. `governance` — scaffold CODEOWNERS + Dependabot (`/agent-ready fix cicd_automation_governance`).
2. `mcp_declaration` — add `.mcp.json` wiring Serena (`/agent-ready fix agent_tooling_capabilities`).
3. `issue_pr_templates` — add issue/PR templates (`/agent-ready fix spec_driven_workflow_docs`).
4. `lint_format_automated` — add a `.swiftlint.yml`.

**As code lands (highest impact, mostly manual):**
1. Choose the toolchain → add `Package.swift`/Xcode project (unlocks dim 2 dependency clarity).
2. Write tests in `Tests/` + wire real `swift test` and CI commands (unlocks dim 3 — the biggest gap).
3. Commit `Package.resolved`; enable GitHub secret-scanning + push protection.
4. Add `ARCHITECTURE.md` + `CHANGELOG.md`; populate real specs in `specs/`.

Run `/agent-ready fix` to auto-generate the skill-fixable items, then `/agent-ready scan`
to track progress.
