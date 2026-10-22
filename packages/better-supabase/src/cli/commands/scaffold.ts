import { existsSync } from "node:fs";
import { resolve } from "node:path";

import type { ResolvedConfig, ScaffoldApiConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs, CliOptions } from "../core/command.ts";
import type { FilePlan } from "../core/files.ts";
import type { CommandResult } from "../core/io.ts";
import type { ScaffoldFramework } from "../scaffold/api.ts";

import { defineCliCommand, list } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import {
  applyPlan,
  hasConflicts,
  changeLines,
  PLAN_ARGS,
  planResult,
} from "../core/files.ts";
import { display } from "../core/io.ts";
import { commandMeta } from "../core/manifest.ts";
import { importFresh } from "../fresh-import.ts";
import { metaPaths } from "../gen/emit.ts";
import { isRecord } from "../guards.ts";
import { detectProject } from "../project/detect.ts";
import {
  SCAFFOLD_FRAMEWORKS,
  scaffoldApiFiles,
  scaffoldNextSteps,
} from "../scaffold/api.ts";
import { ScreensError, scaffoldScreensFiles } from "../scaffold/screens.ts";

const ARGS = {
  framework: {
    type: "string",
    description: "hono or next. Defaults to the one in package.json",
    valueHint: "name",
  },
  tables: {
    type: "string",
    description:
      "Tables to serve. Defaults to every table and view in the public schema",
    valueHint: "list",
  },
  name: {
    type: "string",
    description:
      "The API module's name: lib/<name>.ts and lib/<name>.generated.ts. Defaults to api",
    valueHint: "name",
  },
  "base-path": {
    type: "string",
    description: "Where the resources are served. Defaults to /api",
    valueHint: "path",
  },
} as const;

const SCREENS_ARGS = {
  table: {
    type: "positional",
    required: false,
    description: "The app table to write pages for",
  },
  framework: {
    type: "string",
    description: "next. Defaults to next when package.json lists it",
    valueHint: "name",
  },
  "base-path": {
    type: "string",
    description: "The route the pages live under. Defaults to /<table>",
    valueHint: "path",
  },
} as const;

export type ScaffoldArgs = CliArgs<typeof ARGS & typeof PLAN_ARGS>;

export type ScaffoldScreensFlags = CliOptions<
  typeof SCREENS_ARGS & typeof PLAN_ARGS
>;

export type ScaffoldFlags = CliOptions<typeof ARGS & typeof PLAN_ARGS>;

const isFramework = (value: unknown): value is ScaffoldFramework =>
  SCAFFOLD_FRAMEWORKS.some((framework) => framework === value);

/**
 * The public tables and views in the metadata module `gen` writes, or undefined
 * without one.
 */
async function generatedTables(
  config: ResolvedConfig,
): Promise<string[] | undefined> {
  const path = resolve(config.root, metaPaths(config.output).js);

  if (!existsSync(path)) {
    return undefined;
  }

  const meta = (await importFresh(path))["default"];
  const tables = isRecord(meta) ? meta["tables"] : undefined;

  if (!isRecord(tables)) {
    return undefined;
  }

  return Object.entries(tables)
    .filter(
      ([, table]) =>
        isRecord(table) &&
        table["schema"] === "public" &&
        (table["kind"] === "table" || table["kind"] === "view"),
    )
    .map(([key]) => key);
}

export interface ScaffoldOptions {
  /**
   * Writes only the generated file, never the module the app edits (the
   * `scaffold` step of `gen`).
   */
  readonly generatedOnly?: boolean;
  /** Compares the generated file instead of writing it. */
  readonly check?: boolean;
}

