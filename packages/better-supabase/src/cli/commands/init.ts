import { existsSync } from "node:fs";
import { join, posix, resolve } from "node:path";

import type {
  BetterSupabaseConfig,
  ResolvedConfig,
  SqlWorkflow,
} from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { Prompter } from "../prompts.ts";
import type { Now } from "../sql/migrations.ts";
import type { TemplateFile } from "../templates.ts";

import { resolveConfig } from "../../config/index.ts";
import {
  type CreateDesign,
  designConfig,
  designOf,
  encodePreset,
  glueCommand,
  isPresetName,
  type Preset,
  PRESET_NAMES,
  presetBlocksSource,
  presetGlue,
  presetOf,
  PRESETS,
  resolvePreset,
  type ResolvedPreset,
} from "../../preset/index.ts";
import { findConfig, loadConfig } from "../config.ts";
import { defineCliCommand, list } from "../core/command.ts";
import { commandMeta } from "../core/manifest.ts";
import { enablePgDelta } from "../enable-pgdelta.ts";
import {
  CANCELLED,
  chooseIntegrations,
  integrationFiles,
  overwrite,
  packagesFor,
  parseIntegrations,
  templateContextFor,
  writeFiles,
} from "../glue.ts";
import { TYPEGEN_VERSION } from "../introspect/typegen-version.ts";
import {
  detectProject,
  installCommand,
  type InstallTarget,
  type Project,
} from "../project/detect.ts";
import { detectWorkspace, suggestedPackage } from "../project/workspace.ts";
import { writeDesign } from "../sql/design-edit.ts";
import { syncModules } from "../sql/sync.ts";
import { plain } from "../style.ts";
import {
  baseFiles,
  INTEGRATIONS,
  needsLib,
  resolveIntegrations,
  suggestedIntegrations,
  TEMPLATES,
} from "../templates.ts";
import { blockConfigImport, blocksWiringPath } from "./add.ts";

export type InitArgs = CliArgs<typeof INIT_ARGS>;

const SQL_WORKFLOWS: readonly SqlWorkflow[] = [
  "pg-delta",
  "migra",
  "migrations",
];

const isSqlWorkflow = (value: string): value is SqlWorkflow =>
  SQL_WORKFLOWS.some((workflow) => workflow === value);

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
  workflow: {
    type: "string",
    description:
      "How the SQL modules reach the database: pg-delta (the default), migra or migrations",
    valueHint: "pg-delta|migra|migrations",
  },
  preset: {
    type: "string",
    description:
      "A named preset, a code from /create or its URL: the config starts from it, and init writes its modules and lib/blocks.ts",
    valueHint: "name|code|url",
  },
  lite: {
    type: "boolean",
    description:
      "Run on Supabase Lite: install @supabase/lite and use its CLI in the next steps",
  },
  force: { type: "boolean", description: "Overwrite files that exist" },
  "dry-run": { type: "boolean", description: "Show what would be written" },
} as const;

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

  if (!workspace || workspace.packages.length === 0) {
    return { dir: "." };
  }

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

/** The preset `--preset` names, or the one the person picks; `null` for none. */
async function chosenPreset(
  args: InitArgs,
  prompts: Prompter | undefined,
): Promise<
  | {
      readonly value: string;
      readonly resolved: ResolvedPreset;
      readonly design?: CreateDesign | undefined;
    }
  | null
  | CommandResult
> {
  let value = args.preset;

  if (
    value === undefined &&
    prompts &&
    args.casing === undefined &&
    args.with === undefined
  ) {
    const picked = await prompts.select(
      "Preset",
      [
        { value: "none", label: "None", hint: "add blocks later" },
        ...PRESET_NAMES.map((name) => ({
          value: name,
          label: PRESETS[name].title,
          hint: PRESETS[name].description,
        })),
      ],
      "none",
    );

    if (picked === undefined) {
      return CANCELLED;
    }

    if (picked !== "none") {
      value = picked;
    }
  }

  if (value === undefined) {
    return null;
  }

  let preset: Preset;
  let design: CreateDesign | undefined;

  try {
    preset = presetOf(value);
    design = isPresetName(value) ? undefined : await designOf(value);
  } catch (error) {
    return {
      code: 2,
      error: error instanceof Error ? error.message : String(error),
    };
  }

  const resolved = resolvePreset(preset);

  if (resolved.conflicts.length > 0) {
    return {
      code: 2,
      error: `The preset can't install: ${resolved.conflicts.map((conflict) => `${conflict.block ?? conflict.field ?? ""} (${conflict.reason})`).join("; ")}.`,
    };
  }

  if (design !== undefined) {
    try {
      designConfig(resolved, design);
    } catch (error) {
      return {
        code: 2,
        error: error instanceof Error ? error.message : String(error),
      };
    }
  }

  return {
    value: isPresetName(value) ? value : encodePreset(preset),
    resolved,
    design,
  };
}

/** `files` with the design's keys written into the config file. */
function withDesign(
  files: readonly TemplateFile[],
  design: CreateDesign | undefined,
): TemplateFile[] | string {
  if (design === undefined) {
    return [...files];
  }

  const out: TemplateFile[] = [];

  for (const file of files) {
    if (posix.basename(file.path) !== "better-supabase.config.ts") {
      out.push(file);
      continue;
    }

    const edit = writeDesign(file.path, file.contents, design);

    if (!edit.ok) {
      return `The design can't be written to ${file.path}: ${edit.reason}`;
    }

    out.push({ ...file, contents: edit.text });
  }

  return out;
}

