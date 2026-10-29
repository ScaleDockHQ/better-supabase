import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";
import type { BlockSqlAccessProvider } from "../../../src/sql/module-types.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const REQUESTER = "22222222-2222-4222-8222-222222222222";
const BEN = "33333333-3333-4333-8333-333333333333";
const ANA = "44444444-4444-4444-8444-444444444444";
const CARL = "55555555-5555-4555-8555-555555555555";
const REQUESTER_EMPLOYEE = "66666666-6666-4666-8666-666666666666";
const BEN_EMPLOYEE = "77777777-7777-4777-8777-777777777777";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const COVERS = `
create schema if not exists authz;
create table authz.covers (cover uuid not null, absent uuid not null);
create function authz.ids_with(permission text) returns setof uuid
  language sql stable as $$ select null::uuid where false $$;
create function authz.is_platform(permission text) returns boolean
  language sql stable as $$ select false $$;
create function authz.is_approver(kind text, subject text, tenant uuid, requester uuid, approvers jsonb)
  returns boolean
  language sql stable as $$
    select (approvers ->> 'required')::integer = 1 and exists (
      select 1 from authz.covers c
      where c.cover = auth.uid() and c.absent is distinct from requester
        and coalesce(approvers -> 'users', '[]'::jsonb) ? c.absent::text
    )
  $$;
grant usage on schema authz to authenticated;
`;

const PROVIDER: BlockSqlAccessProvider = {
  name: "test",
  scope: "organization",
  idType: "uuid",
  functions: {
    idsWith: "authz.ids_with({permission})",
    isPlatform: "authz.is_platform({permission})",
    isApprover:
      "authz.is_approver({kind}, {subject}, {tenant}, {requester}, {approvers})",
  },
};

const STAFF = `
create table public.staff (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  user_id uuid,
  name text not null,
  manager_id uuid references public.staff (id),
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
`;

const EMPLOYEES: AnyBlocksConfig = {
  employees: {
    tables: {
      employees: "public.staff",
      privateDetails: null,
      contracts: null,
    },
    columns: {
      employees: {
        email: null,
        jobTitle: null,
        team: null,
        employmentType: null,
        startDate: null,
        endDate: null,
        offboardReason: null,
        originType: null,
        originId: null,
        createdBy: null,
      },
    },
    values: { employees: { status: { offboarded: "ended" } } },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '', true);`;

const as = (user: string): string =>
  `perform set_config('request.jwt.claims', '{"role":"authenticated","sub":"${user}"}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);`;

const BOOT = { timeout: 90_000 };

async function run(
  files: ReturnType<typeof renderBlocks>,
  setup: string,
  check: string,
): Promise<void> {
  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      setup,
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

const steps = (users: readonly string[]) => ({
  approve: { steps: [{ approvers: { users } }] },
});

const coverFiles = () =>
  renderBlocks(["approvals"], {
    modules: {
      permissions: { model: "provider" },
      approvals: {
        options: { policies: { named: steps([BEN]), other: steps([CARL]) } },
      },
    },
    accessProvider: PROVIDER,
  });

const managerFiles = () =>
  renderBlocks(["employees", "approvals"], {
    modules: {
      ...EMPLOYEES,
      approvals: {
        options: {
          policies: {
            leave: { approve: { steps: [{ approvers: { manager: true } }] } },
          },
        },
      },
    },
    ownTables: { "public.staff": "app.sql" },
  });

describe("the approvals block and the provider's isApprover", BOOT, () => {
  it("fills {approvers} with the current step's approvers and required count", () => {
    const sql = coverFiles()
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      `authz.is_approver(v_req."subject_type" || '.' || v_req."action", v_req."subject_id"::text, v_req."tenant_id", v_req."requested_by", (coalesce(v_approvers, '{}'::jsonb) || jsonb_build_object('required', coalesce(v_step -> 'required', '1'::jsonb))))`,
    );
  });

  it("lets a cover decide for an approver the current step names, and nowhere else", async () => {
    await expect(
      run(
        coverFiles(),
        COVERS,
        `insert into authz.covers (cover, absent) values ('${ANA}', '${BEN}');
do $$
declare
  v_named uuid;
  v_other uuid;
begin
  ${SERVICE}
  v_named := (better_supabase.request_approval('${TENANT}', 'named', 'n-1', 'approve') ->> 'id')::uuid;
  v_other := (better_supabase.request_approval('${TENANT}', 'other', 'o-1', 'approve') ->> 'id')::uuid;
  update better_supabase.approval_requests set requested_by = '${REQUESTER}' where id in (v_named, v_other);
  ${as(ANA)}
  if not better_supabase.approval_eligible(v_named) then
    raise exception 'the cover could not decide for the named approver';
  end if;
  if better_supabase.approval_eligible(v_other) then
    raise exception 'the cover decides a step that does not name the absent approver';
  end if;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses a manager whose employee row has the mapped offboarded status", async () => {
    await expect(
      run(
        managerFiles(),
        STAFF,
        `insert into auth.users (id) values ('${REQUESTER}'), ('${BEN}') on conflict do nothing;
insert into better_supabase.memberships (organization_id, user_id, role)
  select '${TENANT}', u, 'member' from unnest(array['${REQUESTER}', '${BEN}']::uuid[]) u
  on conflict do nothing;
insert into public.staff (id, tenant_id, user_id, name, manager_id, status) values
  ('${BEN_EMPLOYEE}', '${TENANT}', '${BEN}', 'Ben', null, 'ended'),
  ('${REQUESTER_EMPLOYEE}', '${TENANT}', '${REQUESTER}', 'Rae', '${BEN_EMPLOYEE}', 'active');
do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.request_approval('${TENANT}', 'leave', 'l-1', 'approve') ->> 'id')::uuid;
  update better_supabase.approval_requests set requested_by = '${REQUESTER}' where id = v_id;
  ${as(BEN)}
  if better_supabase.approval_eligible(v_id) then
    raise exception 'an ended manager decides';
  end if;
  update public.staff set status = 'active' where id = '${BEN_EMPLOYEE}';
  if not better_supabase.approval_eligible(v_id) then
    raise exception 'an active manager could not decide';
  end if;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });
});