export async function runScaffoldApi(
  config: ResolvedConfig,
  args: ScaffoldFlags,
  options: ScaffoldOptions = {},
): Promise<CommandResult> {
  const configured = config.scaffold.api ?? {};
  const project = await detectProject(config.root);
  const detected = project.frameworks.filter(isFramework);
  const chosen = args.framework ?? configured.framework;
  const framework = chosen ?? (detected.length === 1 ? detected[0] : undefined);

  if (!isFramework(framework)) {
    throw new CliError(
      "usage",
      chosen === undefined
        ? "Pass --framework hono or --framework next, or set scaffold.api.framework."
        : `--framework takes hono or next, got "${chosen}".`,
    );
  }

  const name = args.name ?? configured.name ?? "api";

  if (!/^[a-z][\w-]*$/i.test(name)) {
    throw new CliError(
      "usage",
      `--name must be a file name without a folder, got "${name}".`,
    );
  }

  const basePath = `/${(args["base-path"] ?? configured.basePath ?? "/api").replaceAll(/^\/+|\/+$/g, "")}`;

  const known = await generatedTables(config);

  const requested =
    args.tables === undefined
      ? [...(configured.tables ?? [])]
      : list(args.tables);

  if (requested.length === 0 && !known) {
    return {
      code: 1,
      errorCode: "not_found",
      error: `No ${display(config.root, metaPaths(config.output).js)}. Run \`better-supabase gen\` first, or pass --tables.`,
    };
  }

  const unknown = known
    ? requested.filter((table) => !known.includes(table))
    : [];

  if (unknown.length > 0) {
    return {
      code: 1,
      error: `Unknown tables: ${unknown.join(", ")}. Known tables: ${known?.join(", ")}.`,
    };
  }

  const tables = requested.length > 0 ? requested : (known ?? []);

  if (tables.length === 0) {
    return {
      code: 1,
      error: "There are no public tables to serve. Pass --tables.",
    };
  }

  const context = {
    framework,
    srcDir: project.srcDir,
    tsExtensions: project.tsExtensions,
    name,
    basePath,
    tables,
  };

  const plan: FilePlan = {
    root: config.root,
    regenerate: "better-supabase scaffold api",
    files: scaffoldApiFiles(context)
      .filter((file) => options.generatedOnly !== true || file.generated)
      .map((file) => ({
        path: file.path,
        contents: file.contents,
        policy: file.generated ? "owned" : "create",
      })),
  };

  const applied = await applyPlan(plan, {
    ...args,
    ...(options.check === true ? { check: true } : {}),
  });

  const files = applied.changes;
  const lines = changeLines(applied);

  if (
    applied.mode !== "write" ||
    options.generatedOnly === true ||
    hasConflicts(applied)
  ) {
    return planResult(plan, applied, { data: { framework, tables } });
  }

  const steps = scaffoldNextSteps(context, config.specs.entry);

  const save =
    config.scaffold.api === undefined
      ? [
          "",
          "Add this to your config so `better-supabase gen` keeps the generated file current:",
          `  scaffold: { api: ${scaffoldSnippet({
            framework,
            ...(name === "api" ? {} : { name }),
            ...(basePath === "/api" ? {} : { basePath }),
            ...(requested.length > 0 ? { tables: requested } : {}),
          })} }`,
        ]
      : [];

  return {
    code: 0,
    output: [
      ...lines,
      "",
      "Next:",
      ...steps.map((step) => `- ${step}`),
      ...save,
    ].join("\n"),
    data: { framework, tables, files, steps },
  };
}

/** Writes list, create and detail pages for one app table, each once. */
export async function runScaffoldScreens(
  config: ResolvedConfig,
  args: ScaffoldScreensFlags,
): Promise<CommandResult> {
  const { table } = args;

  if (table === undefined) {
    throw new CliError(
      "usage",
      "Name the app table: `better-supabase scaffold screens <table>`.",
    );
  }

  const project = await detectProject(config.root);

  const framework =
    args.framework ??
    (project.frameworks.includes("next") ? "next" : undefined);

  if (framework !== "next") {
    throw new CliError(
      "usage",
      framework === undefined
        ? "Screens are Next.js pages, and package.json has no next. Pass --framework next."
        : `Screens are Next.js pages; --framework ${framework} has none.`,
    );
  }

  const basePath = `/${(args["base-path"] ?? table).replaceAll(/^\/+|\/+$/g, "")}`;
  let files;

  try {
    files = scaffoldScreensFiles({
      config,
      table,
      srcDir: project.srcDir,
      tsExtensions: project.tsExtensions,
      basePath,
    });
  } catch (error) {
    if (error instanceof ScreensError) {
      return { code: 1, errorCode: "invalid_input", error: error.message };
    }

    throw error;
  }

  const plan: FilePlan = {
    root: config.root,
    regenerate: "better-supabase scaffold screens",
    files: files.map((file) => ({
      path: file.path,
      contents: file.contents,
      policy: "create",
    })),
  };

  const applied = await applyPlan(plan, args);

  if (applied.mode !== "write" || hasConflicts(applied)) {
    return planResult(plan, applied, { data: { table, basePath } });
  }

  const steps = [
    `Open ${basePath} in \`next dev\`. The pages call \`bsb\` from lib/supabase/server; \`better-supabase add next\` writes it if you don't have one.`,
    "The files are yours. For search, saved views, a board or a calendar, start from the record-* recipes: https://bettersupabase.com/docs/registry/ui-recipes",
  ];

  return {
    code: 0,
    output: [
      ...changeLines(applied),
      "",
      "Next:",
      ...steps.map((step) => `- ${step}`),
    ].join("\n"),
    data: { table, basePath, files: applied.changes, steps },
  };
}

const quote = (value: string): string => `'${value}'`;

const scaffoldSnippet = (api: ScaffoldApiConfig): string =>
  `{ ${Object.entries(api)
    .map(
      ([key, value]: [string, string | readonly string[]]) =>
        `${key}: ${typeof value === "string" ? quote(value) : `[${value.map(quote).join(", ")}]`}`,
    )
    .join(", ")} }`;

export const scaffoldApiCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("scaffold api"),
  args: { ...ARGS, ...PLAN_ARGS },
  lists: ["tables"],
  run: (args, { config }) => runScaffoldApi(config, args),
});

export const scaffoldScreensCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("scaffold screens"),
  args: { ...SCREENS_ARGS, ...PLAN_ARGS },
  run: (args, { config }) => runScaffoldScreens(config, args),
});