export async function runInit(
  config: ResolvedConfig,
  args: InitArgs,
  prompts?: Prompter,
  now: Now = () => new Date(),
): Promise<CommandResult> {
  const chosen = await chosenPreset(args, prompts);

  if (chosen !== null && "code" in chosen) {
    return chosen;
  }

  const casing =
    args.casing ??
    chosen?.resolved.preset.casing ??
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

  if (casing === undefined) {
    return CANCELLED;
  }

  if (casing !== "camel" && casing !== "snake") {
    return { code: 2, error: '--casing must be "camel" or "snake"' };
  }

  const workflow = args.workflow ?? "pg-delta";

  if (!isSqlWorkflow(workflow)) {
    return {
      code: 2,
      error: '--workflow must be "pg-delta", "migra" or "migrations"',
    };
  }

  const target = await initTarget(config.root, args, prompts);

  if ("code" in target) {
    return target;
  }

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

  if (typeof requested === "string") {
    return { code: 2, error: requested };
  }

  const fromPreset = parseIntegrations(
    chosen === null
      ? []
      : [
          ...chosen.resolved.preset.integrations,
          ...INTEGRATIONS.filter(
            (name) => name === chosen.resolved.preset.framework,
          ),
        ],
  );

  if (typeof fromPreset === "string") {
    return { code: 2, error: fromPreset };
  }

  const detected = resolveIntegrations([
    ...suggestedIntegrations(project.frameworks),
    ...requested,
    ...fromPreset,
  ]);

  const picked =
    args.with === undefined && prompts && chosen === null
      ? await chooseIntegrations(prompts, detected)
      : detected;

  if (picked === undefined) {
    return CANCELLED;
  }

  const integrations = resolveIntegrations(picked);
  const hasConfig = findConfig(root) !== undefined;

  let generated = posix.normalize(
    posix.join(project.srcDir, "lib/supabase/generated.ts"),
  );

  if (hasConfig) {
    generated = inPackage ? (await loadConfig(root)).output : config.output;
  }

  const templateContext = templateContextFor(project, generated);

  const files = withDesign(
    [
      ...baseFiles(
        templateContext,
        casing,
        needsLib(integrations),
        integrations,
        workflow,
        chosen?.value,
      ),
      ...integrationFiles(integrations, templateContext),
      ...(chosen === null
        ? []
        : [
            {
              path: blocksWiringPath(templateContext),
              contents: presetBlocksSource(
                chosen.resolved,
                blockConfigImport(templateContext),
              ),
            },
          ]),
    ],
    chosen?.design,
  );

  if (typeof files === "string") {
    return { code: 1, error: files };
  }

  const force = await overwrite(root, files, args, prompts, config.root);

  if (force === undefined) {
    return CANCELLED;
  }

  const where = inPackage ? ` in ${target.dir}` : "";

  const lines = [
    project.frameworks.length > 0
      ? `Found ${project.frameworks.join(", ")}${where}.`
      : `No framework found${where}.`,
    "",
    ...(await writeFiles(root, files, args, force, config.root)),
    ...(workflow === "pg-delta"
      ? await enablePgDelta(root, args["dry-run"] === true, config.root)
      : []),
  ];

  if (chosen !== null) {
    const presetConfig = resolveConfig(
      {
        preset: chosen.value,
        casing,
        output: generated,
        ...designKeys(chosen.resolved, chosen.design),
        ...(workflow === "pg-delta" ? {} : { sql: { workflow } }),
      },
      root,
    );

    const synced = await syncModules(
      presetConfig,
      { "dry-run": args["dry-run"] === true },
      plain,
      now,
    );

    lines.push("", synced.output ?? synced.error ?? "");
    const glue = presetGlue(chosen.resolved);

    if (glue.length > 0) {
      lines.push(
        "",
        `Glue for ${chosen.resolved.preset.framework}: ${glueCommand(glue)}`,
      );
    }
  }

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

  if (lite) {
    lines.push(
      "  - Pass backend: 'lite' to createServer (or createNext, createHono, createEdge, createOrpc): https://bettersupabase.com/docs/platform/lite",
    );
  }

  for (const name of integrations) {
    for (const hint of TEMPLATES[name].next ?? []) {
      lines.push(`  - ${hint}`);
    }
  }

  lines.push("", "Agent skills: better-supabase skills install");

  return { code: 0, output: lines.join("\n") };
}

export const initCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("init"),
  args: INIT_ARGS,
  lists: ["with"],
  run: (args, { config, io }) => runInit(config, args, io.prompts),
});

/** The `blocks` and `appTables` keys a design adds to the preset's config. */
function designKeys(
  resolved: ResolvedPreset,
  design: CreateDesign | undefined,
): Pick<BetterSupabaseConfig, "appTables" | "blocks"> {
  if (design === undefined) {
    return {};
  }

  const { blocks, appTables } = designConfig(resolved, design);

  return { blocks, ...(appTables === undefined ? {} : { appTables }) };
}
