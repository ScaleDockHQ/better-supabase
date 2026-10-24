import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { moduleContext } from "../../../src/sql/module-context.ts";
import { runsOverAppTables } from "../../../src/sql/module-types.ts";
import { SQL_MODULES } from "../../../src/sql/registry.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { declaredTables } from "../../../src/sql/schema-scan.ts";

/** The domain modules that run over tables the app already has. */
const MODULES = [
  "quotes",
  "invoices",
  "tasks",
  "contacts",
  "orders",
  "shipments",
  "expenses",
  "leave",
  "hiring",
  "assets",
  "approvals",
  "templates",
  "workflows",
  "workflow-editor",
  "messaging",
  "comments",
  "timeline",
  "ledger",
] as const;

const SCHEMAS = ["public", "better_supabase"];

const unquote = (text: string): string => text.replaceAll('"', "");

/**
 * `schema.table` of each logical table that can be the app's, as the module
 * renders it by default.
 */
function tablesOf(module: string): Record<string, string> {
  const ctx = moduleContext(module, {}, [module]);

  return Object.fromEntries(
    Object.entries(SQL_MODULES[module]?.names?.tables ?? {})
      .filter(
        ([logical, spec]) => spec.app !== undefined && ctx.hasTable(logical),
      )
      .map(([logical]) => {
        const { schema, name } = ctx.tableName(logical);

        return [logical, `${schema}.${name}`];
      }),
  );
}

/** The module's own files, rendered with `ownTables` and `modules`. */
function render(
  module: string,
  ownTables: Record<string, string>,
  modules: AnyBlocksConfig = {},
): string {
  return renderBlocks([module], { ownTables, modules })
    .filter((file) => file.module === module && file.kind === "schema")
    .map((file) => file.contents)
    .join("\n");
}

interface ConflictTarget {
  readonly table: string;
  readonly columns: string;
}

/** Each `insert into <table> ... on conflict (<columns>)` in `sql`. */
function conflictTargets(sql: string): ConflictTarget[] {
  return [...sql.matchAll(/on conflict\s*\(([^)]*)\)/gi)].flatMap((match) => {
    const before = sql.slice(0, match.index);
    const insert = [...before.matchAll(/insert into\s+([\w."]+)/gi)].at(-1);

    return insert === undefined
      ? []
      : [
          {
            table: unquote(insert[1]!),
            columns: unquote(match[1]!).replaceAll(/\s+/g, ""),
          },
        ];
  });
}

/** Whether `sql` creates a unique index on `table` over `columns`. */
function hasUniqueIndex(sql: string, target: ConflictTarget): boolean {
  return [
    ...unquote(sql).matchAll(
      /create unique index if not exists \S+ on ([\w.]+) \(([^)]*)\)/gi,
    ),
  ].some(
    (match) =>
      match[1] === target.table &&
      match[2]!.replaceAll(/\s+/g, "") === target.columns,
  );
}

/** The optional columns of each table, all mapped to `null`. */
function nullOptional(module: string): AnyBlocksConfig {
  const columns = Object.fromEntries(
    Object.entries(SQL_MODULES[module]?.names?.tables ?? {}).flatMap(
      ([logical, spec]) =>
        spec.optional === undefined || spec.optional.length === 0
          ? []
          : [
              [
                logical,
                Object.fromEntries(
                  spec.optional.map((column) => [column, null]),
                ),
              ],
            ],
    ),
  );

  return { [module]: { columns } };
}

describe.each(MODULES)("%s over the app's tables", (module) => {
  const tables = tablesOf(module);

  const all = Object.fromEntries(
    Object.values(tables).map((table) => [table, "app.sql"]),
  );

  const cases: [string, Record<string, string>][] = [
    ...Object.entries(tables).map(
      ([logical, table]): [string, Record<string, string>] => [
        logical,
        { [table]: "app.sql" },
      ],
    ),
    ["every table", all],
  ];

  it("has tables that can be the app's", () => {
    expect(runsOverAppTables(SQL_MODULES[module]!)).toBe(true);
  });

  it.each(cases)("creates no table the app has (%s)", (_name, own) => {
    const sql = render(module, own);
    const created = declaredTables([{ text: sql }], SCHEMAS);

    expect(created.filter((table) => Object.hasOwn(own, table))).toEqual([]);
    expect(
      Object.values(tables).filter(
        (table) => !Object.hasOwn(own, table) && !created.includes(table),
      ),
    ).toEqual([]);
  });

  it.each(cases)(
    "keeps the app's grants and indexes every on conflict target (%s)",
    (_name, own) => {
      const sql = render(module, own);

      for (const table of Object.keys(own)) {
        expect(unquote(sql)).not.toContain(
          `revoke all on ${table} from anon, authenticated`,
        );
      }

      const missing = conflictTargets(sql).filter(
        (target) =>
          Object.hasOwn(own, target.table) && !hasUniqueIndex(sql, target),
      );

      expect(missing).toEqual([]);
    },
  );

  it.each(cases)(
    "names its policies and triggers on the app's tables bsb_ (%s)",
    (_name, own) => {
      const sql = unquote(render(module, own));

      const named = [
        ...sql.matchAll(
          /(?:create|drop|alter) policy (?:if exists )?(\S+) on ([\w.]+)/gi,
        ),
        ...sql.matchAll(
          /(?:create (?:or replace )?(?:constraint )?|drop |alter )trigger (?:if exists )?(\S+)\s[\s\S]*?\bon ([\w.]+)/gi,
        ),
      ]
        .filter((match) => Object.hasOwn(own, match[2]!))
        .map((match) => `${match[2]!}: ${match[1]!}`);

      expect(named.filter((name) => !name.includes(": bsb_"))).toEqual([]);
    },
  );

  it("renders with every optional column mapped to null", () => {
    const modules = nullOptional(module);

    expect(() => render(module, {}, modules)).not.toThrow();
    expect(() => render(module, all, modules)).not.toThrow();
  });
});

describe("blocks next to the app's tables", () => {
  const files = (
    names: readonly string[],
    ownTables: Record<string, string>,
    modules: AnyBlocksConfig = {},
  ): string =>
    unquote(
      renderBlocks([...names], { ownTables, modules })
        .filter((file) => file.kind === "schema")
        .map((file) => file.contents)
        .join("\n"),
    );

  it("casts the conversation access channels write to the app's column type", () => {
    const conversations = tablesOf("messaging").conversations!;

    const sql = files(["messaging", "channels"], {
      [conversations]: "app.sql",
    });

    const update = sql.slice(
      sql.indexOf("function better_supabase.update_channel"),
    );

    expect(update).toMatch(/access = better_supabase\.as_column_type\(/);
  });

  it("binds pipelines to the tenant column the app's applications table names", () => {
    const applications = tablesOf("hiring").applications!;

    const sql = files(
      ["hiring", "pipelines"],
      { [applications]: "app.sql" },
      { hiring: { columns: { applications: { tenant: "org_id" } } } },
    );

    expect(sql).toContain("default_pipeline(new.org_id, 'application'");
    expect(sql).not.toContain("new.tenant_id");
  });

  it("moves stock movements onto a ledger without a memo column", () => {
    expect(() =>
      files(
        ["ledger", "catalog", "inventory"],
        {},
        { ledger: { columns: { transactions: { memo: null } } } },
      ),
    ).not.toThrow();
  });
});
