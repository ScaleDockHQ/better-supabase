import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";
const DAN = "44444444-4444-4444-8444-444444444444";
const ALICE_EMPLOYEE = "66666666-6666-4666-8666-666666666666";
const SALES = "77777777-7777-4777-8777-777777777777";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const TEAMS = `
create table public.teams (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  name text not null,
  slug text not null,
  status text not null default 'active',
  description text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
`;

// The shape most apps start from: the user is part of the primary key.
const USER_ONLY = `${TEAMS}
create table public.team_members (
  organization_id uuid not null,
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (team_id, user_id)
);
`;

// An app that keeps employees on its own table: its own key and a nullable user.
const WITH_EMPLOYEES = `${TEAMS}
create table public.team_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid references auth.users (id) on delete cascade,
  employee_id uuid,
  created_at timestamptz not null default now()
);
`;

const BLOCKS: AnyBlocksConfig = {
  teams: {
    tables: { teams: "public.teams", members: "public.team_members" },
    columns: {
      teams: { tenant: "organization_id" },
      members: { tenant: "organization_id" },
    },
  },
};

const SEED = `
insert into auth.users (id) values ('${ALICE}'), ('${BOB}');
insert into better_supabase.memberships (organization_id, user_id, role) values
  ('${TENANT}', '${ALICE}', 'member'), ('${TENANT}', '${BOB}', 'member');
insert into public.teams (id, organization_id, name, slug) values ('${SALES}', '${TENANT}', 'Sales', 'sales');
insert into better_supabase.employees (id, tenant_id, user_id, name) values
  ('${ALICE_EMPLOYEE}', '${TENANT}', '${ALICE}', 'Alice'), ('${DAN}', '${TENANT}', null, 'Dan');
`;

const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const BOOT = { timeout: 120_000 };

function render(columns: readonly string[]) {
  return renderBlocks(["teams", "employees", "outbox"], {
    modules: BLOCKS,
    ownTables: { "public.teams": "app.sql", "public.team_members": "app.sql" },
    ownColumns: {
      "public.teams": [
        "id",
        "organization_id",
        "name",
        "slug",
        "status",
        "description",
        "created_by",
        "created_at",
        "updated_at",
      ],
      "public.team_members": columns,
    },
  });
}

async function run(
  app: string,
  columns: readonly string[],
  check: string,
): Promise<void> {
  const files = render(columns);

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      app,
      ...files
        .filter((file) => file.kind === "schema")
        .map((file) => file.contents),
    ],
    seed: [
      SEED,
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      ALLOW,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("teams with employees over the app's team_members", BOOT, () => {
  const userOnly = ["organization_id", "team_id", "user_id", "created_at"];

  it("keeps a table without employee_id user-only", () => {
    const sql = render(userOnly)
      .filter((file) => file.module === "teams")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain("employee_id");
    expect(sql).not.toContain("bsb_team_member_employee_keep");
  });

  it("removes members and users of a user-only table that have an employee record", async () => {
    await expect(
      run(
        USER_ONLY,
        userOnly,
        `do $$
begin
  ${SERVICE}
  perform better_supabase.add_team_member('${SALES}', '${ALICE}');
  perform better_supabase.add_team_member('${SALES}', '${BOB}');
  if (select count(*) from public.team_members) <> 2 then
    raise exception 'add %', (select jsonb_agg(m) from public.team_members m);
  end if;

  if not better_supabase.remove_team_member('${SALES}', '${ALICE}') then
    raise exception 'remove_team_member';
  end if;
  delete from auth.users where id = '${BOB}';
  if exists (select 1 from public.team_members) then
    raise exception 'remove %', (select jsonb_agg(m) from public.team_members m);
  end if;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });

  it("keeps employees on a table with its own key and a nullable user", async () => {
    await expect(
      run(
        WITH_EMPLOYEES,
        [...userOnly, "id", "employee_id"],
        `do $$
begin
  ${SERVICE}
  perform better_supabase.add_team_member('${SALES}', employee => '${DAN}');
  perform better_supabase.add_team_member('${SALES}', '${ALICE}');
  if (select jsonb_agg(jsonb_build_array(user_id, employee_id) order by employee_id) from public.team_members)
    <> '[[null, "${DAN}"], ["${ALICE}", "${ALICE_EMPLOYEE}"]]'::jsonb then
    raise exception 'add %', (select jsonb_agg(m) from public.team_members m);
  end if;

  delete from better_supabase.memberships where user_id = '${ALICE}';
  delete from auth.users where id = '${ALICE}';
  if (select jsonb_agg(jsonb_build_array(user_id, employee_id) order by employee_id) from public.team_members)
    <> '[[null, "${DAN}"], [null, "${ALICE_EMPLOYEE}"]]'::jsonb then
    raise exception 'keep %', (select jsonb_agg(m) from public.team_members m);
  end if;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });
});
