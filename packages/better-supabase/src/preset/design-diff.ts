import type {
  AppColumnConfig,
  AppTableConfig,
  AppTablesConfig,
} from "../config/types/app-tables.ts";
import type { CreateDesign } from "./design.ts";

/** What changed between two sets of app tables. */
export type DesignChangeKind =
  | "table.added"
  | "table.dropped"
  | "table.renamed"
  | "table.id"
  | "table.changed"
  | "table.computed"
  | "column.added"
  | "column.dropped"
  | "column.renamed"
  | "column.type"
  | "column.required"
  | "column.changed";

export interface DesignChange {
  readonly kind: DesignChangeKind;
  readonly table: string;
  readonly column?: string;
  /** The old name of a renamed table or column, or the old type. */
  readonly from?: string;
  /** The new type of a type change. */
  readonly to?: string;
  /**
   * True when existing rows or app code can break: a dropped or renamed
   * table or column, a type change, or a column made required without a
   * default.
   */
  readonly breaking: boolean;
  readonly summary: string;
  /** The expand-and-contract steps that make a breaking change safe. */
  readonly steps: readonly string[];
}

export interface DiffOptions {
  /**
   * Leave out tables that `after` doesn't have, as `apply` does: it writes
   * the tables of a design and keeps the others.
   */
  readonly keepMissing?: boolean;
}

/** `value` as JSON with sorted keys, so two configs compare by content. */
function canonical(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(canonical).join(",")}]`;
  }

  if (value !== null && typeof value === "object") {
    const entries = Object.entries(value)
      .filter(([, each]) => each !== undefined)
      .toSorted(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));

    return `{${entries.map(([key, each]) => `${JSON.stringify(key)}:${canonical(each)}`).join(",")}}`;
  }

  return JSON.stringify(value);
}

const same = (a: unknown, b: unknown): boolean => canonical(a) === canonical(b);

const isRequired = (column: AppColumnConfig): boolean =>
  column.nullable === false;

const lacksDefault = (column: AppColumnConfig): boolean =>
  column.default === undefined && column.identity !== true;

const safe = (
  kind: DesignChangeKind,
  table: string,
  summary: string,
  column?: string,
): DesignChange => ({
  kind,
  table,
  ...(column === undefined ? {} : { column }),
  breaking: false,
  summary,
  steps: [],
});

const columnsOf = (
  table: AppTableConfig,
): Readonly<Record<string, AppColumnConfig>> => table.columns ?? {};

/**
 * Pairs each name only in `before` with a name only in `after` whose value
 * is the same: a rename, as far as a config can tell.
 */
function renames<T>(
  before: Readonly<Record<string, T>>,
  after: Readonly<Record<string, T>>,
): ReadonlyMap<string, string> {
  const added = Object.keys(after).filter((name) => !(name in before));
  const paired = new Map<string, string>();

  for (const [name, value] of Object.entries(before)) {
    if (name in after) {
      continue;
    }

    const match = added.find(
      (candidate) =>
        ![...paired.values()].includes(candidate) &&
        same(value, after[candidate]),
    );

    if (match !== undefined) {
      paired.set(name, match);
    }
  }

  return paired;
}

function columnChanges(
  table: string,
  before: AppTableConfig,
  after: AppTableConfig,
): DesignChange[] {
  const old = columnsOf(before);
  const next = columnsOf(after);
  const renamed = renames(old, next);
  const renamedTo = new Set(renamed.values());
  const changes: DesignChange[] = [];

  for (const [name, column] of Object.entries(old)) {
    const to = renamed.get(name);
    const now = next[name];

    if (to !== undefined) {
      changes.push({
        kind: "column.renamed",
        table,
        column: to,
        from: name,
        breaking: true,
        summary: `Renames ${table}.${name} to ${to}.`,
        steps: [
          `Add ${to} as a nullable column and copy ${name} into it in a migration.`,
          `Write both columns and move reads to ${to}, then deploy.`,
          `Drop ${name} in a later migration${isRequired(column) ? `, then make ${to} required` : ""}.`,
        ],
      });
    } else if (now === undefined) {
      changes.push({
        kind: "column.dropped",
        table,
        column: name,
        breaking: true,
        summary: `Drops ${table}.${name} and its values.`,
        steps: [
          `Stop reading and writing ${table}.${name} in the app, then deploy.`,
          `Export the values first if you need them.`,
          `Remove the column and generate the migration that drops it.`,
        ],
      });
    } else if (now.type !== column.type) {
      changes.push({
        kind: "column.type",
        table,
        column: name,
        from: column.type,
        to: now.type,
        breaking: true,
        summary: `Changes ${table}.${name} from ${column.type} to ${now.type}.`,
        steps: [
          `Add a ${now.type} column next to ${name}.`,
          `Fill it from ${name} with a cast in a migration, and write both columns.`,
          `Move reads to the new column, drop ${name} in a later migration and rename the new one if you need the name.`,
        ],
      });
    } else if (!isRequired(column) && isRequired(now) && lacksDefault(now)) {
      changes.push({
        kind: "column.required",
        table,
        column: name,
        breaking: true,
        summary: `Makes ${table}.${name} required without a default.`,
        steps: [
          `Fill ${table}.${name} in every row where it is null, in a migration.`,
          `Make the app always write it, or give it a default, then deploy.`,
          `Make the column required.`,
        ],
      });
    } else if (!same(column, now)) {
      changes.push(
        safe("column.changed", table, `Changes ${table}.${name}.`, name),
      );
    }
  }

  for (const [name, column] of Object.entries(next)) {
    if (name in old || renamedTo.has(name)) {
      continue;
    }

    changes.push(
      isRequired(column) && lacksDefault(column)
        ? {
            kind: "column.added",
            table,
            column: name,
            breaking: true,
            summary: `Adds ${table}.${name} as required without a default, which rows already in the table don't have.`,
            steps: [
              `Add ${name} as a nullable column.`,
              `Fill it in every existing row, and make the app always write it, then deploy.`,
              `Make the column required.`,
            ],
          }
        : safe("column.added", table, `Adds ${table}.${name}.`, name),
    );
  }

  return changes;
}

