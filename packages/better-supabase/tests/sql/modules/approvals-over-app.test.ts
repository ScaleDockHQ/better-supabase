import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";
import type { BlockSqlAccessProvider } from "../../../src/sql/module-types.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const OWNER = "22222222-2222-4222-8222-222222222222";
const REQUESTER = "33333333-3333-4333-8333-333333333333";
const REVIEWER = "44444444-4444-4444-8444-444444444444";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The approval tables an authorization provider owns: renamed columns, enum
// statuses, the provider's own columns, and no policy, step, reason, payload,
// expiry, reminder, delegate or comment columns.
const APP = `
create type public.request_state as enum ('pending', 'approved', 'rejected', 'cancelled', 'expired');
create type public.verdict as enum ('approved', 'rejected', 'delegated');

create table public.access_approvals (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  subject_type text not null,
  subject_id text not null,
  action text not null,
  state public.request_state not null default 'pending',
  requested_by uuid,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  external_token text,
  external_request jsonb
);

create table public.access_verdicts (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.access_approvals (id) on delete cascade,
  org_id uuid not null,
  step integer not null default 0,
  approver uuid,
  verdict public.verdict not null,
  created_at timestamptz not null default clock_timestamp()
);

create schema if not exists authz;
create function authz.ids_with(permission text) returns setof uuid
  language sql stable as $$ select null::uuid where false $$;
create function authz.is_platform(permission text) returns boolean
  language sql stable as $$ select false $$;
create function authz.is_approver(kind text, subject text, tenant uuid) returns boolean
  language sql stable as $$
    select kind = 'refund.approve' and subject is not null
      and auth.uid() in ('${REVIEWER}'::uuid, '${REQUESTER}'::uuid)
  $$;
grant usage on schema authz to authenticated;
`;

const OWN_TABLES = {
  "public.access_approvals": "app.sql",
  "public.access_verdicts": "app.sql",
};

const PROVIDER: BlockSqlAccessProvider = {
  name: "test",
  scope: "organization",
  idType: "uuid",
  functions: {
    idsWith: "authz.ids_with({permission})",
    isPlatform: "authz.is_platform({permission})",
    isApprover: "authz.is_approver({kind}, {subject}, {tenant})",
  },
};

