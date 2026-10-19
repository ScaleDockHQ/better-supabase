import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig, ScaffoldApiConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs, CliOptions } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { ScaffoldFramework } from "../scaffold/api.ts";

import { defineCliCommand, list } from "../core/command.ts";
import { writeLine } from "../core/files.ts";
import { display, sameText } from "../core/io.ts";
import { fileDiff } from "../diff.ts";
import { importFresh } from "../fresh-import.ts";
import { metaPaths } from "../gen/emit.ts";
import { isRecord } from "../guards.ts";
import { detectProject } from "../project/detect.ts";
import {
  GENERATED_HEADER,
  SCAFFOLD_FRAMEWORKS,
  scaffoldApiFiles,
  scaffoldNextSteps,
} from "../scaffold/api.ts";
import { ScreensError, scaffoldScreensFiles } from "../scaffold/screens.ts";

const ARGS = {
  kind: {
    type: "positional",
    required: false,
    description: "api, or screens <table>",
  },
  table: {
    type: "positional",
    required: false,
    description: "The app table `scaffold screens` writes pages for",
  },
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
    description:
      "Where the resources are served (default /api), or the route the screens live under (default /<table>)",
    valueHint: "path",
  },
} as const;

export type ScaffoldArgs = CliArgs<typeof ARGS>;

export type ScaffoldFlags = CliOptions<typeof ARGS>;

const isFramework = (value: unknown): value is ScaffoldFramework =>
  SCAFFOLD_FRAMEWORKS.some((framework) => framework === value);

/** The public tables and views in the metadata module `gen` writes, or undefined without one. */
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
  /** Writes only the generated file, never the module the app edits (the `scaffold` step of `gen`). */
  readonly generatedOnly?: boolean;
  /** Compares the generated file instead of writing it. */
  readonly check?: boolean;
}

export async function runScaffold(
  config: ResolvedConfig,
  args: ScaffoldFlags,
  options: ScaffoldOptions = {},
): Promise<CommandResult> {
  const [kind, table] = args._ ?? [];

  if (kind === "screens") {
    return runScaffoldScreens(config, args, table);
  }

  if (kind !== "api") {
    return {
      code: 2,
      error: `${kind ? `Unknown scaffold "${kind}"` : "Name what to scaffold"}. Run \`better-supabase scaffold api\` or \`better-supabase scaffold screens <table>\`.`,
    };
  }

  const configured = config.scaffold.api ?? {};
  const project = await detectProject(config.root);
  const detected = project.frameworks.filter(isFramework);
  const chosen = args.framework ?? configured.framework;
  const framework = chosen ?? (detected.length === 1 ? detected[0] : undefined);

  if (!isFramework(framework)) {
    return {
      code: 2,
      error:
        chosen === undefined
          ? "Pass --framework hono or --framework next, or set scaffold.api.framework."
          : `--framework takes hono or next, got "${chosen}".`,
    };
  }

  const name = args.name ?? configured.name ?? "api";

  if (!/^[a-z][\w-]*$/i.test(name)) {
    return {
      code: 2,
      error: `--name must be a file name without a folder, got "${name}".`,
    };
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

  const lines: string[] = [];
  const stale: string[] = [];
  const diffs: string[] = [];

  for (const file of scaffoldApiFiles(context)) {
    if (options.generatedOnly === true && !file.generated) {
      continue;
    }

    const path = resolve(config.root, file.path);
    const exists = existsSync(path);

    if (!file.generated && exists) {
      lines.push(`Kept ${file.path} (yours)`);
      continue;
    }

    const current = exists ? await readFile(path, "utf-8") : undefined;

    if (current !== undefined && !current.startsWith(GENERATED_HEADER)) {
      return {
        code: 1,
        error: `${file.path} was not written by better-supabase scaffold. Move it, or pass another --name.`,
      };
    }

    if (options.check === true) {
      if (sameText(current, file.contents)) {
        lines.push(`${file.path} is up to date.`);
      } else {
        stale.push(file.path);
        diffs.push(fileDiff(file.path, current, file.contents));
      }

      continue;
    }

    lines.push((await writeLine(path, file.contents, file.path)).line);
  }

  if (stale.length > 0) {
    return {
      code: 1,
      output: diffs.join("\n"),
      error: `Out of date: ${stale.join(", ")}. Run \`better-supabase scaffold api\`.`,
    };
  }

  if (options.generatedOnly === true || options.check === true) {
    return { code: 0, output: lines.join("\n") };
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
  };
}

/** Writes list, create and detail pages for one app table, each once. */
async function runScaffoldScreens(
  config: ResolvedConfig,
  args: ScaffoldFlags,
  table: string | undefined,
): Promise<CommandResult> {
  if (table === undefined) {
    return {
      code: 2,
      error: "Name the app table: `better-supabase scaffold screens <table>`.",
    };
  }

  const project = await detectProject(config.root);

  const framework =
    args.framework ??
    (project.frameworks.includes("next") ? "next" : undefined);

  if (framework !== "next") {
    return {
      code: 2,
      error:
        framework === undefined
          ? "Screens are Next.js pages, and package.json has no next. Pass --framework next."
          : `Screens are Next.js pages; --framework ${framework} has none.`,
    };
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
      return { code: 1, error: error.message };
    }

    throw error;
  }

  const lines: string[] = [];

  for (const file of files) {
    const path = resolve(config.root, file.path);

    if (existsSync(path)) {
      lines.push(`Kept ${file.path} (yours)`);
      continue;
    }

    lines.push((await writeLine(path, file.contents, file.path)).line);
  }

  return {
    code: 0,
    output: [
      ...lines,
      "",
      "Next:",
      `- Open ${basePath} in \`next dev\`. The pages call \`bs\` from lib/supabase/server; \`better-supabase add next\` writes it if you don't have one.`,
      "- The files are yours. For search, saved views, a board or a calendar, start from the record-* recipes: https://bettersupabase.com/docs/registry/ui-recipes",
    ].join("\n"),
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

export const scaffoldCommand: AnyCommand = defineCliCommand({
  meta: {
    name: "scaffold",
    description:
      "Writes an API module and its routes for Hono or Next.js, or list, create and detail pages for an app table",
  },
  args: ARGS,
  lists: ["tables"],
  run: (args, { config }) => runScaffold(config, args),
});
