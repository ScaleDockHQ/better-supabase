import { existsSync } from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../command.ts";
import type { CliEnv } from "../env.ts";
import type { CommandResult } from "../io.ts";

import { defineCliCommand, list } from "../command.ts";
import { display, writeIfChanged } from "../io.ts";

const ARGS = {
  action: {
    type: "positional",
    required: false,
    description: "list or install",
  },
  agent: {
    type: "string",
    description:
      "cursor (.cursor/skills), claude (.claude/skills) or agents (.agents/skills). Defaults to the agent folders the project has, else agents",
    valueHint: "names",
  },
  global: {
    type: "boolean",
    description: "Install into your home directory instead of the project",
  },
  check: {
    type: "boolean",
    description: "Fail when installed skills differ from this version",
  },
  from: {
    type: "string",
    description: "Read skills from this folder instead of the package",
    valueHint: "dir",
  },
} as const;

export type SkillsArgs = CliArgs<typeof ARGS>;

const AGENT_DIRS = {
  cursor: ".cursor/skills",
  claude: ".claude/skills",
  agents: ".agents/skills",
} as const;

type Agent = keyof typeof AGENT_DIRS;

const isAgent = (name: string): name is Agent => name in AGENT_DIRS;

/** The `skills/` folder of the `better-supabase` package this CLI depends on. */
function skillsRoot(): string {
  const root = join(
    dirname(fileURLToPath(import.meta.resolve("better-supabase/package.json"))),
    "skills",
  );
  if (!existsSync(root))
    throw new Error("Could not find the better-supabase skills folder.");
  return root;
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
  args: SkillsArgs,
  env: CliEnv,
): Promise<CommandResult> {
  const [action] = args._;
  const skills = await loadSkills(args.from ?? skillsRoot());
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
      error: `${action ? `Unknown skills action "${action}"` : "Name an action"}. Use \`skills list\` or \`skills install\`.`,
    };
  }
  const global = args.global === true;
  const base = global ? (env.HOME ?? homedir()) : config.root;
  const requested = list(args.agent);
  const unknown = requested.filter((name) => !isAgent(name));
  if (unknown.length > 0) {
    return {
      code: 2,
      error: `Unknown agent ${unknown.join(", ")}. Use ${Object.keys(AGENT_DIRS).join(", ")}.`,
    };
  }
  // SAFETY: AGENT_DIRS is keyed by Agent, and Object.keys widens the keys to string.
  const detected = (Object.keys(AGENT_DIRS) as Agent[]).filter((agent) =>
    existsSync(join(base, AGENT_DIRS[agent].split("/")[0]!)),
  );
  const agents: Agent[] =
    requested.length > 0
      ? requested.filter(isAgent)
      : detected.length > 0
        ? detected
        : ["agents"];

  const check = args.check === true;
  const lines: string[] = [];
  const stale: string[] = [];
  const targets = agents.flatMap((agent) =>
    skills.flatMap((skill) =>
      skill.files.map((file) => ({
        file,
        relativePath: join(AGENT_DIRS[agent], skill.name, file.path),
      })),
    ),
  );
  for (const { file, relativePath } of targets) {
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

export const skillsCommand: AnyCommand = defineCliCommand({
  meta: {
    name: "skills",
    description:
      "Installs the Agent Skills that ship with this version of better-supabase",
  },
  args: ARGS,
  lists: ["agent"],
  run: (args, { config, env }) => runSkills(config, args, env),
});
