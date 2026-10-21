import type { DoctorContext, FindingInput } from "./rules.ts";

import { catalogOf, qualified, tableObject } from "./shared.ts";

const escapeRegExp = (value: string): string =>
  value.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");

export interface Exemption {
  readonly glob: string;
  readonly reason: string | undefined;
}

/** `exempt` entries: a glob, or `{ table, reason }` where `table` is a glob. */
function exemptions(value: unknown): Exemption[] {
  const entries: unknown[] = Array.isArray(value) ? value : [];

  return entries.flatMap((entry): Exemption[] => {
    if (typeof entry === "string") {
      return [{ glob: entry, reason: undefined }];
    }

    if (
      typeof entry === "object" &&
      entry !== null &&
      "table" in entry &&
      typeof entry.table === "string"
    ) {
      const reason =
        "reason" in entry && typeof entry.reason === "string"
          ? entry.reason.trim()
          : "";

      return [
        { glob: entry.table, reason: reason === "" ? undefined : reason },
      ];
    }

    return [];
  });
}

/** `exempt` globs (`public.*_archive`): `*` matches any run of characters. */
export const globs = (value: unknown): RegExp[] =>
  (Array.isArray(value) ? value : [])
    .filter((entry): entry is string => typeof entry === "string")
    .map(
      (glob) =>
        new RegExp(`^${glob.split("*").map(escapeRegExp).join(".*")}$`, "i"),
    );

/**
 * The module schemas and the app tables SQL modules adopted, which the audit
 * trigger skips.
 */
export function moduleOwned(context: DoctorContext): {
  schemas: ReadonlySet<string>;
  tables: ReadonlySet<string>;
} {
  const schemas = new Set<string>(["better_supabase"]);
  const tables = new Set<string>();

  for (const module of Object.values(context.config.blocks)) {
    if (module?.schema !== undefined) {
      schemas.add(module.schema);
    }

    for (const table of Object.values(module?.tables ?? {})) {
      if (table === null || table === undefined) {
        continue;
      }

      tables.add(
        table.includes(".")
          ? table
          : `${module?.schema ?? "better_supabase"}.${table}`,
      );
    }
  }

  return { schemas, tables };
}

/**
 * Tables in `config.schemas` without the `bs_audit` trigger, when `audit` is in
 * `blocks`, and exemptions that give no reason.
 */
export function unauditedTables(context: DoctorContext): FindingInput[] {
  if (!context.config.blockNames.includes("audit")) {
    return [];
  }

  const entries = exemptions(
    context.config.blocks["audit"]?.options?.["exempt"],
  );

  const exempt = globs(entries.map((entry) => entry.glob));
  const owned = moduleOwned(context);

  const unaudited = catalogOf(context)
    .tables.filter(
      (table) =>
        table.kind === "table" &&
        table.partitionOf === undefined &&
        context.config.schemas.includes(table.schema) &&
        !owned.schemas.has(table.schema) &&
        !owned.tables.has(qualified(table)) &&
        !exempt.some((pattern) => pattern.test(qualified(table))) &&
        !table.triggers.some(
          (trigger) =>
            trigger.name.startsWith("bs_audit") ||
            trigger.function.split(".").at(-1) === "audit_row_change",
        ),
    )
    .map((table) => ({
      message: `${qualified(table)} has no audit trigger, so its inserts, updates and deletes are not in the audit log. Run \`select better_supabase.audit('${qualified(table)}')\` in a schema file, or list it in blocks.audit.options.exempt as \`{ table: '${qualified(table)}', reason: '...' }\`.`,
      target: qualified(table),
      object: tableObject(table),
    }));

  const unexplained = entries
    .filter((entry) => entry.reason === undefined)
    .map((entry) => ({
      message: `blocks.audit.options.exempt lists ${entry.glob} without a reason. Write it as { table: '${entry.glob}', reason: 'why its changes need no audit entry' } so a reviewer can tell an intended gap from a forgotten table.`,
      target: `blocks.audit.options.exempt:${entry.glob}`,
    }));

  return [...unaudited, ...unexplained];
}
