import { describe, expect, it } from "vitest";

import { moduleContext } from "../../src/sql/module-context.ts";
import { renameTableObjects } from "../../src/sql/rename-sql.ts";
import { renderBlocks } from "../../src/sql/render.ts";
import { TABLE_RENAMES } from "../../src/sql/table-renames.ts";
import { upgradePlan } from "../../src/sql/upgrade.ts";
import { liteStack } from "../../src/testing/lite.ts";

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

const schemaOf = (blocks: readonly string[], config = {}): string =>
  renderBlocks(blocks, config)
    .filter((file) => file.kind === "schema")
    .map((file) => file.contents)
    .join("\n");

describe("TABLE_RENAMES", () => {
  it("names each module's current default table", () => {
    const names = Object.entries(TABLE_RENAMES).flatMap(([module, renames]) =>
      Object.entries(renames).map(([logical, rename]) => ({
        table: `${module}.${logical}`,
        name: moduleContext(module).tableName(logical).name,
        from: rename.from,
        to: rename.to,
      })),
    );

    expect(names.filter((entry) => entry.name !== entry.to)).toEqual([]);
    expect(names.filter((entry) => entry.from === entry.to)).toEqual([]);
  });
});

describe("module table upgrades", () => {
  it("renames the table and its objects, and drops nothing", () => {
    const [plan] = upgradePlan([{ module: "invoices", version: 2 }]);
    const sql = plan?.steps.map((step) => step.sql).join("\n") ?? "";

    expect(plan?.steps.map((step) => step.description)).toContain(
      "The delivery log is e_invoice_deliveries (ADR 0206).",
    );
    expect(sql).toContain(
      `alter table "better_supabase"."invoice_e_deliveries" rename to "e_invoice_deliveries"`,
    );
    expect(sql).toContain("alter index %I.%I rename to %I");
    expect(sql).not.toMatch(/\bdrop\b/i);
  });

  it("skips a step on a table the app adopted", () => {
    const [plan] = upgradePlan([{ module: "invoices", version: 2 }], {
      modules: {
        invoices: { tables: { eDeliveries: "public.invoice_e_deliveries" } },
      },
    });

    expect(plan?.steps.map((step) => step.sql).join("")).not.toContain(
      "rename to",
    );
  });

  it("keeps a renamed entity's tables under their old noun", () => {
    const tickets = schemaOf(["tasks"], {
      modules: { tasks: { entities: { task: "ticket" } } },
    });

    expect(tickets).toContain(`create table "better_supabase"."tickets"`);
    expect(schemaOf(["tasks"])).toContain(
      `create table "better_supabase"."tasks"`,
    );
  });

  it("renames only the objects that carry the old table name", () => {
    const sql = renameTableObjects(
      { schema: "better_supabase", name: "activities" },
      "engagements",
    );

    expect(sql).toContain(
      'if to_regclass(\'"better_supabase"."activities"\') is null then return; end if;',
    );
    expect(sql).toContain("left(o.name, 12) = 'engagements_'");
    expect(sql).toContain("'activities' || substr(o.name, 12)");
  });

  it(
    "moves the old table with its indexes, policies, constraints and sequences",
    async () => {
      const [plan] = upgradePlan([{ module: "invoices", version: 2 }]);

      await using stack = await liteStack({
        driver: "pglite",
        migrations: [
          `create schema if not exists better_supabase;
create table better_supabase.invoice_e_deliveries (id uuid primary key, n serial, name text not null check (name <> ''));
create index invoice_e_deliveries_name_idx on better_supabase.invoice_e_deliveries (name);
alter table better_supabase.invoice_e_deliveries enable row level security;
create policy invoice_e_deliveries_read on better_supabase.invoice_e_deliveries for select using (true);`,
          ...(plan?.steps.map((step) => step.sql) ?? []),
        ],
        seed: [
          `do $$
begin
  if to_regclass('better_supabase.e_invoice_deliveries') is null
    or to_regclass('better_supabase.invoice_e_deliveries') is not null then
    raise exception 'table not renamed';
  end if;
  if to_regclass('better_supabase.e_invoice_deliveries_name_idx') is null then
    raise exception 'index not renamed';
  end if;
  if not exists (select 1 from pg_policy where polname = 'e_invoice_deliveries_read') then
    raise exception 'policy not renamed';
  end if;
  if not exists (select 1 from pg_constraint where conname = 'e_invoice_deliveries_name_check')
    or not exists (select 1 from pg_constraint where conname = 'e_invoice_deliveries_pkey') then
    raise exception 'constraints not renamed';
  end if;
  if to_regclass('better_supabase.e_invoice_deliveries_n_seq') is null then
    raise exception 'sequence not renamed';
  end if;
end;
$$;`,
        ],
      });

      expect(stack.url).not.toBe("");
    },
    BOOT.timeout,
  );
});
