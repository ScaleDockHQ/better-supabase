import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";
const CAROL = "66666666-6666-4666-8666-666666666666";
const DAVE = "77777777-7777-4777-8777-777777777777";
const ALICE_EMPLOYEE = "44444444-4444-4444-8444-444444444444";
const BOB_EMPLOYEE = "55555555-5555-4555-8555-555555555555";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// Only Carol holds the approve and manage keys. Bob manages Alice, and the
// app's decider accepts Dave, who holds no key.
const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$
  select (permission not like '%.approve' and permission not like '%.manage') or auth.uid() = '${CAROL}'::uuid
$$;
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$
  select (permission not like '%.approve' and permission not like '%.manage') or member = '${CAROL}'::uuid
$$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
create function public.leave_decides(id uuid) returns boolean language sql stable as $$
  select auth.uid() = '${DAVE}'::uuid
$$;
insert into auth.users (id) values ('${ALICE}'), ('${BOB}'), ('${CAROL}'), ('${DAVE}') on conflict do nothing;
insert into better_supabase.memberships (organization_id, user_id, role)
  select '${TENANT}', u, 'member' from unnest(array['${ALICE}', '${BOB}', '${CAROL}', '${DAVE}']::uuid[]) u
  on conflict do nothing;
insert into better_supabase.employees (id, tenant_id, user_id, name, manager_id) values
  ('${BOB_EMPLOYEE}', '${TENANT}', '${BOB}', 'Bob', null),
  ('${ALICE_EMPLOYEE}', '${TENANT}', '${ALICE}', 'Alice', '${BOB_EMPLOYEE}');
