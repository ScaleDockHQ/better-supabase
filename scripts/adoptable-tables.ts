// The "Tables a block runs over" list on the own-schemas docs page, built
// from each module's `names.tables`. `pnpm catalog` writes it between the
// markers, and `pnpm catalog:check` and `docs:drift` fail when it is stale.
import { join } from "node:path";

import type { BlockSqlTableSpec } from "../packages/better-supabase/src/sql/context.ts";

import { SQL_MODULES } from "../packages/better-supabase/src/sql/index.ts";
import { moduleContext } from "../packages/better-supabase/src/sql/module-context.ts";

export const OWN_SCHEMAS_PAGE: string = join(
  import.meta.dirname,
  "../apps/docs/content/docs/(blocks)/blocks/(using)/own-schemas.mdx",
);

const START = "{/* adoptable-tables:start, written by `pnpm catalog` */}";
const END = "{/* adoptable-tables:end */}";

const code = (names: readonly string[]): string =>
  names.map((name) => `\`${name}\``).join(", ");

/** One line for a table that can be the app's own table. */
function line(
  module: string,
  logical: string,
  spec: BlockSqlTableSpec,
): string | undefined {
  if (spec.app === undefined) {
    return undefined;
  }

  const { schema, name } = moduleContext(module, {}, [module]).tableName(
    logical,
  );

  const optional = new Set(spec.optional);

  const required = Object.entries(spec.columns)
    .filter(([key]) => !optional.has(key))
    .map(([, column]) => column);

  const typed = (spec.typed ?? []).flatMap((key) => {
    const column = spec.columns[key];

    return column === undefined ? [] : [column];
  });

  const mappable = (spec.mappable ?? []).flatMap((key) => {
    const column = spec.columns[key];

    return column === undefined ? [] : [column];
  });

  const mapped = spec.app.onlyWhenMapped === true ? ", once mapped" : "";

  const types = `${typed.length === 0 ? "" : `; typed: ${code(typed)}`}${
    mappable.length === 0 ? "" : `; typed with values: ${code(mappable)}`
  }`;

  const columns =
    required.length === 0 ? "no required columns" : code(required);

  return `  - \`${schema}.${name}\`${mapped}: ${columns}${types}`;
}

/** The generated section, markers included. */
export function adoptableTablesSection(): string {
  const blocks = Object.keys(SQL_MODULES)
    .toSorted()
    .flatMap((module) => {
      const tables = Object.entries(SQL_MODULES[module]?.names?.tables ?? {});

      const lines = tables.flatMap(([logical, spec]) => {
        const text = line(module, logical, spec);

        return text === undefined ? [] : [text];
      });

      return lines.length === 0 ? [] : [`- \`${module}\``, ...lines];
    });

  return [START, "", ...blocks, "", END].join("\n");
}

function sectionOf(page: string): readonly [number, number] | undefined {
  const start = page.indexOf(START);
  const end = page.indexOf(END);

  return start === -1 || end < start ? undefined : [start, end + END.length];
}

/** The page with its generated section replaced, or `undefined` without markers. */
export function withAdoptableTables(page: string): string | undefined {
  const bounds = sectionOf(page);

  return bounds === undefined
    ? undefined
    : page.slice(0, bounds[0]) +
        adoptableTablesSection() +
        page.slice(bounds[1]);
}

/** Whether the page's generated section matches the table specs. */
export function adoptableTablesCurrent(page: string): boolean {
  const bounds = sectionOf(page);

  return (
    bounds !== undefined && page.slice(...bounds) === adoptableTablesSection()
  );
}