/**
 * What changes from `before` to `after`: each added, dropped, renamed or
 * changed table and column, with the breaking ones marked and their
 * expand-and-contract steps. A rename is a dropped name and an added one
 * with the same definition.
 */
export function diffAppTables(
  before: AppTablesConfig,
  after: AppTablesConfig,
  options: DiffOptions = {},
): readonly DesignChange[] {
  const old =
    options.keepMissing === true
      ? Object.fromEntries(
          Object.entries(before).filter(([name]) => name in after),
        )
      : before;

  const renamed = renames(old, after);
  const renamedTo = new Set(renamed.values());
  const changes: DesignChange[] = [];

  for (const [name, table] of Object.entries(old)) {
    const to = renamed.get(name);
    const now = after[name];

    if (to !== undefined) {
      changes.push({
        kind: "table.renamed",
        table: to,
        from: name,
        breaking: true,
        summary: `Renames table ${name} to ${to}.`,
        steps: [
          `Add ${to} next to ${name} and copy the rows in a migration.`,
          `Write to both tables and move reads to ${to}, then deploy.`,
          `Stop using ${name}, then drop it in a later migration.`,
        ],
      });
    } else if (now === undefined) {
      changes.push({
        kind: "table.dropped",
        table: name,
        breaking: true,
        summary: `Drops table ${name} and its rows.`,
        steps: [
          `Stop reading and writing ${name} in the app, then deploy.`,
          `Export the rows first if you need them.`,
          `Remove the table and generate the migration that drops it.`,
        ],
      });
    } else {
      const from = table.id ?? "uuid";
      const toId = now.id ?? "uuid";

      if (from !== toId) {
        changes.push({
          kind: "table.id",
          table: name,
          from,
          to: toId,
          breaking: true,
          summary: `Changes the id of ${name} from ${from} to ${toId}.`,
          steps: [
            `Add a table with the ${toId} id and copy the rows, keeping a map from old ids to new ones.`,
            `Point the columns that reference ${name} at the new ids, then move the app to the new table.`,
            `Drop the old table in a later migration.`,
          ],
        });
      }

      changes.push(...columnChanges(name, table, now));

      const rest = (config: AppTableConfig): unknown => ({
        ...config,
        columns: undefined,
        id: undefined,
        rollups: undefined,
        lookups: undefined,
      });

      if (!same(rest(table), rest(now))) {
        changes.push(safe("table.changed", name, `Changes table ${name}.`));
      }

      const computed = (config: AppTableConfig): unknown => ({
        rollups: config.rollups,
        lookups: config.lookups,
      });

      // The view keeps no rows and is created again on every sync.
      if (!same(computed(table), computed(now))) {
        changes.push(
          safe(
            "table.computed",
            name,
            `Changes the rollups and lookups of ${name}, read through ${name}_view.`,
          ),
        );
      }
    }
  }

  for (const name of Object.keys(after)) {
    if (!(name in old) && !renamedTo.has(name)) {
      changes.push(safe("table.added", name, `Adds table ${name}.`));
    }
  }

  return changes;
}

/** `diffAppTables` over the app tables of two `/create` designs. */
export function diffDesigns(
  before: CreateDesign,
  after: CreateDesign,
): readonly DesignChange[] {
  return diffAppTables(before.appTables ?? {}, after.appTables ?? {});
}
