import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../command.ts";
import type { CommandResult } from "../io.ts";
import type { ScaffoldFramework } from "../scaffold/api.ts";

import { defineCliCommand, list } from "../command.ts";
import { importFresh } from "../fresh-import.ts";
import { metaPaths } from "../gen/emit.ts";
import { display, writeIfChanged } from "../io.ts";
import { detectProject } from "../project.ts";
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

const isFramework = (value: unknown): value is ScaffoldFramework =>
  SCAFFOLD_FRAMEWORKS.some((framework) => framework === value);

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** The public tables and views in the metadata module `gen` writes, or undefined without one. */
async function generatedTables(
  config: ResolvedConfig,
): Promise<string[] | undefined> {
  const path = resolve(config.root, metaPaths(config.output).js);
  if (!existsSync(path)) return undefined;
  const meta = (await importFresh(path))["default"];
  const tables = isRecord(meta) ? meta["tables"] : undefined;
  if (!isRecord(tables)) return undefined;
  return Object.entries(tables)
    .filter(
      ([, table]) =>
        isRecord(table) &&
        table["schema"] === "public" &&
        (table["kind"] === "table" || table["kind"] === "view"),
    )
    .map(([key]) => key);
}

export async function runScaffold(
  config: ResolvedConfig,
  args: ScaffoldArgs,
): Promise<CommandResult> {
  const [kind] = args._;
  if (kind !== "api")
    return {
      code: 2,
      error: `${kind ? `Unknown scaffold "${kind}"` : "Name what to scaffold"}. Run \`better-supabase scaffold api\`.`,
    };
  const project = await detectProject(config.root);
  const detected = project.frameworks.filter(isFramework);
  const framework =
    args.framework ?? (detected.length === 1 ? detected[0] : undefined);
  if (!isFramework(framework))
    return {
      code: 2,
      error:
        args.framework === undefined
          ? "Pass --framework hono or --framework next."
          : `--framework takes hono or next, got "${args.framework}".`,
    };
  const name = args.name ?? "api";
  if (!/^[a-z][\w-]*$/i.test(name))
    return {
      code: 2,
      error: `--name must be a file name without a folder, got "${name}".`,
    };
  const basePath = `/${(args["base-path"] ?? "/api").replaceAll(/^\/+|\/+$/g, "")}`;

  const known = await generatedTables(config);
  const requested = list(args.tables);
  if (requested.length === 0 && !known)
    return {
      code: 1,
      error: `No ${display(config.root, metaPaths(config.output).js)}. Run \`better-supabase gen\` first, or pass --tables.`,
    };
  const unknown = known
    ? requested.filter((table) => !known.includes(table))
    : [];
  if (unknown.length > 0)
    return {
      code: 1,
      error: `Unknown tables: ${unknown.join(", ")}. Known tables: ${known?.join(", ")}.`,
    };
  const tables = requested.length > 0 ? requested : (known ?? []);
  if (tables.length === 0)
    return {
      code: 1,
      error: "There are no public tables to serve. Pass --tables.",
    };

  const context = {
    framework,
    srcDir: project.srcDir,
    tsExtensions: project.tsExtensions,
    name,
    basePath,
    tables,
  };
  const lines: string[] = [];
  for (const file of scaffoldApiFiles(context)) {
    const path = resolve(config.root, file.path);
    const exists = existsSync(path);
    if (!file.generated && exists) {
      lines.push(`Kept ${file.path} (yours)`);
      continue;
    }
    if (file.generated && exists) {
      const current = await readFile(path, "utf8");
      if (!current.startsWith(GENERATED_HEADER))
        return {
          code: 1,
          error: `${file.path} was not written by better-supabase scaffold. Move it, or pass another --name.`,
        };
    }
    const wrote = await writeIfChanged(path, file.contents);
    lines.push(`${wrote ? "Wrote" : "Unchanged"} ${file.path}`);
  }
  const steps = scaffoldNextSteps(context, config.specs.entry);
  return {
    code: 0,
    output: [...lines, "", "Next:", ...steps.map((step) => `- ${step}`)].join(
      "\n",
    ),
  };
}

export const scaffoldCommand: AnyCommand = defineCliCommand({
  meta: {
    name: "scaffold",
    description:
      "Writes an API module, its resource routes and an OpenAPI route for Hono or Next.js",
  },
  args: ARGS,
  lists: ["tables"],
  run: (args, { config }) => runScaffold(config, args),
});