const approvals = {
  tables: {
    requests: "public.access_approvals",
    decisions: "public.access_verdicts",
  },
  columns: {
    requests: {
      tenant: "org_id",
      status: "state",
      decidedAt: "closed_at",
      policy: null,
      step: null,
      reason: null,
      payload: null,
      expiresAt: null,
      remindedAt: null,
    },
    decisions: {
      request: "request_id",
      tenant: "org_id",
      decision: "verdict",
      delegateTo: null,
      comment: null,
    },
  },
  options: {
    policies: {
      refund: {
        approve: { steps: [{ approvers: { users: [OWNER] }, required: 1 }] },
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '', true);`;

const as = (user: string): string =>
  `perform set_config('request.jwt.claims', '{"role":"authenticated","sub":"${user}"}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string, provider: boolean): Promise<void> {
  const modules: AnyBlocksConfig = provider
    ? { permissions: { model: "provider" }, approvals }
    : { approvals };

  const files = renderBlocks(["approvals"], {
    modules,
    ownTables: OWN_TABLES,
    ...(provider ? { accessProvider: PROVIDER } : {}),
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
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("approvals over the app's tables", BOOT, () => {
  it("decides through isApprover and keeps the provider's columns", async () => {
    await expect(
      run(
        `do $$
declare
  v_req jsonb;
  v_id uuid;
  v_other uuid;
begin
  ${SERVICE}
  v_req := better_supabase.request_approval('${TENANT}', 'refund', 'r-1', 'approve');
  v_id := (v_req ->> 'id')::uuid;
  if v_req ->> 'status' <> 'pending' or (v_req ->> 'step')::integer <> 0 or v_req -> 'reason' <> 'null'::jsonb
    or jsonb_array_length(v_req -> 'steps') <> 1 then
    raise exception 'requested %', v_req;
  end if;
  update public.access_approvals set requested_by = '${REQUESTER}', external_token = 'tok-1', external_request = '{"ref": 7}'
    where id = v_id;

  ${as(REQUESTER)}
  if better_supabase.approval_eligible(v_id) then
    raise exception 'the requester may decide';
  end if;

  ${as(REVIEWER)}
  if not (better_supabase.get_approval(v_id) ->> 'canDecide')::boolean then
    raise exception 'isApprover did not let the reviewer decide';
  end if;
  v_req := better_supabase.decide_approval(v_id, 'approved');
  if v_req ->> 'status' <> 'approved' or v_req ->> 'decidedAt' is null then
    raise exception 'decided %', v_req;
  end if;
  if (select state from public.access_approvals where id = v_id) <> 'approved'
    or (select external_token from public.access_approvals where id = v_id) <> 'tok-1'
    or (select external_request from public.access_approvals where id = v_id) <> '{"ref": 7}'::jsonb then
    raise exception 'the app row is %', (select to_jsonb(a) from public.access_approvals a where id = v_id);
  end if;
  if (select verdict from public.access_verdicts where request_id = v_id) <> 'approved' then
    raise exception 'no approved verdict';
  end if;

  ${SERVICE}
  v_other := (better_supabase.request_approval('${TENANT}', 'refund', 'r-2', 'approve') ->> 'id')::uuid;
  ${as(OWNER)}
  v_req := better_supabase.decide_approval(v_other, 'rejected');
  if v_req ->> 'status' <> 'rejected' then
    raise exception 'rejected %', v_req;
  end if;

  ${SERVICE}
  v_other := (better_supabase.request_approval('${TENANT}', 'refund', 'r-3', 'approve') ->> 'id')::uuid;
  if better_supabase.cancel_approval(v_other) ->> 'status' <> 'cancelled' then
    raise exception 'not cancelled';
  end if;
  if jsonb_array_length(better_supabase.list_approvals('${TENANT}', 'approved')) <> 1
    or jsonb_array_length(better_supabase.list_approvals('${TENANT}', null)) <> 3 then
    raise exception 'list_approvals %', better_supabase.list_approvals('${TENANT}', null);
  end if;
  if not better_supabase.is_approved('refund', 'r-1', 'approve') or better_supabase.is_approved('refund', 'r-2', 'approve') then
    raise exception 'is_approved is wrong';
  end if;
  if better_supabase.expire_approvals() <> 0 or better_supabase.remind_approvals(interval '0 seconds') <> 0 then
    raise exception 'expiry or reminders ran without their columns';
  end if;
end;
$$;`,
        true,
      ),
    ).resolves.toBeUndefined();
  });

  it("keeps the built-in approvers without a provider", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.request_approval('${TENANT}', 'refund', 'r-1', 'approve') ->> 'id')::uuid;
  ${as(REVIEWER)}
  if better_supabase.approval_eligible(v_id) then
    raise exception 'the reviewer may decide without a provider';
  end if;
  ${as(OWNER)}
  if better_supabase.decide_approval(v_id, 'approved') ->> 'status' <> 'approved' then
    raise exception 'the named approver could not approve';
  end if;
end;
$$;`,
        false,
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses a reason the app's table has no column for", async () => {
    await expect(
      run(
        `do $$
begin
  ${SERVICE}
  perform better_supabase.request_approval('${TENANT}', 'refund', 'r-1', 'approve', 'please');
end;
$$;`,
        false,
      ),
    ).rejects.toThrow(/no reason column/);
  });

  it("refuses a delegation the app's table has no column for", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.request_approval('${TENANT}', 'refund', 'r-1', 'approve') ->> 'id')::uuid;
  ${as(OWNER)}
  perform better_supabase.delegate_approval(v_id, '${REVIEWER}');
end;
$$;`,
        false,
      ),
    ).rejects.toThrow(/no delegate column/);
  });
});
