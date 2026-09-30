import { existsSync } from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import type { ResolvedConfig } from "../../config/index.ts";
import type { ParsedArgs } from "../args.ts";
import type { CommandResult } from "../io.ts";

import { flagBool, flagList, flagString } from "../args.ts";
import { display, writeIfChanged } from "../io.ts";

export const SKILLS_HELP = `Usage: better-supabase skills <list|install> [--agent cursor,claude,agents] [--global] [--check]

Installs the Agent Skills that ship with better-supabase, so coding agents
use the typed repositories, adapters and tests the way the docs describe.
The installed skills match the installed package version. For any other
agent, \`npx skills add ScaleDockHQ/better-supabase\` installs them from GitHub.

Options
  --agent <names>   cursor (.cursor/skills), claude (.claude/skills), agents (.agents/skills).
                    Defaults to the agent folders the project already has, else agents.
  --global          Install into your home directory instead of the project
  --check           Fail when installed skills differ from this version`;

const AGENT_DIRS = {
  cursor: ".cursor/skills",
  claude: ".claude/skills",
  agents: ".agents/skills",
} as const;

type Agent = keyof typeof AGENT_DIRS;

const isAgent = (name: string): name is Agent => name in AGENT_DIRS;

/** The package's `skills/` folder, found by walking up from this module (src or dist). */
export function skillsRoot(
  from: string = fileURLToPath(import.meta.url),
): string {
  let dir = dirname(from);
  for (;;) {
    if (
      existsSync(join(dir, "skills")) &&
      existsSync(join(dir, "package.json"))
    ) {
      return join(dir, "skills");
    }
    const parent = dirname(dir);
    if (parent === dir)
      throw new Error("Could not find the better-supabase skills folder.");
    dir = parent;
  }
}

interface SkillFile {
  /** Relative to the skill folder, with `/` separators. */
  readonly path: string;
  readonly contents: string;
}

interface Skill {
  readonly name: string;
  readonly description: string;
  /** The `SKILL.md` contents. */
  readonly contents: string;
  /** `SKILL.md` first, then its reference files. */
  readonly files: readonly SkillFile[];
}

async function readTree(root: string, prefix = ""): Promise<SkillFile[]> {
  const files: SkillFile[] = [];
  const entries = await readdir(join(root, prefix), { withFileTypes: true });
  for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    const path = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) files.push(...(await readTree(root, path)));
    else if (entry.isFile())
      files.push({ path, contents: await readFile(join(root, path), "utf8") });
  }
  return files;
}

export async function loadSkills(
  root: string = skillsRoot(),
): Promise<Skill[]> {
  const skills: Skill[] = [];
  for (const entry of (await readdir(root, { withFileTypes: true })).filter(
    (item) => item.isDirectory(),
  )) {
    const folder = join(root, entry.name);
    if (!existsSync(join(folder, "SKILL.md"))) continue;
    const tree = await readTree(folder);
    const main = tree.find((file) => file.path === "SKILL.md")!;
    const files = [main, ...tree.filter((file) => file !== main)];
    const description = /^description:\s*(.+)$/m.exec(main.contents)?.[1] ?? "";
    skills.push({
      name: entry.name,
      description,
      contents: main.contents,
      files,
    });
  }
  return skills.sort((a, b) => a.name.localeCompare(b.name));
}

export async function runSkills(
  config: ResolvedConfig,
  args: ParsedArgs,
  env: Readonly<Record<string, string | undefined>>,
): Promise<CommandResult> {
  const [action] = args.rest;
  const skills = await loadSkills(
    flagString(args.flags, "from") ?? skillsRoot(),
  );
  if (action === "list") {
    return {
      code: 0,
      output: skills
        .map((skill) => `${skill.name}\n  ${skill.description}`)
        .join("\n"),
    };
  }
  if (action !== "install") {
    return {
      code: 2,
      error: action
        ? `Unknown skills action "${action}".\n\n${SKILLS_HELP}`
        : SKILLS_HELP,
    };
  }
  const global = flagBool(args.flags, "global");
  const base = global ? (env["HOME"] ?? homedir()) : config.root;
  const requested = flagList(args.flags, "agent");
  const unknown = requested.filter((name) => !isAgent(name));
  if (unknown.length > 0) {
    return {
      code: 2,
      error: `Unknown agent ${unknown.join(", ")}. Use ${Object.keys(AGENT_DIRS).join(", ")}.`,
    };
  }
  const detected = (Object.keys(AGENT_DIRS) as Agent[]).filter((agent) =>
    existsSync(join(base, AGENT_DIRS[agent].split("/")[0]!)),
  );
  const agents: Agent[] =
    requested.length > 0
      ? requested.filter(isAgent)
      : detected.length > 0
        ? detected
        : ["agents"];

  const check = flagBool(args.flags, "check");
  const lines: string[] = [];
  const stale: string[] = [];
  for (const agent of agents) {
    for (const skill of skills) {
      for (const file of skill.files) {
        const relativePath = join(AGENT_DIRS[agent], skill.name, file.path);
        const path = resolve(base, relativePath);
        const shown = global
          ? `~/${relativePath}`
          : display(config.root, relativePath);
        if (check) {
          const current = existsSync(path)
            ? await readFile(path, "utf8")
            : undefined;
          if (current !== file.contents) stale.push(shown);
          continue;
        }
        lines.push(
          `${(await writeIfChanged(path, file.contents)) ? "Wrote" : "Unchanged"} ${shown}`,
        );
      }
    }
  }
  if (check) {
    return stale.length === 0
      ? { code: 0, output: "Skills are up to date." }
      : {
          code: 1,
          error: `Out of date: ${stale.join(", ")}. Run \`better-supabase skills install\`.`,
        };
  }
  return { code: 0, output: lines.join("\n") };
}
