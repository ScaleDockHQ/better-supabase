import { describe, expect, it } from "vitest";

import { TABLE_RENAMES } from "../../src/core/renames.ts";
import { moduleContext } from "../../src/sql/module-context.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renameTableObjects } from "../../src/sql/rename-sql.ts";
import { renderBlocks } from "../../src/sql/render.ts";
import { freesTableName, tableMoves } from "../../src/sql/table-renames.ts";
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

  it("gives every renamed table an upgrade step", () => {
    const steps = (module: string): string[] =>
      (SQL_MODULES[module]?.names?.migrations ?? [])
        .filter((step) => step.objects === true)
        .map((step) => step.table)
        .toSorted();

    for (const [module, renames] of Object.entries(TABLE_RENAMES)) {
      expect(steps(module)).toEqual(Object.keys(renames).toSorted());
    }
  });

  it("moves the idempotency leases before the leases block takes the name", () => {
    expect(freesTableName("idempotency")).toBe(true);
    expect(freesTableName("leases")).toBe(false);

    const plans = upgradePlan([
      { module: "leases", version: 2 },
      { module: "idempotency", version: 1 },
    ]);

    expect(plans.map((plan) => plan.module)).toEqual(["idempotency", "leases"]);
  });
});

describe("module table upgrades", () => {
  it("renames the table and its objects, and drops nothing", () => {
    const [plan] = upgradePlan([{ module: "activities", version: 1 }]);
    const sql = plan?.steps.map((step) => step.sql).join("\n") ?? "";

    expect(plan?.steps.map((step) => step.description)).toContain(
      "The engagements table is activities (ADR 0130).",
    );
    expect(sql).toContain(
      `alter table "better_supabase"."engagements" rename to "activities"`,
    );
    expect(sql).toContain("alter index %I.%I rename to %I");
    expect(sql).not.toMatch(/\bdrop\b/i);
  });

  it("skips a step on a table the app adopted", () => {
    const [plan] = upgradePlan([{ module: "goals", version: 1 }], {
      modules: { goals: { tables: { targets: "public.targets" } } },
    });

    expect(plan?.steps.map((step) => step.sql).join("")).not.toContain(
      "rename to",
    );
  });

  it("keeps a renamed entity's tables under their old noun", () => {
    const tickets = schemaOf(["tasks"], {
      modules: { tasks: { entities: { task: "ticket" } } },
    });

    expect(tickets).toContain(
      `create table if not exists "better_supabase"."tickets"`,
    );
    expect(schemaOf(["tasks"])).toContain(
      `create table if not exists "better_supabase"."tasks"`,
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
      const [plan] = upgradePlan([{ module: "goals", version: 1 }]);

      await using stack = await liteStack({
        driver: "pglite",
        migrations: [
          `create schema if not exists better_supabase;
create table better_supabase.targets (id uuid primary key, n serial, name text not null check (name <> ''));
create index targets_name_idx on better_supabase.targets (name);
alter table better_supabase.targets enable row level security;
create policy targets_read on better_supabase.targets for select using (true);`,
          ...(plan?.steps.map((step) => step.sql) ?? []),
        ],
        seed: [
          `do $$
begin
  if to_regclass('better_supabase.goals') is null
    or to_regclass('better_supabase.targets') is not null then
    raise exception 'table not renamed';
  end if;
  if to_regclass('better_supabase.goals_name_idx') is null then
    raise exception 'index not renamed';
  end if;
  if not exists (select 1 from pg_policy where polname = 'goals_read') then
    raise exception 'policy not renamed';
  end if;
  if not exists (select 1 from pg_constraint where conname = 'goals_name_check')
    or not exists (select 1 from pg_constraint where conname = 'goals_pkey') then
    raise exception 'constraints not renamed';
  end if;
  if to_regclass('better_supabase.goals_n_seq') is null then
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

describe("tableMoves", () => {
  it("returns nothing for a module 0.47 left alone", () => {
    expect(tableMoves("contacts", 1)).toEqual([]);
  });
});
