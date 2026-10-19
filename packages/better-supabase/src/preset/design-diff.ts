import type {
  AppColumnConfig,
  AppTableConfig,
  AppTablesConfig,
} from "../config/types/app-tables.ts";
import type { CreateDesign } from "./design.ts";

import { FIELD_FORMATS } from "../core/contracts/field-formats.ts";

/** What changed between two sets of app tables. */
export type DesignChangeKind =
  | "table.added"
  | "table.dropped"
  | "table.renamed"
  | "table.id"
  | "table.scope"
  | "table.unique"
  | "table.columns"
  | "table.changed"
  | "table.computed"
  | "column.added"
  | "column.dropped"
  | "column.renamed"
  | "column.type"
  | "column.required"
  | "column.unique"
  | "column.options"
  | "column.bounds"
  | "column.format"
  | "column.reference"
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
   * table or column, a type change, a column made required without a
   * default, a new or tighter constraint (unique, options, bounds, format,
   * a reference target), a new scope, or removed generated columns.
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

const breakingChange = (
  kind: DesignChangeKind,
  table: string,
  summary: string,
  steps: readonly string[],
  column?: string,
): DesignChange => ({
  kind,
  table,
  ...(column === undefined ? {} : { column }),
  breaking: true,
  summary,
  steps,
});

/** The steps that make a new check or constraint safe on rows that may not pass it. */
const checkSteps = (target: string, rule: string): readonly string[] => [
  `Find the rows where ${target} doesn't ${rule}, and fix them in a migration.`,
  `Make the app write only values that ${rule}, then deploy.`,
  `Add the constraint.`,
];

const targetOf = (reference: AppColumnConfig["references"]): string =>
  reference === undefined
    ? ""
    : "block" in reference
      ? `${reference.block}.${reference.table}`
      : reference.table;

/**
 * The changes to one column whose name and type stay: each new or tighter
 * constraint is breaking, because rows already in the table may not pass
 * it; anything else (a comment, a default, `onDelete`, a looser rule) is safe.
 */
function constraintChanges(
  table: string,
  name: string,
  before: AppColumnConfig,
  after: AppColumnConfig,
): DesignChange[] {
  const at = `${table}.${name}`;
  const changes: DesignChange[] = [];

  if (before.unique !== true && after.unique === true) {
    changes.push(
      breakingChange(
        "column.unique",
        table,
        `Makes ${at} unique, which fails while two rows share a value.`,
        checkSteps(at, "repeat a value"),
        name,
      ),
    );
  }

  const removed =
    after.options === undefined
      ? []
      : before.options === undefined
        ? after.options
        : before.options.filter((option) => !after.options?.includes(option));

  if (after.options !== undefined && removed.length > 0) {
    changes.push(
      breakingChange(
        "column.options",
        table,
        before.options === undefined
          ? `Limits ${at} to ${after.options.join(", ")}.`
          : `Removes ${removed.join(", ")} from the options of ${at}.`,
        checkSteps(at, `hold one of ${after.options.join(", ")}`),
        name,
      ),
    );
  }

  const raised =
    after.min !== undefined &&
    (before.min === undefined || after.min > before.min);

  const lowered =
    after.max !== undefined &&
    (before.max === undefined || after.max < before.max);

  if (raised || lowered) {
    changes.push(
      breakingChange(
        "column.bounds",
        table,
        `Narrows the bounds of ${at}${after.min === undefined ? "" : ` to at least ${String(after.min)}`}${after.max === undefined ? "" : `${after.min === undefined ? " to" : " and"} at most ${String(after.max)}`}.`,
        checkSteps(at, "fit the new bounds"),
        name,
      ),
    );
  }

  const checks = (format: AppColumnConfig["format"]): boolean => {
    const rule = format === undefined ? undefined : FIELD_FORMATS[format];

    return rule?.pattern !== undefined || rule?.bounds !== undefined;
  };

  if (
    after.format !== undefined &&
    after.format !== before.format &&
    checks(after.format)
  ) {
    changes.push(
      breakingChange(
        "column.format",
        table,
        `Checks ${at} as ${after.format}.`,
        checkSteps(at, `hold a valid ${after.format}`),
        name,
      ),
    );
  }

  if (
    after.references !== undefined &&
    targetOf(before.references) !== targetOf(after.references)
  ) {
    changes.push(
      breakingChange(
        "column.reference",
        table,
        `Points ${at} at ${targetOf(after.references)}, which fails for values that row doesn't have.`,
        checkSteps(at, `match a row of ${targetOf(after.references)}`),
        name,
      ),
    );
  }

  if (changes.length === 0 && !same(before, after)) {
    changes.push(safe("column.changed", table, `Changes ${at}.`, name));
  }

  return changes;
}

/**
 * The changes to a table's own keys: a new scope, unique set, or a removed
 * `timestamps`, `rank` or `softDelete` breaks what exists; the rest (indexes,
 * the comment, other subject keys) is safe.
 */
function tableChanges(
  name: string,
  before: AppTableConfig,
  after: AppTableConfig,
): DesignChange[] {
  const changes: DesignChange[] = [];

  if ((before.scope ?? "inherit") !== (after.scope ?? "inherit")) {
    changes.push(
      breakingChange(
        "table.scope",
        name,
        `Changes the scope of ${name} from ${before.scope ?? "inherit"} to ${after.scope ?? "inherit"}, which changes its scope column and policies.`,
        [
          `Add the new scope column as nullable and fill it for every row in a migration.`,
          `Move the app to the new scope, then deploy.`,
          `Change the scope and drop the old column in a later migration.`,
        ],
      ),
    );
  }

  const sets = (table: AppTableConfig): Set<string> =>
    new Set((table.unique ?? []).map((set) => set.join(",")));

  const oldSets = sets(before);
  const added = [...sets(after)].filter((set) => !oldSets.has(set));

  if (added.length > 0) {
    changes.push(
      breakingChange(
        "table.unique",
        name,
        `Adds unique (${added.join("), (")}) to ${name}, which fails while two rows share those values.`,
        checkSteps(`(${added.join("), (")})`, "repeat across rows"),
      ),
    );
  }

  const dropped = [
    before.timestamps !== false && after.timestamps === false
      ? "timestamps"
      : undefined,
    before.subject?.rank !== undefined && after.subject?.rank === undefined
      ? "rank"
      : undefined,
    before.subject?.softDelete === true && after.subject?.softDelete !== true
      ? "softDelete"
      : undefined,
  ].filter((each) => each !== undefined);

  if (dropped.length > 0) {
    changes.push(
      breakingChange(
        "table.columns",
        name,
        `Removes ${dropped.join(", ")} from ${name}, which drops the columns ${dropped.length === 1 ? "it adds" : "they add"} and their values.`,
        [
          `Stop reading ${dropped.join(", ")} in the app, then deploy.`,
          `Export the values first if you need them.`,
          `Remove the key and generate the migration that drops the columns.`,
        ],
      ),
    );
  }

  const rest = (config: AppTableConfig): unknown => ({
    ...config,
    columns: undefined,
    id: undefined,
    rollups: undefined,
    lookups: undefined,
  });

  if (changes.length === 0 && !same(rest(before), rest(after))) {
    changes.push(safe("table.changed", name, `Changes table ${name}.`));
  }

  return changes;
}

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
    } else {
      changes.push(...constraintChanges(table, name, column, now));
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

      changes.push(
        ...tableChanges(name, table, now),
        ...columnChanges(name, table, now),
      );

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
