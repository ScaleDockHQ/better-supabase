import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";
const POLICY = "44444444-4444-4444-8444-444444444444";
const V1 = "55555555-5555-4555-8555-555555555555";
const V2 = "66666666-6666-4666-8666-666666666666";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The app's policy documents, which point at their current version, and its
// own assignment and read-receipt tables without the optional columns.
const APP = `
create table public.policy_docs (
  id uuid primary key,
  organization_id uuid not null,
  title text not null,
  current_version_id uuid
);

create table public.read_requests (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  subject_type text not null,
  subject_id text not null,
  principal_type text not null,
  principal_id text not null,
  due_in_days integer
);

create table public.read_receipts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  subject_type text not null,
  subject_id text not null,
  version_id uuid not null,
  user_id uuid not null,
  acknowledged_at timestamptz not null default now()
);
`;

const BLOCKS: AnyBlocksConfig = {
  acknowledgements: {
    tables: {
      assignments: "public.read_requests",
      acknowledgements: "public.read_receipts",
    },
    columns: {
      assignments: { tenant: "org_id", createdBy: null, createdAt: null },
      acknowledgements: { tenant: "org_id", method: null, signature: null },
    },
    on: {
      policy: {
        table: "public.policy_docs",
        idType: "uuid",
        versionColumn: "current_version_id",
      },
    },
  },
};

const SEED = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into auth.users (id) values ('${ALICE}'), ('${BOB}') on conflict do nothing;
insert into better_supabase.memberships (organization_id, user_id, role)
  values ('${TENANT}', '${ALICE}', 'member'), ('${TENANT}', '${BOB}', 'member')
  on conflict do nothing;
insert into public.policy_docs (id, organization_id, title) values ('${POLICY}', '${TENANT}', 'Security policy');
insert into better_supabase.versions (id, tenant_id, subject_type, subject_id, number, content, content_hash, frozen, created_at)
  values
    ('${V1}', '${TENANT}', 'policy', '${POLICY}', 1, '{"body":"one"}', 'h1', true, now() - interval '5 days'),
    ('${V2}', '${TENANT}', 'policy', '${POLICY}', 2, '{"body":"two"}', 'h2', true, now());
update public.policy_docs set current_version_id = '${V1}';
`;

const as = (user: string): string =>
  `perform set_config('request.jwt.claims', '{"sub":"${user}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["acknowledgements"], {
    modules: BLOCKS,
    ownTables: {
      "public.policy_docs": "app.sql",
      "public.read_requests": "app.sql",
      "public.read_receipts": "app.sql",
    },
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
      SEED,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("acknowledgements over the app's tables", BOOT, () => {
  it("assigns a role, records acknowledgements of the current version and reminds the overdue once", async () => {
    await expect(
      run(`do $$
declare
  v_assignment jsonb;
  v_again jsonb;
  v_ack jsonb;
  v_mine jsonb;
  v_status jsonb;
begin
  ${as(ALICE)}
  v_assignment := better_supabase.assign_acknowledgement('${TENANT}', 'policy', '${POLICY}', 'role', 'member', 1);
  v_again := better_supabase.assign_acknowledgement('${TENANT}', 'policy', '${POLICY}', 'role', 'member', 1);
  if v_again ->> 'id' <> v_assignment ->> 'id' or (select count(*) from public.read_requests) <> 1
    or v_assignment ->> 'createdBy' is not null then
    raise exception 'assignment %', v_again;
  end if;
  begin
    perform better_supabase.assign_acknowledgement('${TENANT}', 'policy', '${POLICY}', 'role', 'nobody');
    raise exception 'an unknown role was accepted';
  exception when others then
    if sqlerrm = 'an unknown role was accepted' then raise; end if;
  end;

  ${as(BOB)}
  v_mine := better_supabase.list_my_acknowledgements('${TENANT}');
  if jsonb_array_length(v_mine) <> 1 or v_mine -> 0 ->> 'versionId' <> '${V1}'
    or (v_mine -> 0 ->> 'overdue')::boolean is not true then
    raise exception 'mine %', v_mine;
  end if;
  begin
    perform better_supabase.acknowledge('policy', '${POLICY}', '${V2}');
    raise exception 'a stale version was accepted';
  exception when others then
    if sqlerrm = 'a stale version was accepted' then raise; end if;
  end;
  v_ack := better_supabase.acknowledge('policy', '${POLICY}');
  perform better_supabase.acknowledge('policy', '${POLICY}');
  if (select count(*) from public.read_receipts) <> 1 or v_ack ->> 'method' <> 'click'
    or v_ack ->> 'versionId' <> '${V1}' then
    raise exception 'ack %', v_ack;
  end if;
  if jsonb_array_length(better_supabase.list_my_acknowledgements('${TENANT}')) <> 0 then
    raise exception 'still pending after acknowledging';
  end if;
  v_status := better_supabase.acknowledgement_status('policy', '${POLICY}');
  if (v_status ->> 'required')::int <> 2 or (v_status ->> 'acknowledged')::int <> 1
    or v_status -> 'pending' -> 0 ->> 'userId' <> '${ALICE}' then
    raise exception 'status %', v_status;
  end if;

  ${SERVICE}
  if better_supabase.notify_due_acknowledgements() <> 1 then
    raise exception 'the overdue member was not notified';
  end if;
  if better_supabase.notify_due_acknowledgements() <> 0 then
    raise exception 'the overdue member was notified twice';
  end if;

  update public.policy_docs set current_version_id = '${V2}';
  ${as(BOB)}
  v_mine := better_supabase.list_my_acknowledgements('${TENANT}');
  if jsonb_array_length(v_mine) <> 1 or v_mine -> 0 ->> 'versionId' <> '${V2}'
    or (v_mine -> 0 ->> 'overdue')::boolean then
    raise exception 'a new version did not ask again %', v_mine;
  end if;
  if jsonb_array_length(better_supabase.acknowledgements_of('policy', '${POLICY}', '${V1}')) <> 1 then
    raise exception 'the first version lost its acknowledgement';
  end if;

  ${as(ALICE)}
  perform better_supabase.unassign_acknowledgement((v_assignment ->> 'id')::uuid);
  if (select count(*) from public.read_requests) <> 0 or (select count(*) from public.read_receipts) <> 1 then
    raise exception 'unassign removed acknowledgements';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
