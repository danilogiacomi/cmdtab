#!/usr/bin/env bun
// Regenerate the "Built by agents" section of README.md from this repo's own
// local agent logs (Claude Code transcripts + Codex rollouts whose cwd matches).
//
//   bun run usage:self      # or: bun run scripts/usage-self.ts
//
// The section lives between the START/END markers below. If no local logs are
// found (e.g. a fresh clone or CI), the existing section is left untouched so
// the script is safe to run anywhere — including from the pre-commit hook.

import { homedir } from "node:os";
import { join } from "node:path";

export const START = "<!-- usage:self:start -->";
export const END = "<!-- usage:self:end -->";

export interface UsageStats {
  totalTokens: number;
  inputTokens: number;
  outputTokens: number;
  cacheCreation: number;
  cacheRead: number;
  activeSeconds: number;
  wallSeconds: number;
  assistantTurns: number;
  toolCalls: number;
  models: string[];
  agents: string[];
  firstDate?: string;
  lastDate?: string;
}

function empty(): UsageStats {
  return {
    totalTokens: 0,
    inputTokens: 0,
    outputTokens: 0,
    cacheCreation: 0,
    cacheRead: 0,
    activeSeconds: 0,
    wallSeconds: 0,
    assistantTurns: 0,
    toolCalls: 0,
    models: [],
    agents: [],
  };
}

export function hasData(s: UsageStats): boolean {
  return s.totalTokens > 0;
}

export function formatTokens(n: number): string {
  if (n >= 1e9) return `${(n / 1e9).toFixed(2)}B`;
  if (n >= 1e6) return `${(n / 1e6).toFixed(1)}M`;
  if (n >= 1e3) return `${(n / 1e3).toFixed(1)}K`;
  return String(n);
}

