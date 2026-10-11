import { existsSync } from "node:fs";
import { join, posix, resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../command.ts";
import type { CommandResult } from "../io.ts";
import type { Prompter } from "../prompts.ts";

import { defineCliCommand, list } from "../command.ts";
import { findConfig, loadConfig } from "../config.ts";
import {
  CANCELLED,
  chooseIntegrations,
  integrationFiles,
  overwrite,
  packagesFor,
  parseIntegrations,
  templateContextFor,
  type WriteFlags,
  writeFiles,
} from "../glue.ts";
import { TYPEGEN_VERSION } from "../introspect/typegen-version.ts";
import { display, writeIfChanged } from "../io.ts";
import {
  detectProject,
  installCommand,
  type InstallTarget,
  type Project,
} from "../project.ts";
import {
  diffEngine,
  findSupabaseRoot,
  PGDELTA_TABLE,
  readSupabaseToml,
  tomlGet,
} from "../supabase-toml.ts";
import {
  baseFiles,
  needsLib,
  resolveIntegrations,
  suggestedIntegrations,
  TEMPLATES,
} from "../templates.ts";
import { detectWorkspace, suggestedPackage } from "../workspace.ts";

export type InitArgs = CliArgs<typeof INIT_ARGS>;

const INIT_ARGS = {
  casing: {
    type: "string",
    description:
      "Row keys in camelCase (camel, the default) or the database's snake_case (snake)",
    valueHint: "camel|snake",
  },
  with: {
    type: "string",
    description:
      "Integrations to add next to the detected ones: next, hono, orpc, edge, expo, mcp, client, react",
    valueHint: "integration,...",
  },
  package: {
    type: "string",
    description: "Workspace package to write to, relative to --cwd",
    valueHint: "dir",
  },
  lite: {
    type: "boolean",
    description:
      "Run on Supabase Lite: install @supabase/lite and use its CLI in the next steps",
  },
  force: { type: "boolean", description: "Overwrite files that exist" },
  "dry-run": { type: "boolean", description: "Show what would be written" },
} as const;

/**
 * Adds `[experimental.pgdelta] enabled = true` to `supabase/config.toml`
 * when it has no such table, so `supabase db schema declarative sync`
 * runs on pg-delta. A table set to `enabled = false` is left alone.
 */
async function enablePgDelta(
  root: string,
  args: WriteFlags,
  base: string,
): Promise<string[]> {
  const supabaseRoot = findSupabaseRoot(root);
  const toml = await readSupabaseToml(root);
  if (supabaseRoot === undefined || toml === undefined) return [];
  const path = join(supabaseRoot, "supabase/config.toml");
  const shown = display(base, path);
  if (diffEngine(toml) === "pg-delta") return [];
  if (
    tomlGet(toml.document, ["experimental", "pgdelta"]) !== undefined ||
    toml.text.includes("pgdelta")
  ) {
    return [
      `Kept    ${shown} (pg-delta is off; set [experimental.pgdelta] enabled = true, remove [db.migrations] schema_paths and use \`supabase db schema declarative sync\` instead of \`supabase db diff\`)`,
    ];
  }
  if (args["dry-run"] === true) return [`Would enable pg-delta in ${shown}`];
  const separator =
    toml.text === "" || toml.text.endsWith("\n\n")
      ? ""
      : toml.text.endsWith("\n")
        ? "\n"
        : "\n\n";
  await writeIfChanged(path, `${toml.text}${separator}${PGDELTA_TABLE}`);
  return [`Enabled pg-delta in ${shown}`];
}

/** The minor of `@supabase/lite` the `backend: 'lite'` option targets. */
const LITE_VERSION = "0.11";

/**
 * pg (or `@supabase/lite`, with `lite`) and the pinned postgrest-typegen as
 * dev dependencies, the ones the project lacks.
 */
function devPackages(project: Project, lite: boolean): string[][] {
  const database = lite ? "@supabase/lite" : "pg";
  const missing = [
    ...(database in project.dependencies
      ? []
      : [lite ? `${database}@${LITE_VERSION}` : database]),
    ...("@supabase/postgrest-typegen" in project.dependencies
      ? []
      : [`@supabase/postgrest-typegen@${TYPEGEN_VERSION}`]),
  ];
  return missing.length === 0 ? [] : [missing];
}

/** Where `init` writes: `--cwd`, `--package`, or the workspace package the person picks. */
async function initTarget(
  cwd: string,
  args: InitArgs,
  prompts: Prompter | undefined,
): Promise<{ readonly dir: string } | CommandResult> {
  if (args.package !== undefined) {
    const dir = posix.normalize(args.package.replaceAll("\\", "/"));
    if (!existsSync(join(cwd, dir, "package.json"))) {
      return {
        code: 2,
        error: `--package ${args.package} has no package.json. Pass the directory of a workspace package, relative to --cwd.`,
      };
    }
    return { dir: dir.replace(/\/$/, "") || "." };
  }
  const workspace = await detectWorkspace(cwd);
  if (!workspace || workspace.packages.length === 0) return { dir: "." };
  const suggested = suggestedPackage(workspace) ?? ".";
  if (!prompts) {
    return {
      code: 2,
      error: `${workspace.file} makes this a workspace root. Pass --package with the package that owns the runtime (${workspace.packages.map((entry) => entry.dir).join(", ")}), or --package . to write here.`,
    };
  }
  const dir = await prompts.select(
    "Package that owns the runtime",
    [
      ...workspace.packages.map((entry) => ({
        value: entry.dir,
        label: entry.dir,
        ...(entry.project.name ? { hint: entry.project.name } : {}),
      })),
      { value: ".", label: ".", hint: "the workspace root" },
    ],
    suggested,
  );
  return dir === undefined ? CANCELLED : { dir };
}

export async function runInit(
  config: ResolvedConfig,
  args: InitArgs,
  prompts?: Prompter,
): Promise<CommandResult> {
  const casing =
    args.casing ??
    (prompts
      ? await prompts.select(
          "Row keys",
          [
            { value: "camel", label: "camelCase", hint: "customerId" },
            {
              value: "snake",
              label: "snake_case",
              hint: "customer_id, as in the database",
            },
          ],
          "camel",
        )
      : "camel");
  if (casing === undefined) return CANCELLED;
  if (casing !== "camel" && casing !== "snake") {
    return { code: 2, error: '--casing must be "camel" or "snake"' };
  }
  const target = await initTarget(config.root, args, prompts);
  if ("code" in target) return target;
  const root = resolve(config.root, target.dir);
  const inPackage = target.dir !== ".";
  const workspaceProject = await detectProject(config.root);
  const project: Project = inPackage
    ? {
        ...(await detectProject(root)),
        packageManager: workspaceProject.packageManager,
      }
    : workspaceProject;
  const lite = args.lite === true;
  const installTarget: InstallTarget | undefined = inPackage
    ? { dir: target.dir, name: project.name }
    : undefined;
  const requested = parseIntegrations(list(args.with));
  if (typeof requested === "string") return { code: 2, error: requested };
  const detected = resolveIntegrations([
    ...suggestedIntegrations(project.frameworks),
    ...requested,
  ]);
  const chosen =
    args.with === undefined && prompts
      ? await chooseIntegrations(prompts, detected)
      : detected;
  if (chosen === undefined) return CANCELLED;
  const integrations = resolveIntegrations(chosen);
  const hasConfig = findConfig(root) !== undefined;
  let generated = posix.normalize(
    posix.join(project.srcDir, "lib/supabase/generated.ts"),
  );
  if (hasConfig)
    generated = inPackage ? (await loadConfig(root)).output : config.output;
  const templateContext = templateContextFor(project, generated);

  const files = [
    ...baseFiles(templateContext, casing, needsLib(integrations), integrations),
    ...integrationFiles(integrations, templateContext),
  ];
  const force = await overwrite(root, files, args, prompts, config.root);
  if (force === undefined) return CANCELLED;
  const where = inPackage ? ` in ${target.dir}` : "";
  const lines = [
    project.frameworks.length > 0
      ? `Found ${project.frameworks.join(", ")}${where}.`
      : `No framework found${where}.`,
    "",
    ...(await writeFiles(root, files, args, force, config.root)),
    ...(await enablePgDelta(root, args, config.root)),
  ];
  const packages = packagesFor(project, integrations);
  const cwdFlag = inPackage ? ` --cwd ${target.dir}` : "";
  const steps = [
    ...(packages.length > 0
      ? [installCommand(project.packageManager, packages, false, installTarget)]
      : []),
    ...devPackages(project, lite).map((names) =>
      installCommand(project.packageManager, names, true, installTarget),
    ),
    ...(project.hasSupabase || workspaceProject.hasSupabase
      ? []
      : [lite ? "npx lite init" : "supabase init"]),
    ...(lite
      ? [
          'Set jwt_secret = "env(SUPABASE_JWT_SECRET)" under [auth] in supabase/config.toml, and add SUPABASE_URL=http://127.0.0.1:54321 and a SUPABASE_JWT_SECRET of 32 or more characters to .env',
          "npx lite dev",
        ]
      : ["supabase start", `better-supabase env${cwdFlag}`]),
    `better-supabase gen${cwdFlag}`,
  ];
  lines.push(
    "",
    "Next:",
    ...steps.map((step, index) => `  ${index + 1}. ${step}`),
  );
  if (lite)
    lines.push(
      "  - Pass backend: 'lite' to createServer (or createNext, createHono, createEdge, createOrpc): https://bettersupabase.com/docs/platform/lite",
    );
  for (const name of integrations) {
    for (const hint of TEMPLATES[name].next ?? []) lines.push(`  - ${hint}`);
  }
  lines.push("", "Agent skills: better-supabase skills install");
  return { code: 0, output: lines.join("\n") };
}

export const initCommand: AnyCommand = defineCliCommand({
  meta: {
    name: "init",
    description:
      "Writes better-supabase.config.ts, src/lib/supabase/index.ts and glue for the frameworks in package.json",
  },
  args: INIT_ARGS,
  lists: ["with"],
  run: (args, { config, io }) => runInit(config, args, io.prompts),
});
