import { existsSync } from "node:fs";
import { join } from "node:path";

import type { PlannedFile } from "./core/files.ts";

import { getIfExists } from "./core/io.ts";

const BEGIN = "<!-- BEGIN:better-supabase-agent-rules -->";
const END = "<!-- END:better-supabase-agent-rules -->";

/** The folders and files that show a project already works with agents. */
const AGENT_MARKERS = [
  "AGENTS.md",
  "CLAUDE.md",
  ".cursor",
  ".claude",
  ".agents",
] as const;

/**
 * The text between the markers. `better-supabase init` rewrites it on every
 * run, so a hand edit goes outside the markers.
 */
export function agentsBlockText(): string {
  return [
    BEGIN,
    "",
    "## better-supabase",
    "",
    "This project uses better-supabase. Before you change data access, auth or the schema:",
    "",
    "- Install the version-matched skills with `pnpm better-supabase skills install` (or `npx skills add ScaleDockHQ/better-supabase`).",
    "- Look up an API in the docs through the MCP server at https://bettersupabase.com/mcp, or read https://bettersupabase.com/llms.txt.",
    "- Never edit generated files (`database.types.ts`, the files `better-supabase gen` writes). Change the schema or the config, then run `pnpm better-supabase gen`.",
    "",
    END,
    "",
  ].join("\n");
}

/**
 * `current` with the managed block added, or replaced in place when the markers
 * are already there.
 */
export function withAgentsBlock(current: string | undefined): string {
  const block = agentsBlockText();

  if (current === undefined || current.trim() === "") {
    return `# Agent guide\n\n${block}`;
  }

  const begin = current.indexOf(BEGIN);
  const end = current.indexOf(END);

  if (begin !== -1 && end > begin) {
    return `${current.slice(0, begin)}${block}${current.slice(end + END.length).replace(/^\n/, "")}`;
  }

  return `${current.replace(/\n*$/, "\n")}\n${block}`;
}

/**
 * The planned `AGENTS.md` write for a project that already works with agents
 * (an `AGENTS.md`, `CLAUDE.md` or an agent folder), else nothing: init does not
 * add agent files to a project that has none.
 */
export async function agentsBlockFile(
  root: string,
): Promise<PlannedFile | undefined> {
  if (!AGENT_MARKERS.some((name) => existsSync(join(root, name)))) {
    return undefined;
  }

  const current = await getIfExists(join(root, "AGENTS.md"));

  return {
    path: "AGENTS.md",
    contents: withAgentsBlock(current),
    policy: "generated",
    note: "agent guide block",
  };
}
