import type { SameTenantLayout } from "../sql/layout-types.ts";

import { factsOf } from "./schema-reader/index.ts";
import {
  declaredForeignKeys,
  declaredTableColumns,
} from "./schema-reader/queries.ts";

type Texts = readonly { readonly text: string }[];

const ROW_COLUMN = /\b(?:new|old)\s*\.\s*"?([a-z_][\w$]*)"?/gi;

/**
 * `@bsb same-tenant-guard column=a,b` in a trigger function: the app's trigger
 * checks the tenant of those foreign key columns itself (ADR 1268).
 */
const GUARD_MARKER =
  /@bsb[ \t]+same-tenant-guard[ \t]+columns?[ \t]*=[ \t]*([a-z_][\w$]*(?:[ \t]*,[ \t]*[a-z_][\w$]*)*)/gi;

const inSchemas = (table: string, schemas: readonly string[]): boolean =>
  schemas.includes(table.slice(0, table.indexOf(".")));

/**
 * The columns each file makes not null, as `schema.table` to names: a column
 * with `not null` or `primary key`, or an `alter column ... set not null`.
 */
function notNullColumns(
  files: Texts,
  schemas: readonly string[],
): ReadonlyMap<string, ReadonlySet<string>> {
  const found = new Map<string, Set<string>>();

  const add = (table: string, column: string): void => {
    found.set(table, (found.get(table) ?? new Set()).add(column));
  };

  for (const file of files) {
    const facts = factsOf(file.text);

    for (const table of facts.tables) {
      if (!inSchemas(table.name, schemas)) {
        continue;
      }

      for (const column of table.columns) {
        if (column.notNull) {
          add(table.name, column.name);
        }
      }
    }

    for (const alter of facts.alters) {
      if (inSchemas(alter.table, schemas)) {
        for (const column of alter.setNotNull) {
          add(alter.table, column);
        }
      }
    }
  }

  return found;
}

/**
 * The function body of each app trigger, by `schema.table`. Triggers named
 * `bsb_*` are the blocks' own and don't count, so a check the app already makes
 * is never emitted twice.
 */
function appTriggerBodies(
  files: Texts,
  schemas: readonly string[],
): Readonly<Record<string, readonly string[]>> {
  const all = files.map((file) => factsOf(file.text));
  const bodies = new Map<string, string>();

  for (const facts of all) {
    for (const fn of facts.functions) {
      if (fn.body !== undefined) {
        bodies.set(fn.name, fn.body);
      }
    }
  }

  const found = new Map<string, string[]>();

  for (const facts of all) {
    for (const trigger of facts.triggers) {
      if (
        trigger.name.startsWith("bsb_") ||
        !inSchemas(trigger.table, schemas)
      ) {
        continue;
      }

      found.set(trigger.table, [
        ...(found.get(trigger.table) ?? []),
        bodies.get(trigger.function) ?? "",
      ]);
    }
  }

  return Object.fromEntries(found);
}

/**
 * The foreign key columns each table's app triggers declare they guard, by the
 * `@bsb same-tenant-guard` marker. Reading `new.<column>` alone guards
 * nothing.
 */
function appTriggerColumns(
  bodies: Readonly<Record<string, readonly string[]>>,
): Readonly<Record<string, readonly string[]>> {
  return Object.fromEntries(
    Object.entries(bodies).flatMap(([table, list]) => {
      const columns = new Set<string>();

      for (const body of list) {
        for (const marker of body.matchAll(GUARD_MARKER)) {
          for (const column of marker[1]!.split(",")) {
            columns.add(column.trim().toLowerCase());
          }
        }
      }

      return columns.size === 0 ? [] : [[table, [...columns]]];
    }),
  );
}

/** The columns each table's app triggers read or write through `new.` or `old.`. */
function appTriggerTouched(
  bodies: Readonly<Record<string, readonly string[]>>,
): Readonly<Record<string, readonly string[]>> {
  return Object.fromEntries(
    Object.entries(bodies).map(([table, list]) => {
      const columns = new Set<string>();

      for (const body of list) {
        for (const column of body.matchAll(ROW_COLUMN)) {
          columns.add(column[1]!.toLowerCase());
        }
      }

      return [table, [...columns]];
    }),
  );
}

const asLists = (
  map: ReadonlyMap<string, ReadonlySet<string>>,
): Record<string, string[]> =>
  Object.fromEntries([...map].map(([table, set]) => [table, [...set]]));

/**
 * The last layout by its input. A render asks for it once per module, so the
 * same files are read once.
 */
let lastLayout: { key: string; layout: SameTenantLayout } | undefined;

/**
 * The layout fields `blocks.memberships.options.sameTenant.auto` derives its
 * entries from, read from the facts of `files`. A caller awaits
 * `primeSchemaFacts` for the texts first.
 *
 * @param files - The schema files.
 * @param schemas - The schemas the layout covers.
 * @returns Foreign keys, columns, not null columns and app triggers.
 */
export function sameTenantLayout(
  files: Texts,
  schemas: readonly string[],
): SameTenantLayout {
  const key = `${schemas.join(",")}\0${files.map((file) => file.text).join("\0")}`;

  if (lastLayout?.key !== key) {
    const facts = files.map((file) => factsOf(file.text));
    const bodies = appTriggerBodies(files, schemas);

    lastLayout = {
      key,
      layout: {
        foreignKeys: declaredForeignKeys(facts, schemas),
        appTriggerColumns: appTriggerColumns(bodies),
        appTriggerTouched: appTriggerTouched(bodies),
        appTriggerBodies: bodies,
        declaredColumns: asLists(declaredTableColumns(facts, schemas)),
        notNullColumns: asLists(notNullColumns(files, schemas)),
      },
    };
  }

  return lastLayout.layout;
}
