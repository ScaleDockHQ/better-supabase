import type { DoctorContext } from "./rules.ts";

import { adoptedTables } from "../../sql/index.ts";
import { appTablesOf } from "./app-tables.ts";
import { catalogOf, qualified } from "./shared.ts";

/** How one table relates to the blocks and to better-supabase's features. */
export type AdoptionStatus = "block" | "adopted" | "yours";

export interface AdoptionRow {
  readonly table: string;
  readonly status: AdoptionStatus;
  /** The block that created the table or runs over it. */
  readonly block?: string;
  /** The `tables.<name>` feature keys the config or an `@bsb` tag sets. */
  readonly features: readonly string[];
}

/**
 * One row per table in the read schemas: created by a block, one of yours that
 * a block runs over, or yours alone, with the features it has turned on (ADR
 * 0101).
 */
export function adoptionRows(context: DoctorContext): readonly AdoptionRow[] {
  const { config } = context;
  const own = appTablesOf(context);

  const adopted = new Map<string, string>(
    adoptedTables(config.blocks, own, { subjects: config.subjects }).map(
      (entry) => [`${entry.schema}.${entry.table}`, entry.module],
    ),
  );

  const created = new Map<string, string>();

  for (const table of catalogOf(context).tables) {
    const name = qualified(table);

    if (config.schemas.includes(table.schema) && own[name] === undefined) {
      created.set(name, table.name);
    }
  }

  return catalogOf(context)
    .tables.filter((table) => config.schemas.includes(table.schema))
    .map((table): AdoptionRow => {
      const name = qualified(table);
      const keys = config.appTables[table.name] ?? config.appTables[name];

      const features = keys === undefined ? [] : Object.keys(keys).toSorted();
      const block = adopted.get(name);

      if (created.has(name)) {
        return { table: name, status: "block", features };
      }

      return block === undefined
        ? { table: name, status: "yours", features }
        : { table: name, status: "adopted", block, features };
    })
    .toSorted((a, b) => a.table.localeCompare(b.table));
}

/** The rows as aligned text for `doctor --adoption`. */
export function adoptionText(rows: readonly AdoptionRow[]): string {
  if (rows.length === 0) {
    return "No tables in the read schemas.";
  }

  const label = (row: AdoptionRow): string =>
    row.status === "adopted" ? `adopted by ${row.block ?? ""}` : row.status;

  const width = Math.max(...rows.map((row) => row.table.length), 5);
  const status = Math.max(...rows.map((row) => label(row).length), 6);

  return [
    `${"Table".padEnd(width)}  ${"Status".padEnd(status)}  Features`,
    ...rows.map(
      (row) =>
        `${row.table.padEnd(width)}  ${label(row).padEnd(status)}  ${row.features.join(", ") || "-"}`,
    ),
  ].join("\n");
}