`;

const as = (user: string): string =>
  `perform set_config('request.jwt.claims', '{"sub":"${user}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const BOOT = { timeout: 180_000 };

async function run(blocks: AnyBlocksConfig, check: string): Promise<void> {
  const files = renderBlocks(["employees", "leave"], { modules: blocks });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      ...files
        .filter((file) => file.kind === "schema")
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

const TYPE = `${as(CAROL)}
  v_type := (better_supabase.save_leave_type('${TENANT}', 'holiday', 'Holiday', 'days', true, false) ->> 'id')::uuid;`;

const approved = (id: string): string =>
  `(select r.approved_at is not null from better_supabase.leave_requests r where r.id = ${id})`;

describe("leave in approvals mode", BOOT, () => {
  it("lets the app's decider decide a step with decider: true", async () => {
    await expect(
      run(
        { leave: { options: { decider: "public.leave_decides" } } },
        `do $$
declare
  v_type uuid;
  v_id uuid;
  v_approval uuid;
begin
  ${TYPE}
  ${as(ALICE)}
  v_id := (better_supabase.request_leave('${TENANT}', v_type, '2099-03-02', '2099-03-03') ->> 'id')::uuid;
  v_approval := (select r.approval_id from better_supabase.leave_requests r where r.id = v_id);
  if (select a.requested_by from better_supabase.approval_requests a where a.id = v_approval) <> '${ALICE}' then
    raise exception 'the approval is not Alice''s';
  end if;
  ${as(BOB)}
  if better_supabase.approval_eligible(v_approval) then
    raise exception 'a manager outside the policy may decide';
  end if;
  ${as(DAVE)}
  if not better_supabase.approval_eligible(v_approval)
    or not exists (select 1 from better_supabase.approval_eligible_ids('${TENANT}') i where i = v_approval) then
    raise exception 'the decider can''t decide';
  end if;
  perform better_supabase.decide_approval(v_approval, 'approved');
  if not ${approved("v_id")} then
    raise exception 'the decider''s approval did not book the leave';
  end if;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });

  it("lets a requester nobody else can decide for approve their own leave", async () => {
    await expect(
      run(
        { leave: { options: { selfDecideWhenTopOfChain: true } } },
        `do $$
declare
  v_type uuid;
  v_id uuid;
  v_approval uuid;
begin
  ${TYPE}
  ${as(CAROL)}
  v_id := (better_supabase.request_leave('${TENANT}', v_type, '2099-03-02', '2099-03-03') ->> 'id')::uuid;
  v_approval := (select r.approval_id from better_supabase.leave_requests r where r.id = v_id);
  if not better_supabase.approval_eligible(v_approval)
    or not exists (select 1 from better_supabase.approval_eligible_ids('${TENANT}') i where i = v_approval) then
    raise exception 'the top of the chain can''t decide their own leave';
  end if;
  perform better_supabase.decide_approval(v_approval, 'approved');
  if not ${approved("v_id")} then
    raise exception 'the self approval did not book the leave';
  end if;
  ${as(ALICE)}
  v_id := (better_supabase.request_leave('${TENANT}', v_type, '2099-04-06', '2099-04-07') ->> 'id')::uuid;
  v_approval := (select r.approval_id from better_supabase.leave_requests r where r.id = v_id);
  if better_supabase.approval_eligible(v_approval) then
    raise exception 'a requester without the approve key decides their own leave';
  end if;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });

  it("lets the requester decide each step of a two-step policy", async () => {
    await expect(
      run(
        {
          leave: {
            options: {
              selfDecideWhenTopOfChain: true,
              policy: {
                steps: [
                  { approvers: { permission: "leave.approve" } },
                  { approvers: { permission: "leave.approve", manager: true } },
                ],
              },
            },
          },
        },
        `do $$
declare
  v_type uuid;
  v_id uuid;
  v_approval uuid;
begin
  ${TYPE}
  ${as(CAROL)}
  v_id := (better_supabase.request_leave('${TENANT}', v_type, '2099-03-02', '2099-03-03') ->> 'id')::uuid;
  v_approval := (select r.approval_id from better_supabase.leave_requests r where r.id = v_id);
  perform better_supabase.decide_approval(v_approval, 'approved');
  if ${approved("v_id")} then
    raise exception 'one step booked a two-step leave';
  end if;
  perform better_supabase.decide_approval(v_approval, 'approved');
  if not ${approved("v_id")} then
    raise exception 'the second step did not book the leave';
  end if;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });

  it("stamps the approval's decision on the request under its own subject type", async () => {
    await expect(
      run(
        { leave: { options: { approvalSubject: "time_off_request" } } },
        `do $$
declare
  v_type uuid;
  v_id uuid;
  v_approval uuid;
  v_row better_supabase.leave_requests%rowtype;
begin
  ${TYPE}
  ${as(ALICE)}
  v_id := (better_supabase.request_leave('${TENANT}', v_type, '2099-03-02', '2099-03-03') ->> 'id')::uuid;
  select r.approval_id into v_approval from better_supabase.leave_requests r where r.id = v_id;
  if (select a.subject_type from better_supabase.approval_requests a where a.id = v_approval) <> 'time_off_request' then
    raise exception 'the approval is not filed under the configured subject type';
  end if;
  ${as(CAROL)}
  perform better_supabase.decide_approval(v_approval, 'rejected', 'Too busy');
  select * into v_row from better_supabase.leave_requests r where r.id = v_id;
  if v_row.rejected_at is null or v_row.decided_by is distinct from '${CAROL}'::uuid or v_row.decision_note is distinct from 'Too busy' then
    raise exception 'the rejection is not stamped on the request: %', to_jsonb(v_row);
  end if;
  ${as(ALICE)}
  v_id := (better_supabase.request_leave('${TENANT}', v_type, '2099-04-06', '2099-04-07') ->> 'id')::uuid;
  select r.approval_id into v_approval from better_supabase.leave_requests r where r.id = v_id;
  ${as(CAROL)}
  perform better_supabase.decide_approval(v_approval, 'approved', 'Enjoy');
  select * into v_row from better_supabase.leave_requests r where r.id = v_id;
  if v_row.approved_at is null or v_row.decided_by is distinct from '${CAROL}'::uuid or v_row.decision_note is distinct from 'Enjoy' or v_row.rejected_at is not null then
    raise exception 'the approval is not stamped on the request: %', to_jsonb(v_row);
  end if;
  ${as(ALICE)}
  v_id := (better_supabase.request_leave('${TENANT}', v_type, '2099-05-04', '2099-05-05') ->> 'id')::uuid;
  select r.approval_id into v_approval from better_supabase.leave_requests r where r.id = v_id;
  perform better_supabase.cancel_approval(v_approval);
  select * into v_row from better_supabase.leave_requests r where r.id = v_id;
  if v_row.cancelled_at is null or v_row.cancelled_by is distinct from '${ALICE}'::uuid then
    raise exception 'the withdrawn approval did not cancel the request: %', to_jsonb(v_row);
  end if;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });

  it("leaves a request alone when another approval names it", async () => {
    await expect(
      run(
        {
          approvals: {
            options: {
              policies: {
                leave_request: {
                  other: {
                    steps: [{ approvers: { permission: "leave.approve" } }],
                  },
                },
              },
            },
          },
        },
        `do $$
declare
  v_type uuid;
  v_id uuid;
  v_forged uuid;
  v_hint text;
  v_row better_supabase.leave_requests%rowtype;
begin
  ${TYPE}
  ${as(ALICE)}
  v_id := (better_supabase.request_leave('${TENANT}', v_type, '2099-03-02', '2099-03-03') ->> 'id')::uuid;
  ${as(BOB)}
  begin
    perform better_supabase.request_approval('${TENANT}', 'leave_request', v_id::text, 'other');
    raise exception 'a member filed an approval on someone else''s leave';
  exception when insufficient_privilege then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint <> 'APPROVAL_SUBJECT_BLOCK_FILED' then
      raise exception 'hint %', v_hint;
    end if;
  end;
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  v_forged := (better_supabase.request_approval('${TENANT}', 'leave_request', v_id::text, 'other', requested_by => '${BOB}') ->> 'id')::uuid;
  perform better_supabase.cancel_approval(v_forged);
  v_forged := (better_supabase.request_approval('${TENANT}', 'leave_request', v_id::text, 'other', requested_by => '${BOB}') ->> 'id')::uuid;
  ${as(CAROL)}
  perform better_supabase.decide_approval(v_forged, 'rejected', 'forged');
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  v_forged := (better_supabase.request_approval('${TENANT}', 'leave_request', 'not-a-uuid', 'other', requested_by => '${BOB}') ->> 'id')::uuid;
  ${as(CAROL)}
  perform better_supabase.decide_approval(v_forged, 'approved');
  select * into v_row from better_supabase.leave_requests r where r.id = v_id;
  if v_row.cancelled_at is not null or v_row.rejected_at is not null or v_row.approved_at is not null or v_row.decided_by is not null then
    raise exception 'another approval changed the request: %', to_jsonb(v_row);
  end if;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });

  it("approves at once and files nothing when the app says no approval is needed", async () => {
    await expect(
      run(
        {
          leave: {
            options: { approvalRequired: "public.leave_needs_approval" },
          },
        },
        `create function public.leave_needs_approval(tenant uuid, request_id uuid) returns boolean
language sql stable as $f$ select false $f$;
do $$
declare
  v_type uuid;
  v_id uuid;
  v_row better_supabase.leave_requests%rowtype;
begin
  ${TYPE}
  ${as(ALICE)}
  v_id := (better_supabase.request_leave('${TENANT}', v_type, '2099-03-02', '2099-03-03') ->> 'id')::uuid;
  select * into v_row from better_supabase.leave_requests r where r.id = v_id;
  if v_row.approved_at is null or v_row.approval_id is not null
    or exists (select 1 from better_supabase.approval_requests a where a.subject_id = v_id::text) then
    raise exception 'leave that needs no approval filed one: %', to_jsonb(v_row);
  end if;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });

  it("asks approvalRequired once, so a request is always filed or booked", async () => {
    await expect(
      run(
        {
          leave: {
            options: { approvalRequired: "public.flip_needs_approval" },
          },
        },
        `create function public.flip_needs_approval(tenant uuid, id uuid) returns boolean
language plpgsql volatile as $f$
declare
  v_n integer := coalesce(nullif(current_setting('test.flips', true), ''), '0')::integer + 1;
begin
  perform set_config('test.flips', v_n::text, false);
  return v_n % 2 = 0;
end;
$f$;
do $$
declare
  v_type uuid;
  v_id uuid;
  v_row better_supabase.leave_requests%rowtype;
  v_day integer;
begin
  ${TYPE}
  ${as(ALICE)}
  for v_day in 0..3 loop
    v_id := (better_supabase.request_leave('${TENANT}', v_type, date '2099-03-02' + v_day * 7, date '2099-03-02' + v_day * 7) ->> 'id')::uuid;
    select * into v_row from better_supabase.leave_requests r where r.id = v_id;
    if (v_row.approval_id is null) = (v_row.approved_at is null) then
      raise exception 'request % is filed and booked, or neither: %', v_day, to_jsonb(v_row);
    end if;
  end loop;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses an approval subject type that isn't snake case", () => {
    expect(() =>
      renderBlocks(["employees", "leave"], {
        modules: { leave: { options: { approvalSubject: "Time Off" } } },
      }),
    ).toThrow(/approvalSubject/u);
  });

  it("refuses self-decide with approvers it can't count", () => {
    for (const approvers of [
      { role: "admin" },
      { team: "11111111-1111-4111-8111-111111111111" },
      { users: [CAROL] },
      { permission: "leave.manage" },
    ]) {
      expect(() =>
        renderBlocks(["employees", "leave"], {
          modules: {
            leave: {
              options: {
                selfDecideWhenTopOfChain: true,
                policy: { steps: [{ approvers }] },
              },
            },
          },
        }),
      ).toThrow(/counts only/u);
    }
  });
});
