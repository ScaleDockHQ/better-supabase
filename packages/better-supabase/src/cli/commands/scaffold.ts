import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig, ScaffoldApiConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs, CliOptions } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { ScaffoldFramework } from "../scaffold/api.ts";

import { defineCliCommand, list } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import { writeLine } from "../core/files.ts";
import { display, sameText } from "../core/io.ts";
import { commandMeta } from "../core/manifest.ts";
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

const ARGS = {
  kind: {
    type: "positional",
    required: false,
    description: "api",
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
    description: "Where the resources are served. Defaults to /api",
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
  const [kind] = args._ ?? [];

  if (kind !== "api") {
    throw new CliError(
      "usage",
      `${kind ? `Unknown scaffold "${kind}"` : "Name what to scaffold"}. Run \`better-supabase scaffold api\`.`,
    );
  }

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

  const lines: string[] = [];

  const files: { path: string; action: "kept" | "written" | "unchanged" }[] =
    [];

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
      files.push({ path: file.path, action: "kept" });
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
        files.push({ path: file.path, action: "unchanged" });
      } else {
        stale.push(file.path);
        diffs.push(fileDiff(file.path, current, file.contents));
      }

      continue;
    }

    const { line, wrote } = await writeLine(path, file.contents, file.path);
    lines.push(line);
    files.push({ path: file.path, action: wrote ? "written" : "unchanged" });
  }

  if (stale.length > 0) {
    return {
      code: 1,
      output: diffs.join("\n"),
      data: { framework, tables, files, stale },
      error: `Out of date: ${stale.join(", ")}. Run \`better-supabase scaffold api\`.`,
      errorCode: "check_failed",
    };
  }

  if (options.generatedOnly === true || options.check === true) {
    return {
      code: 0,
      output: lines.join("\n"),
      data: { framework, tables, files, stale },
    };
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
    data: { framework, tables, files, stale, steps },
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
  meta: commandMeta("scaffold"),
  args: ARGS,
  lists: ["tables"],
  run: (args, { config }) => runScaffold(config, args),
});
