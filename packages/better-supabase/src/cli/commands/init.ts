import { existsSync } from "node:fs";
import { join, posix, resolve } from "node:path";

import type {
  FlatConfig,
  ResolvedConfig,
  SqlWorkflow,
} from "../../config/index.ts";
import type {
  ConfigConventions,
  CreateDesign,
  ResolvedPreset,
} from "../../preset/index.ts";
import type { AnyCommand, CliArgs } from "../core/command.ts";
import type { CommandResult, NextStep } from "../core/io.ts";
import type { InstallTarget, Project } from "../project/detect.ts";
import type { Prompter } from "../prompts.ts";
import type { Now } from "../sql/migrations.ts";
import type { TemplateFile } from "../templates.ts";

import { groupConfig, resolveConfig } from "../../config/index.ts";
import {
  conventionConfig,
  designConfig,
  encodePreset,
  glueCommand,
  integrationsForFramework,
  isPresetName,
  PRESET_NAMES,
  presetBlocksSource,
  presetGlue,
  PRESETS,
  resolvePreset,
} from "../../preset/index.ts";
import { findConfig, loadConfig } from "../config.ts";
import {
  CONVENTION_ARGS,
  CONVENTION_COMPLETIONS,
  conventionFlags,
  defaultConventions,
  hasConventionFlags,
  promptConventions,
  withConventions,
} from "../conventions.ts";
import { defineCliCommand, list } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import {
  applyPlan,
  changeLines,
  PLAN_ARGS,
  planResult,
} from "../core/files.ts";
import { commandMeta } from "../core/manifest.ts";
import { AUTHZ_NOTE, createUrlParam } from "../create-url.ts";
import { latestMigrationVersion } from "../doctor/migration-safety.ts";
import { enablePgDelta } from "../enable-pgdelta.ts";
import {
  CANCELLED,
  chooseIntegrations,
  integrationFiles,
  overwrite,
  packagesFor,
  parseIntegrations,
  templateContextFor,
  templatePlan,
} from "../glue.ts";
import { TYPEGEN_VERSION } from "../introspect/typegen-version.ts";
import { readPresetInput } from "../preset-input.ts";
import { detectProject, installCommand } from "../project/detect.ts";
import { detectWorkspace, suggestedPackage } from "../project/workspace.ts";
import { writeDesign } from "../sql/design-edit.ts";
import { syncModules } from "../sql/sync.ts";
import { plain } from "../style.ts";
import {
  baseFiles,
  needsLib,
  resolveIntegrations,
  suggestedIntegrations,
  TEMPLATES,
} from "../templates.ts";
import { blockConfigImport, blocksWiringPath } from "./add.ts";

export type InitArgs = CliArgs<
  typeof INIT_ARGS & typeof CONVENTION_ARGS & typeof PLAN_ARGS
>;

const SQL_WORKFLOWS: readonly SqlWorkflow[] = [
  "pg-delta",
  "migra",
  "migrations",
];

const isSqlWorkflow = (value: string): value is SqlWorkflow =>
  SQL_WORKFLOWS.some((workflow) => workflow === value);

const INIT_ARGS = {
  integration: {
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
      "A named preset, a code from /create, its URL or a downloaded design file: the config starts from it, and init writes its modules and lib/blocks.ts",
    valueHint: "name|code|url|file",
  },
  lite: {
    type: "boolean",
    description:
      "Run on Supabase Lite: install @supabase/lite and use its CLI in the next steps",
  },
} as const;

/** The minor of `@supabase/lite` the `backend: 'lite'` option targets. */
const LITE_VERSION = "0.11";

/**
 * Pg (or `@supabase/lite`, with `lite`) and the pinned postgrest-typegen as dev
 * dependencies, the ones the project lacks.
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

/**
 * Where `init` writes: `--cwd`, `--package` (or the `package=` of a Create
 * URL), or the workspace package the person picks.
 */
