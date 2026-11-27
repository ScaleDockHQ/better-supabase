import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../src/sql/render.ts";
import { upgradePlan } from "../../src/sql/upgrade.ts";
import { liteStack } from "../../src/testing/lite.ts";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const run = async (migrations: readonly string[]): Promise<void> => {
  await using stack = await liteStack({
    driver: "pglite",
    migrations: [...migrations],
  });

  expect(stack.url).not.toBe("");
};

describe("upgrade steps over an adopter's layout", { timeout: 60_000 }, () => {
  it("leaves out delegate_profile when the adopted tasks table lacks it", async () => {
    const TASKS = `create table public.tasks (
  id uuid primary key,
  organization_id uuid not null,
  title text not null
);`;

    const [plan] = upgradePlan([{ module: "tasks", version: 6 }], {
      blockTenantColumn: "organization_id",
      modules: { tasks: { tables: { items: "public.tasks" } } },
      ownTables: { "public.tasks": "app.sql" },
      ownColumns: { "public.tasks": ["id", "organization_id", "title"] },
    });

    const sql = (plan?.steps ?? []).map((step) => step.sql);

    expect(plan?.steps[0]?.from).toBe(6);
    expect(sql.join("\n")).not.toContain("delegate_profile");

    // Later steps alter the managed projects table, which a version 6 install
    // already has. This case only has the adopted tasks table.
    const adopted = (plan?.steps ?? [])
      .filter((step) => step.from === 6)
      .map((step) => step.sql);

    await expect(run([TASKS, ...adopted])).resolves.toBeUndefined();
  });

  it("clears delegate_profile when the adopted tasks table has it", () => {
    const [plan] = upgradePlan([{ module: "tasks", version: 6 }], {
      modules: { tasks: { tables: { items: "public.tasks" } } },
      ownTables: { "public.tasks": "app.sql" },
      ownColumns: { "public.tasks": ["id", "tenant_id", "delegate_profile"] },
    });

    expect(plan?.steps[0]?.sql).toContain(
      'update "public"."tasks" set "delegate_profile" = null',
    );
  });

  it("keys tax rates on the configured tenant column", async () => {
    const layout = { blockTenantColumn: "organization_id" };
    const files = renderBlocks(["tax"], layout);
    const [plan] = upgradePlan([{ module: "tax", version: 1 }], layout);
    const steps = (plan?.steps ?? []).map((step) => step.sql);

    // A version 1 database has neither the unique index nor the key.
    const v1 = `alter table better_supabase.tax_rates drop constraint tax_rates_tenant_code_fkey;
drop index better_supabase.tax_codes_id_tenant_key;`;

    const check = `do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'tax_rates_tenant_code_fkey'
      and pg_get_constraintdef(oid) like '%(tax_code_id, organization_id)%'
  ) then
    raise exception 'the upgrade did not key rates on organization_id';
  end if;
end;
$$;`;

    expect(steps.join("\n")).not.toContain("tenant_id");
    await expect(
      run([
        ROLES,
        ...files
          .filter((file) => file.kind === "schema")
          .map((file) => file.contents),
        v1,
        ...steps,
        check,
      ]),
    ).resolves.toBeUndefined();
  });
});
