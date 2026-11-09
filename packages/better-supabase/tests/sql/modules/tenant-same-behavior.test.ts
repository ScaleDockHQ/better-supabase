import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { PgliteConnection } from "../../../src/lite/runtime.ts";

import { loadLite } from "../../../src/lite/runtime.ts";
import { sameTenantLayout } from "../../../src/sql/foreign-keys.ts";
import { moduleBody } from "../../../src/sql/render.ts";

const SCHEMA = `
create table public.roles (id uuid primary key, organization_id uuid, name text);
create table public.members (
  id uuid primary key,
  organization_id uuid not null,
  role_id uuid references public.roles
);
create table public.projects (id uuid primary key, organization_id uuid not null);
create table public.tasks (
  id uuid primary key,
  organization_id uuid not null,
  project_id uuid references public.projects deferrable initially deferred
);
`;

/** The `same_tenant` function and its triggers, as the module renders them. */
function sameTenantPart(): string {
  const layout = sameTenantLayout([{ text: SCHEMA }], ["public"]);

  const body = moduleBody("memberships", {
    modules: { memberships: { options: { sameTenant: { auto: true } } } },
    ...layout,
  })!;

  const start = body.indexOf(
    "create or replace function better_supabase.same_tenant()",
  );

  const last = body.lastIndexOf(
    "execute function better_supabase.same_tenant(",
  );

  return body.slice(start, body.indexOf(";", last) + 1);
}

describe("same_tenant on a database", { timeout: 60_000 }, () => {
  let connection: PgliteConnection | undefined;

  const run = async (sql: string): Promise<void> => {
    await connection!.driver.exec(sql);
  };

  const fails = async (sql: string): Promise<string> => {
    try {
      await run(sql);
    } catch (error) {
      return error instanceof Error ? error.message : String(error);
    }

    return "";
  };

  beforeAll(async () => {
    const lite = await loadLite();

    if (lite === undefined) {
      throw new Error("@supabase/lite is not installed");
    }

    connection = await lite.createPgliteConnection();

    await run(`
      create schema if not exists better_supabase;
      do $$ begin
        if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
        if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
      end $$;
      ${SCHEMA}
      ${sameTenantPart()}
    `);
  });

  afterAll(async () => {
    await connection?.close();
  });

  const ID = (n: number): string =>
    `'00000000-0000-4000-8000-${String(n).padStart(12, "0")}'`;

  it("lets a row reference a shared row without a tenant, and refuses another tenant's row", async () => {
    if (connection === undefined) {
      return;
    }

    await run(`
      insert into public.roles values (${ID(1)}, null, 'global'), (${ID(2)}, ${ID(100)}, 'mine'), (${ID(3)}, ${ID(200)}, 'theirs');
    `);

    await run(
      `insert into public.members values (${ID(11)}, ${ID(100)}, ${ID(1)}), (${ID(12)}, ${ID(100)}, ${ID(2)})`,
    );

    expect(
      await fails(
        `insert into public.members values (${ID(13)}, ${ID(100)}, ${ID(3)})`,
      ),
    ).toContain("must reference a row of");
  });

  it("checks a deferrable key at commit, so the child can come first", async () => {
    if (connection === undefined) {
      return;
    }

    await run(`
      begin;
      insert into public.tasks values (${ID(21)}, ${ID(100)}, ${ID(31)});
      insert into public.projects values (${ID(31)}, ${ID(100)});
      commit;
    `);

    expect(
      await fails(`
        begin;
        insert into public.tasks values (${ID(22)}, ${ID(100)}, ${ID(32)});
        insert into public.projects values (${ID(32)}, ${ID(200)});
        commit;
      `),
    ).toContain("must reference a row of");

    await run("rollback");
    expect(sameTenantPart()).toContain("create constraint trigger");
  });
});