async function initTarget(
  cwd: string,
  pkg: string | undefined,
  prompts: Prompter | undefined,
): Promise<{ readonly dir: string } | CommandResult> {
  if (pkg !== undefined) {
    const dir = posix.normalize(pkg.replaceAll("\\", "/"));

    if (!existsSync(join(cwd, dir, "package.json"))) {
      throw new CliError(
        "usage",
        `--package ${pkg} has no package.json. Pass the directory of a workspace package, relative to --cwd.`,
      );
    }

    return { dir: dir.replace(/\/$/, "") || "." };
  }

  const workspace = await detectWorkspace(cwd);

  if (!workspace || workspace.packages.length === 0) {
    return { dir: "." };
  }

  const suggested = suggestedPackage(workspace) ?? ".";

  if (!prompts) {
    const others = workspace.packages
      .map((entry) => entry.dir)
      .filter((dir) => dir !== suggested);

    throw new CliError(
      "input_required",
      `${workspace.file} makes this a workspace root. Pass --package with the package that owns the runtime (${workspace.packages.map((entry) => entry.dir).join(", ")}), or --package . to write here.`,
      {
        missing: ["--package"],
        choices: { "--package": [...new Set([suggested, ...others, "."])] },
      },
    );
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
  flags: Partial<ConfigConventions>,
  prompts: Prompter | undefined,
  root: string,
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
    !hasConventionFlags(flags) &&
    args.integration === undefined
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

  const input = await readPresetInput(value, root);
  const design = input.design;
  const preset = withConventions(input.preset, flags);

  const resolved = resolvePreset(preset);

  if (resolved.conflicts.length > 0) {
    throw new CliError(
      "usage",
      `The preset can't install: ${resolved.conflicts.map((conflict) => `${conflict.block ?? conflict.field ?? ""} (${conflict.reason})`).join("; ")}.`,
    );
  }

  if (design !== undefined) {
    try {
      designConfig(resolved, design);
    } catch (error) {
      throw new CliError(
        "usage",
        error instanceof Error ? error.message : String(error),
      );
    }
  }

  return {
    value:
      isPresetName(value) && !hasConventionFlags(flags)
        ? value
        : encodePreset(preset),
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
  const flags = conventionFlags(args);
  const chosen = await chosenPreset(args, flags, prompts, config.root);

  if (chosen !== null && "code" in chosen) {
    return chosen;
  }

  let conventions: ConfigConventions | undefined = chosen?.resolved.preset;

  conventions ??=
    prompts && !hasConventionFlags(flags)
      ? await promptConventions(prompts)
      : defaultConventions(flags);

  if (conventions === undefined) {
    return CANCELLED;
  }

  const casing = conventions.casing;
  const keys = conventionConfig(conventions);

  const workflow = args.workflow ?? "pg-delta";

  if (!isSqlWorkflow(workflow)) {
    throw new CliError(
      "usage",
      '--workflow must be "pg-delta", "migra" or "migrations"',
    );
  }

  const target = await initTarget(
    config.root,
    args.package ?? createUrlParam(args.preset, "package"),
    prompts,
  );

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

  const requested = parseIntegrations(list(args.integration));

  if (typeof requested === "string") {
    throw new CliError("usage", requested);
  }

  const fromPreset = parseIntegrations(
    chosen === null
      ? []
      : [
          ...chosen.resolved.preset.integrations,
          ...integrationsForFramework(chosen.resolved.preset.framework),
        ],
  );

  if (typeof fromPreset === "string") {
    throw new CliError("usage", fromPreset);
  }

  const detected = resolveIntegrations([
    ...suggestedIntegrations(project.frameworks),
    ...requested,
    ...fromPreset,
  ]);

  const picked =
    args.integration === undefined && prompts && chosen === null
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

  const templateContext = templateContextFor(
    project,
    generated,
    chosen !== null || keys.blocks !== undefined,
  );

  const migrationSince =
    (await latestMigrationVersion(root)) ??
    (await latestMigrationVersion(config.root));

  const since = migrationSince === undefined ? {} : { migrationSince };

  const files = withDesign(
    [
      ...baseFiles(
        templateContext,
        casing,
        needsLib(integrations),
        integrations,
        workflow,
        chosen?.value,
        chosen === null
          ? {
              ...(keys.sql === undefined ? {} : { sql: keys.sql }),
              ...(keys.blocks === undefined ? {} : { blocks: keys.blocks }),
              provider: conventions.access === "provider",
              ...since,
            }
          : { provider: conventions.access === "provider", ...since },
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

  const applied = await applyPlan(
    templatePlan(root, files, "better-supabase init", config.root),
    { ...args, force },
  );

  if (applied.mode === "check" && applied.drift) {
    return planResult(
      templatePlan(root, files, "better-supabase init", config.root),
      applied,
    );
  }

  const lines = [
    project.frameworks.length > 0
      ? `Found ${project.frameworks.join(", ")}${where}.`
      : `No framework found${where}.`,
    "",
    ...changeLines(applied),
    ...(workflow === "pg-delta"
      ? await enablePgDelta(root, args["dry-run"] === true, config.root)
      : []),
  ];

  if (createUrlParam(args.preset, "authz") !== undefined) {
    lines.push("", AUTHZ_NOTE);
  }

  if (chosen !== null) {
    const presetConfig = resolveConfig(
      groupConfig({
        preset: chosen.value,
        casing,
        output: generated,
        ...designKeys(chosen.resolved, chosen.design),
        ...(workflow === "pg-delta" ? {} : { sql: { workflow } }),
      }),
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

  const install = (names: readonly string[], dev: boolean): string =>
    installCommand(project.packageManager, names, dev, installTarget);

  const next: NextStep[] = [
    ...(packages.length > 0
      ? [{ command: install(packages, false), when: "installs the packages" }]
      : []),
    ...devPackages(project, lite).map((names) => ({
      command: install(names, true),
      when: "installs the dev tools",
    })),
    ...(project.hasSupabase || workspaceProject.hasSupabase
      ? []
      : [
          {
            command: lite ? "npx lite init" : "supabase init",
            when: "creates the supabase folder",
          },
        ]),
    ...(lite
      ? [{ command: "npx lite dev", when: "starts the local stack" }]
      : [
          { command: "supabase start", when: "starts the local stack" },
          {
            command: `better-supabase env${cwdFlag}`,
            when: "writes the stack's keys to .env",
          },
        ]),
    {
      command: `better-supabase gen${cwdFlag}`,
      when: "generates the typed client",
    },
    {
      command: "better-supabase skills install",
      when: "installs the agent skills",
    },
  ];

  const hints = [
    ...(lite
      ? [
          'Before npx lite dev, set jwt_secret = "env(SUPABASE_JWT_SECRET)" under [auth] in supabase/config.toml, and add SUPABASE_URL=http://127.0.0.1:54321 and a SUPABASE_JWT_SECRET of 32 or more characters to .env',
          "Pass backend: 'lite' to createServer (or createNext, createHono, createEdge, createOrpc): https://bettersupabase.com/docs/platform/lite",
        ]
      : []),
    ...integrations.flatMap((name) => TEMPLATES[name].next ?? []),
  ];

  if (hints.length > 0) {
    lines.push("", ...hints.map((hint) => `- ${hint}`));
  }

  return {
    code: 0,
    output: lines.join("\n"),
    data: {
      frameworks: project.frameworks,
      ...(inPackage ? { package: target.dir } : {}),
      integrations,
      ...(chosen === null ? {} : { preset: chosen.value }),
      files: applied.changes,
      hints,
    },
    next,
  };
}

export const initCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("init"),
  args: { ...CONVENTION_ARGS, ...INIT_ARGS, ...PLAN_ARGS },
  lists: ["integration"],
  completions: { ...CONVENTION_COMPLETIONS, preset: () => PRESET_NAMES },
  run: (args, { config, io }) => runInit(config, args, io.prompts),
});

/** The `blocks` and `appTables` keys a design adds to the preset's config. */
function designKeys(
  resolved: ResolvedPreset,
  design: CreateDesign | undefined,
): Pick<FlatConfig, "appTables" | "blocks"> {
  if (design === undefined) {
    return {};
  }

  const { blocks, appTables } = designConfig(resolved, design);

  return { blocks, ...(appTables === undefined ? {} : { appTables }) };
}
