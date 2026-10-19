import { existsSync } from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { CliEnv } from "../env.ts";

import { byCodePoint } from "../compare.ts";
import { defineCliCommand, list } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import {
  applyPlan,
  type FilePlan,
  PLAN_ARGS,
  planResult,
} from "../core/files.ts";
import { commandMeta } from "../core/manifest.ts";

const SOURCE_ARG = {
  source: {
    type: "string",
    description: "Read skills from this folder instead of the package",
    valueHint: "dir",
  },
} as const;

const INSTALL_ARGS = {
  for: {
    type: "string",
    description:
      "cursor (.cursor/skills), claude (.claude/skills) or agents (.agents/skills). Defaults to skills.agents, then the agent folders the project has, else agents",
    valueHint: "names",
  },
  global: {
    type: "boolean",
    description: "Install into your home directory instead of the project",
  },
} as const;

type InstallArgs = CliArgs<
  typeof INSTALL_ARGS &
    typeof SOURCE_ARG &
    Pick<typeof PLAN_ARGS, "dry-run" | "check">
>;

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

  if (!existsSync(root)) {
    throw new Error("Could not find the better-supabase skills folder.");
  }

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

  for (const entry of entries.sort((a, b) => byCodePoint(a.name, b.name))) {
    const path = prefix ? `${prefix}/${entry.name}` : entry.name;

    if (entry.isDirectory()) {
      files.push(...(await readTree(root, path)));
    } else if (entry.isFile()) {
      files.push({ path, contents: await readFile(join(root, path), "utf-8") });
    }
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

    if (!existsSync(join(folder, "SKILL.md"))) {
      continue;
    }

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

  return skills.sort((a, b) => byCodePoint(a.name, b.name));
}

async function listSkills(source: string | undefined): Promise<CommandResult> {
  const skills = await loadSkills(source ?? skillsRoot());

  return {
    code: 0,
    output: skills
      .map((skill) => `${skill.name}\n  ${skill.description}`)
      .join("\n"),
    data: {
      skills: skills.map(({ name, description }) => ({ name, description })),
    },
  };
}

async function installSkills(
  config: ResolvedConfig,
  args: InstallArgs,
  env: CliEnv,
): Promise<CommandResult> {
  const skills = await loadSkills(args.source ?? skillsRoot());
  const global = args.global === true;
  const base = global ? (env.HOME ?? homedir()) : config.root;

  const requested =
    args.for === undefined ? [...(config.skills.agents ?? [])] : list(args.for);

  const unknown = requested.filter((name) => !isAgent(name));

  if (unknown.length > 0) {
    throw new CliError(
      "usage",
      `Unknown agent ${unknown.join(", ")}. Use ${Object.keys(AGENT_DIRS).join(", ")}.`,
    );
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

  const plan: FilePlan = {
    root: base,
    regenerate: `better-supabase skills install${global ? " --global" : ""}`,
    files: agents.flatMap((agent) =>
      skills.flatMap((skill) =>
        skill.files.map((file) => ({
          path: join(AGENT_DIRS[agent], skill.name, file.path),
          contents: file.contents,
        })),
      ),
    ),
  };

  return planResult(plan, await applyPlan(plan, args), {
    ...(global ? { summary: `Installed under ${base}.` } : {}),
    data: { agents },
  });
}

export const skillsListCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("skills list"),
  args: SOURCE_ARG,
  run: (args) => listSkills(args.source),
});

export const skillsInstallCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("skills install"),
  args: {
    ...INSTALL_ARGS,
    ...SOURCE_ARG,
    check: PLAN_ARGS.check,
    "dry-run": PLAN_ARGS["dry-run"],
  },
  lists: ["for"],
  run: (args, { config, env }) => installSkills(config, args, env),
});
