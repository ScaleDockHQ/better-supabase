import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../src/config/blocks.ts";

import { canBeAppTable } from "../../src/sql/app-owned.ts";
import { moduleContext } from "../../src/sql/module-context.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderBlocks } from "../../src/sql/render.ts";
import { declaredTables } from "../../src/sql/schema-scan.ts";

/** Options a module needs once one of its tables is the app's. */
const OVER_APP_OPTIONS: AnyBlocksConfig = {
  "webhooks-out": { options: { defaultFormat: "standard" } },
};

function rendersAlone(module: string): boolean {
  try {
    renderBlocks([module]);

    return true;
  } catch {
    return false;
  }
}

export const ALONE: readonly string[] = Object.keys(SQL_MODULES).filter(
  (name) => name !== "pgtap" && rendersAlone(name),
);

/** `[module, table]` for each table a module creates on its own. */
const TABLES = ALONE.flatMap((name) =>
  createdAlone(name).map((table) => [name, table] as const),
);

function specOf(module: string, table: string) {
  const ctx = moduleContext(module, {}, [module]);

  return Object.entries(SQL_MODULES[module]?.names?.tables ?? {}).find(
    ([logical]) => {
      const parts = ctx.tableName(logical);

      return `${parts.schema}.${parts.name}` === table;
    },
  )?.[1];
}

export const OVER: readonly (readonly [string, string])[] = TABLES.filter(
  ([module, table]) => {
    const spec = specOf(module, table);

    return spec !== undefined && canBeAppTable(spec, undefined);
  },
);

const CREATING: readonly (readonly [string, string])[] = TABLES.filter(
  ([module, table]) =>
    !OVER.some(([other, own]) => other === module && own === table),
);

function tablesOf(module: string): string[] {
  const ctx = moduleContext(module, {}, [module]);

  return Object.keys(SQL_MODULES[module]?.names?.tables ?? {})
    .filter((logical) => ctx.hasTable(logical))
    .map((logical) => {
      const { schema, name } = ctx.tableName(logical);

      return `${schema}.${name}`;
    });
}

function created(module: string, ownTables: Record<string, string>): string[] {
  const files = renderBlocks([module], {
    ownTables,
    modules: OVER_APP_OPTIONS,
  }).filter((file) => file.module === module);

  return declaredTables(
    files.map((file) => ({ text: file.contents })),
    ["public", "better_supabase"],
  );
}

function createdAlone(module: string): string[] {
  const alone = created(module, {});

  return tablesOf(module).filter((table) => alone.includes(table));
}

/**
 * Every column the module names for `schema.table`, as the app's view lists
 * them.
 */
function allColumnsOf(module: string, table: string): string[] {
  const name = table.slice(table.indexOf(".") + 1);

  const spec = Object.values(SQL_MODULES[module]?.names?.tables ?? {}).find(
    (each) => each.name === name,
  );

  return ["id", ...Object.values(spec?.columns ?? {})];
}

/** One half of the per-table adoption cases. `part` is 0 or 1. */
export function registerAdoptedTables(part: 0 | 1): void {
  const over = OVER.filter((_, index) => index % 2 === part);
  const creating = CREATING.filter((_, index) => index % 2 === part);

  describe("blocks over the app's tables", () => {
    it.each(over)(
      "%s leaves %s to the app and creates its other tables",
      (module, table) => {
        const made = created(module, { [table]: "app.sql" });

        expect(made).not.toContain(table);
        expect(
          tablesOf(module).filter((other) => made.includes(other)),
        ).toEqual(createdAlone(module).filter((other) => other !== table));
      },
    );

    it.each(creating)(
      "%s refuses to create %s the app has",
      (module, table) => {
        expect(() => created(module, { [table]: "app.sql" })).toThrow(
          `creates ${table}, which is already in app.sql`,
        );
      },
    );

    it.each(creating)(
      "%s refuses to create %s over the app's view",
      (module, table) => {
        expect(() =>
          renderBlocks([module], {
            ownTables: { [table]: "app.sql" },
            ownViews: { [table]: { updatable: false } },
            ownColumns: { [table]: allColumnsOf(module, table) },
            modules: OVER_APP_OPTIONS,
          }),
        ).toThrow(`creates ${table}, which is already in app.sql`);
      },
    );
  });
}
