import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The app's own leave tables: renamed columns, enum unit and part, and no
// allowance, carryover, color, note or cancelled-by columns.
const APP = `
create type public.absence_unit as enum ('days', 'hours');
create type public.absence_part as enum ('full', 'morning', 'afternoon', 'hours');

create table public.absence_kinds (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  code text not null,
  label text not null,
  unit public.absence_unit not null default 'days',
  paid boolean not null default true,
  tracked boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.absences (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  user_id uuid not null,
  kind_id uuid not null references public.absence_kinds (id),
  starts_on date not null,
  ends_on date not null,
  part public.absence_part not null default 'full',
  days numeric not null,
  approval_id uuid,
  approved_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
`;

const OWN_TABLES = {
  "public.absence_kinds": "app.sql",
  "public.absences": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  leave: {
    tables: { types: "public.absence_kinds", requests: "public.absences" },
    columns: {
      types: {
        tenant: "org_id",
        key: "code",
        name: "label",
        allowance: null,
        carryoverMax: null,
        color: null,
      },
      requests: {
        tenant: "org_id",
        type: "kind_id",
        partial: "part",
        amount: "days",
        note: null,
        cancelledBy: null,
      },
    },
  },
};

// Everyone may do everything in the tenant: these tests are about the tables.
const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into auth.users (id) values ('${ALICE}');
insert into better_supabase.memberships (organization_id, user_id, role) values ('${TENANT}', '${ALICE}', 'owner');
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const AS_ALICE = `perform set_config('request.jwt.claims', '{"sub":"${ALICE}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${ALICE}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["leave"], {
    modules: BLOCKS,
    ownTables: OWN_TABLES,
  });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      APP,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      ALLOW,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("leave over the app's tables", BOOT, () => {
  it("saves a type, books, approves and cancels leave in enum columns", async () => {
    await expect(
      run(`do $$
declare
  v_type jsonb;
  v_type_id uuid;
  v_request jsonb;
  v_id uuid;
begin
  ${SERVICE}
  v_type := better_supabase.save_leave_type('${TENANT}', 'vacation', 'Vacation');
  v_type_id := (v_type ->> 'id')::uuid;
  v_type := better_supabase.save_leave_type('${TENANT}', 'vacation', 'Holiday', 'days');
  if (v_type ->> 'id')::uuid <> v_type_id or (select label from public.absence_kinds where id = v_type_id) <> 'Holiday' then
    raise exception 'saved %', v_type;
  end if;
  perform better_supabase.adjust_leave_balance('${TENANT}', '${ALICE}', v_type_id, 10, 2099);
  ${AS_ALICE}
  v_request := better_supabase.request_leave('${TENANT}', v_type_id, '2099-03-02', '2099-03-08');
  v_id := (v_request ->> 'id')::uuid;
  if (select part from public.absences where id = v_id) <> 'full' or (select days from public.absences where id = v_id) <> 5 then
    raise exception 'requested %', v_request;
  end if;
  perform better_supabase.approve_leave_request(v_id);
  if (select approved_at from public.absences where id = v_id) is null then
    raise exception 'not approved';
  end if;
  ${SERVICE}
  v_request := better_supabase.cancel_leave_request(v_id);
  if (select cancelled_at from public.absences where id = v_id) is null then
    raise exception 'not cancelled %', v_request;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a note the app's table has no column for", async () => {
    await expect(
      run(`do $$
declare
  v_type_id uuid;
begin
  ${SERVICE}
  v_type_id := (better_supabase.save_leave_type('${TENANT}', 'vacation', 'Vacation') ->> 'id')::uuid;
  perform better_supabase.adjust_leave_balance('${TENANT}', '${ALICE}', v_type_id, 10, 2099);
  ${AS_ALICE}
  perform better_supabase.request_leave('${TENANT}', v_type_id, '2099-03-02', '2099-03-08', 'full', null, 'beach');
end;
$$;`),
    ).rejects.toThrow(/no note column/);
  });
});
