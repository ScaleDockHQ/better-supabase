import { readdir, readFile } from "node:fs/promises";
import { join, relative } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../core/command.ts";
import type { FilePlan } from "../core/files.ts";
import type { CommandResult } from "../core/io.ts";
import type { Paint } from "../style.ts";

import {
  createsTable,
  isTableFeature,
  setTableFeature,
  TABLE_FEATURES,
} from "../../sql/index.ts";
import { defineCliCommand } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import { applyPlan, PLAN_ARGS, planResult } from "../core/files.ts";
import { display } from "../core/io.ts";
import { commandMeta } from "../core/manifest.ts";
import { plain } from "../style.ts";
import { supabaseDir } from "../supabase-toml.ts";

const TABLE_ARGS = {
  table: {
    type: "positional",
    required: true,
    description: "The table, as name or schema.name",
  },
  action: {
    type: "positional",
    required: true,
    description: "enable or disable",
  },
  feature: {
    type: "positional",
    required: true,
    description:
      "The feature: realtime, audit, audit-reads, subject, json, expose, encrypted, events or vector-search",
  },
} as const;

export type TableArgs = CliArgs<
  typeof TABLE_ARGS & Pick<typeof PLAN_ARGS, "dry-run" | "check">
>;

/** What `runTable` reads from outside. */
export interface TableDeps {
  readonly paint?: Paint;
}

async function sqlFiles(dir: string): Promise<string[]> {
  const entries = await readdir(dir, { withFileTypes: true }).catch(() => []);

  const nested = await Promise.all(
    entries.map(async (entry) =>
      entry.isDirectory()
        ? sqlFiles(join(dir, entry.name))
        : entry.name.endsWith(".sql")
          ? [join(dir, entry.name)]
          : [],
    ),
  );

  return nested.flat().toSorted();
}

/**
 * Turns a per-table feature on or off by editing the `@bsb` tag in the table's
 * comment, in the file under `supabase/schemas` that creates the table (ADR
 * 0102). Nothing else in the file changes; `db diff` then writes the
 * migration.
 */
export async function runTable(
  config: ResolvedConfig,
  args: TableArgs,
  deps: TableDeps = {},
): Promise<CommandResult> {
  const { action, feature } = args;

  if (action !== "enable" && action !== "disable") {
    throw new CliError("usage", `Expected enable or disable, got ${action}.`);
  }

  if (!isTableFeature(feature)) {
    throw new CliError(
      "usage",
      `Unknown feature ${feature}. Use one of ${TABLE_FEATURES.join(", ")}.`,
    );
  }

  const [schema, name] = args.table.includes(".")
    ? args.table.split(".", 2)
    : ["public", args.table];

  if (schema === undefined || name === undefined || name === "") {
    throw new CliError("usage", `Expected a table, got ${args.table}.`);
  }

  const dir = join(config.root, supabaseDir(config.root), "schemas");
  const files = await sqlFiles(dir);
  const matches: { readonly path: string; readonly text: string }[] = [];

  for (const path of files) {
    const text = await readFile(path, "utf-8");

    if (createsTable(text, schema, name)) {
      matches.push({ path, text });
    }
  }

  const [found, ...others] = matches;

  if (found === undefined) {
    throw new CliError(
      "usage",
      `No file under ${display(config.root, dir)} creates ${schema}.${name}. Tables you own live in supabase/schemas; add the table there first.`,
    );
  }

  if (others.length > 0) {
    throw new CliError(
      "usage",
      `${schema}.${name} is created in ${String(matches.length)} files: ${matches
        .map((match) => relative(config.root, match.path))
        .join(", ")}. Keep one.`,
    );
  }

  const next = setTableFeature(
    found.text,
    schema,
    name,
    feature,
    action === "enable",
  );

  const plan: FilePlan = {
    root: config.root,
    regenerate: `better-supabase table ${args.table} ${action} ${feature}`,
    files: [{ path: found.path, contents: next, policy: "edit" }],
  };

  const applied = await applyPlan(plan, args, deps.paint ?? plain);

  const summary =
    applied.mode === "write" && applied.drift
      ? `${action === "enable" ? "Enabled" : "Disabled"} ${feature} on ${schema}.${name}. Run \`better-supabase db diff -f ${feature}_${name}\` for the migration.`
      : undefined;

  const data = {
    table: `${schema}.${name}`,
    feature,
    enabled: action === "enable",
  };

  return planResult(plan, applied, {
    data,
    ...(summary === undefined ? {} : { summary }),
  });
}

export const tableCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("table"),
  args: {
    ...TABLE_ARGS,
    "dry-run": PLAN_ARGS["dry-run"],
    check: PLAN_ARGS.check,
  },
  run: (args, { config, paint }) => runTable(config, args, { paint }),
});