export function formatDuration(seconds: number): string {
  const s = Math.round(seconds);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m`;
  return `${s}s`;
}

// Sum the wall-clock span and the "active" time (consecutive gaps under 5 minutes)
// from a sorted list of epoch-millisecond timestamps.
function timeSpans(tsMs: number[]): { activeSeconds: number; wallSeconds: number } {
  if (tsMs.length < 2) return { activeSeconds: 0, wallSeconds: 0 };
  const sorted = [...tsMs].sort((a, b) => a - b);
  let active = 0;
  let prev = sorted[0] as number;
  for (let i = 1; i < sorted.length; i++) {
    const cur = sorted[i] as number;
    const gap = cur - prev;
    if (gap < 300_000) active += gap;
    prev = cur;
  }
  const first = sorted[0] as number;
  const last = sorted[sorted.length - 1] as number;
  return { activeSeconds: active / 1000, wallSeconds: (last - first) / 1000 };
}

// --- Claude Code transcripts ---

export function aggregateClaude(contents: string[]): { stats: UsageStats; tsMs: number[] } {
  const stats = empty();
  const tsMs: number[] = [];
  const models = new Set<string>();
  for (const text of contents) {
    for (const line of text.split("\n")) {
      if (!line.trim()) continue;
      let o: Record<string, unknown>;
      try {
        o = JSON.parse(line);
      } catch {
        continue;
      }
      const t = o.timestamp;
      if (typeof t === "string") {
        const ms = Date.parse(t);
        if (!Number.isNaN(ms)) tsMs.push(ms);
      }
      const msg = o.message as Record<string, unknown> | undefined;
      if (o.type === "user") continue;
      if (o.type === "assistant" && msg && typeof msg === "object") {
        stats.assistantTurns++;
        const u = msg.usage as Record<string, number> | undefined;
        if (u) {
          stats.inputTokens += u.input_tokens ?? 0;
          stats.outputTokens += u.output_tokens ?? 0;
          stats.cacheCreation += u.cache_creation_input_tokens ?? 0;
          stats.cacheRead += u.cache_read_input_tokens ?? 0;
        }
        const model = msg.model;
        if (typeof model === "string" && model !== "<synthetic>") models.add(model);
        const content = msg.content;
        if (Array.isArray(content)) {
          for (const c of content) {
            if (c && typeof c === "object" && (c as { type?: string }).type === "tool_use")
              stats.toolCalls++;
          }
        }
      }
    }
  }
  stats.totalTokens =
    stats.inputTokens + stats.outputTokens + stats.cacheCreation + stats.cacheRead;
  stats.models = [...models];
  if (stats.totalTokens > 0) stats.agents.push("Claude Code");
  return { stats, tsMs };
}

// --- Codex rollouts (only sessions whose session_meta cwd matches repoPath) ---

export function aggregateCodex(
  contents: string[],
  repoPath: string,
): { stats: UsageStats; tsMs: number[] } {
  const stats = empty();
  const tsMs: number[] = [];
  let matched = false;
  for (const text of contents) {
    const lines = text.split("\n").filter((l) => l.trim());
    if (lines.length === 0) continue;
    let cwd: string | undefined;
    let lastTotals: Record<string, number> | undefined;
    const sessionTs: number[] = [];
    for (const line of lines) {
      let o: Record<string, unknown>;
      try {
        o = JSON.parse(line);
      } catch {
        continue;
      }
      const payload = o.payload as Record<string, unknown> | undefined;
      if (o.type === "session_meta" && payload && typeof payload.cwd === "string")
        cwd = payload.cwd;
      const t = o.timestamp;
      if (typeof t === "string") {
        const ms = Date.parse(t);
        if (!Number.isNaN(ms)) sessionTs.push(ms);
      }
      // token_count events carry the cumulative total_token_usage for the session.
      if (payload?.type === "token_count") {
        const info = payload.info as Record<string, unknown> | undefined;
        const totals = info?.total_token_usage as Record<string, number> | undefined;
        if (totals) lastTotals = totals;
      }
    }
    if (cwd !== repoPath || !lastTotals) continue;
    matched = true;
    tsMs.push(...sessionTs);
    stats.inputTokens += lastTotals.input_tokens ?? 0;
    stats.outputTokens +=
      (lastTotals.output_tokens ?? 0) + (lastTotals.reasoning_output_tokens ?? 0);
    stats.cacheRead += lastTotals.cached_input_tokens ?? 0;
  }
  stats.totalTokens =
    stats.inputTokens + stats.outputTokens + stats.cacheCreation + stats.cacheRead;
  if (matched && stats.totalTokens > 0) stats.agents.push("Codex");
  return { stats, tsMs };
}

export function mergeStats(
  a: { stats: UsageStats; tsMs: number[] },
  b: { stats: UsageStats; tsMs: number[] },
): UsageStats {
  const merged = empty();
  for (const k of [
    "inputTokens",
    "outputTokens",
    "cacheCreation",
    "cacheRead",
    "assistantTurns",
    "toolCalls",
  ] as const) {
    merged[k] = a.stats[k] + b.stats[k];
  }
  merged.totalTokens =
    merged.inputTokens + merged.outputTokens + merged.cacheCreation + merged.cacheRead;
  merged.models = [...new Set([...a.stats.models, ...b.stats.models])];
  merged.agents = [...new Set([...a.stats.agents, ...b.stats.agents])];
  const allTs = [...a.tsMs, ...b.tsMs];
  const spans = timeSpans(allTs);
  merged.activeSeconds = spans.activeSeconds;
  merged.wallSeconds = spans.wallSeconds;
  if (allTs.length > 0) {
    const sorted = [...allTs].sort((x, y) => x - y);
    const first = sorted[0] as number;
    const last = sorted[sorted.length - 1] as number;
    merged.firstDate = new Date(first).toISOString().slice(0, 10);
    merged.lastDate = new Date(last).toISOString().slice(0, 10);
  }
  return merged;
}

export function renderSection(s: UsageStats): string {
  const agents = s.agents.length ? s.agents.join(" · ") : "—";
  const models = s.models.length ? s.models.join(", ") : "—";
  const dates = s.firstDate
    ? s.firstDate === s.lastDate
      ? s.firstDate
      : `${s.firstDate} → ${s.lastDate}`
    : "—";
  return [
    START,
    "",
    "## 🤖 Built by agents",
    "",
    "This project is built largely by coding agents. The numbers below are this repo's own",
    "development footprint, read from the local agent logs (Claude Code transcripts and",
    "Codex rollouts) on the machine that generated this section.",
    "",
    "| Metric | Value |",
    "|---|---|",
    `| **Total tokens** | **${formatTokens(s.totalTokens)}** |`,
    `| Token breakdown | ${formatTokens(s.outputTokens)} output · ${formatTokens(s.inputTokens)} input · ${formatTokens(s.cacheCreation)} cache-write · ${formatTokens(s.cacheRead)} cache-read |`,
    `| Agent time | ~${formatDuration(s.activeSeconds)} active (${formatDuration(s.wallSeconds)} wall-clock) |`,
    `| Turns | ${s.assistantTurns.toLocaleString("en-US")} assistant turns · ${s.toolCalls.toLocaleString("en-US")} tool calls |`,
    `| Agents / models | ${agents} — ${models} |`,
    `| As of | ${dates} |`,
    "",
    "> 💡 Most of those tokens are *cache reads* — re-reading the growing conversation each",
    "> turn — which is why the total dwarfs the tokens actually written.",
    "",
    "_Regenerated by `bun Scripts/usage-self.ts` (kept fresh via the repo's pre-commit hook)._",
    "",
    END,
  ].join("\n");
}

export function replaceSection(readme: string, section: string): string {
  const start = readme.indexOf(START);
  const end = readme.indexOf(END);
  if (start !== -1 && end !== -1 && end > start) {
    return readme.slice(0, start) + section + readme.slice(end + END.length);
  }
  // No markers yet — append before the License heading if present, else at the end.
  const licenseIdx = readme.indexOf("\n## License");
  if (licenseIdx !== -1) {
    return `${readme.slice(0, licenseIdx)}\n\n${section}\n${readme.slice(licenseIdx)}`;
  }
  return `${readme.replace(/\s*$/, "")}\n\n${section}\n`;
}

// Claude encodes a project's log dir by replacing path separators/dots with "-".
export function claudeProjectDir(repoPath: string): string {
  return repoPath.replace(/[/.]/g, "-");
}

async function readAll(glob: string, cwd: string): Promise<string[]> {
  const out: string[] = [];
  try {
    for await (const rel of new Bun.Glob(glob).scan({ cwd, onlyFiles: true })) {
      out.push(await Bun.file(join(cwd, rel)).text());
    }
  } catch {
    // directory missing — return what we have (possibly nothing)
  }
  return out;
}

async function main(): Promise<void> {
  const repoPath = process.cwd();
  const claudeRoot = join(homedir(), ".claude", "projects", claudeProjectDir(repoPath));
  const codexRoot = join(process.env.CODEX_HOME ?? join(homedir(), ".codex"), "sessions");

  const claude = aggregateClaude(await readAll("*.jsonl", claudeRoot));
  const codex = aggregateCodex(await readAll("**/rollout-*.jsonl", codexRoot), repoPath);
  const stats = mergeStats(claude, codex);

  const readmePath = join(repoPath, "README.md");
  const readme = await Bun.file(readmePath).text();

  if (!hasData(stats)) {
    console.log("usage:self — no local agent logs for this repo; README left unchanged.");
    return;
  }

  const next = replaceSection(readme, renderSection(stats));
  if (next === readme) {
    console.log("usage:self — README already up to date.");
    return;
  }
  await Bun.write(readmePath, next);
  console.log(
    `usage:self — updated README: ${formatTokens(stats.totalTokens)} tokens, ` +
      `~${formatDuration(stats.activeSeconds)} active, ${stats.agents.join(" · ") || "no agents"}.`,
  );
}

if (import.meta.main) await main();
