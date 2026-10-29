import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";
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

// Everyone may do everything, so only the manager step decides who approves.
const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into auth.users (id) values ('${ALICE}'), ('${BOB}') on conflict do nothing;
insert into better_supabase.memberships (organization_id, user_id, role)
  select '${TENANT}', u, 'member' from unnest(array['${ALICE}', '${BOB}']::uuid[]) u
  on conflict do nothing;
insert into better_supabase.employees (id, tenant_id, user_id, name, manager_id) values
  ('${BOB_EMPLOYEE}', '${TENANT}', '${BOB}', 'Bob', null),
  ('${ALICE_EMPLOYEE}', '${TENANT}', '${ALICE}', 'Alice', '${BOB_EMPLOYEE}');
`;

const as = (user: string): string =>
  `perform set_config('request.jwt.claims', '{"sub":"${user}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const MANAGER = { steps: [{ approvers: { manager: true } }] };

const BLOCKS: AnyBlocksConfig = {
  leave: {
    options: { owner: "employee", approvalOwner: "employee", policy: MANAGER },
  },
  "time-tracking": {
    options: { owner: "employee", policy: MANAGER, overlap: "allow" },
  },
  expenses: {
    tables: { reports: null, lines: null },
    options: { owner: "employee", standaloneApprovals: true, policy: MANAGER },
  },
};

const NAMES = ["employees", "leave", "time-tracking", "expenses"] as const;

const BOOT = { timeout: 90_000 };

const render = (modules: AnyBlocksConfig, names: readonly string[] = NAMES) =>
  renderBlocks(names, { modules });

async function run(check: string): Promise<void> {
  const files = render(BLOCKS).map((file) => ({
    ...file,
    contents: file.contents
      .replace(
        "create extension if not exists btree_gist with schema extensions;",
        "",
      )
      .replace(
        'create extension if not exists "btree_gist" with schema "extensions";',
        "",
      ),
  }));

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
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

const sqlOf = (modules: AnyBlocksConfig, names: readonly string[]): string =>
  render(modules, names)
    .map((file) => file.contents)
    .join("\n");

describe(
  "leave, timesheets and expenses through the approvals block per employee",
  BOOT,
  () => {
    it("asks the employee's manager for leave a manager books, never the employee", async () => {
      await expect(
        run(`do $$
declare
  v_type uuid;
  v_request jsonb;
  v_approval uuid;
begin
  ${as(BOB)}
  v_type := (better_supabase.save_leave_type('${TENANT}', 'holiday', 'Holiday', 'days', true, false) ->> 'id')::uuid;
  v_request := better_supabase.request_leave('${TENANT}', v_type, '2099-03-02', '2099-03-03', employee_id => '${ALICE_EMPLOYEE}');
  v_approval := (v_request ->> 'approvalId')::uuid;
  if (select requested_by from better_supabase.approval_requests where id = v_approval) <> '${ALICE}' then
    raise exception 'the filer is the requester';
  end if;
  ${as(ALICE)}
  if better_supabase.approval_eligible(v_approval) then
    raise exception 'the employee approves their own leave';
  end if;
  ${as(BOB)}
  perform better_supabase.decide_approval(v_approval, 'approved');
  if (select approved_at from better_supabase.leave_requests where id = (v_request ->> 'id')::uuid) is null then
    raise exception 'the manager could not approve';
  end if;
end;
$$;`),
      ).resolves.toBeUndefined();
    });

    it("decides an employee's week through its approval request", async () => {
      await expect(
        run(`do $$
declare
  v_sheet jsonb;
  v_approval uuid;
begin
  ${as(ALICE)}
  perform better_supabase.log_time('${TENANT}', '2099-03-02T09:00:00Z', '2099-03-02T10:00:00Z');
  v_sheet := better_supabase.submit_timesheet('${TENANT}', '2099-03-02');
  select id into v_approval from better_supabase.approval_requests
    where subject_type = 'timesheet' and subject_id = v_sheet ->> 'id' and status = 'pending';
  if v_approval is null or better_supabase.approval_eligible(v_approval) then
    raise exception 'no request, or Alice decides her own week';
  end if;
  ${as(BOB)}
  begin
    perform better_supabase.approve_timesheet((v_sheet ->> 'id')::uuid);
    raise exception 'decided around the approval request';
  exception when others then
    if sqlerrm not like '%through its approval request%' then
      raise;
    end if;
  end;
  perform better_supabase.decide_approval(v_approval, 'rejected', 'Missing Friday');
  v_sheet := better_supabase.get_timesheet('${TENANT}', '2099-03-02', null, '${ALICE_EMPLOYEE}');
  if v_sheet ->> 'status' <> 'rejected' or v_sheet ->> 'decisionNote' <> 'Missing Friday' or v_sheet ->> 'decidedBy' <> '${BOB}' then
    raise exception 'rejected %', v_sheet;
  end if;
  ${as(ALICE)}
  perform better_supabase.submit_timesheet('${TENANT}', '2099-03-02');
  select id into v_approval from better_supabase.approval_requests
    where subject_type = 'timesheet' and subject_id = v_sheet ->> 'id' and status = 'pending';
  ${as(BOB)}
  perform better_supabase.decide_approval(v_approval, 'approved');
  if better_supabase.get_timesheet('${TENANT}', '2099-03-02', null, '${ALICE_EMPLOYEE}') ->> 'status' <> 'approved' then
    raise exception 'not approved';
  end if;
end;
$$;`),
      ).resolves.toBeUndefined();
    });

    it("decides a standalone expense through its approval request", async () => {
      await expect(
        run(`do $$
declare
  v_expense jsonb;
  v_id uuid;
  v_approval uuid;
begin
  ${as(ALICE)}
  v_id := (better_supabase.create_expense('${TENANT}', '2099-03-02', 1250, 'EUR') ->> 'id')::uuid;
  perform better_supabase.submit_expense(v_id);
  select id into v_approval from better_supabase.approval_requests
    where subject_type = 'expense' and subject_id = v_id::text and status = 'pending';
  if v_approval is null or (select requested_by from better_supabase.approval_requests where id = v_approval) <> '${ALICE}' then
    raise exception 'no request for Alice';
  end if;
  ${as(BOB)}
  begin
    perform better_supabase.decide_expense(v_id, true);
    raise exception 'decided around the approval request';
  exception when others then
    if sqlerrm not like '%through its approval request%' then
      raise;
    end if;
  end;
  ${as(ALICE)}
  perform better_supabase.withdraw_expense(v_id);
  if (select status from better_supabase.approval_requests where id = v_approval) <> 'cancelled' then
    raise exception 'withdrawing left the request pending';
  end if;
  perform better_supabase.submit_expense(v_id);
  select id into v_approval from better_supabase.approval_requests
    where subject_type = 'expense' and subject_id = v_id::text and status = 'pending';
  ${as(BOB)}
  perform better_supabase.decide_approval(v_approval, 'approved');
  v_expense := better_supabase.get_expense(v_id);
  if v_expense ->> 'status' <> 'approved' or v_expense ->> 'decidedBy' <> '${BOB}' then
    raise exception 'approved %', v_expense;
  end if;
end;
$$;`),
      ).resolves.toBeUndefined();
    });

    it("keeps the defaults: the filer owns leave approvals and expenses need no approvals", () => {
      const leave = sqlOf({ leave: { options: { owner: "employee" } } }, [
        "employees",
        "leave",
      ]);

      expect(leave).not.toContain("'managerOf', v_owner");

      const expenses = sqlOf(
        {
          expenses: {
            tables: { reports: null, lines: null },
            options: { owner: "employee" },
          },
        },
        ["employees", "expenses"],
      );

      expect(expenses).not.toContain("expense_approval_decided");
      expect(expenses).not.toContain("approval_requests");
    });

    it("refuses the options where they can't apply", () => {
      expect(() =>
        sqlOf({ leave: { options: { approvalOwner: "employee" } } }, ["leave"]),
      ).toThrow(/approvalOwner "employee" needs/);
      expect(() =>
        sqlOf({ expenses: { options: { standaloneApprovals: true } } }, [
          "expenses",
        ]),
      ).toThrow(/standaloneApprovals needs tables.reports: null/);
    });
  },
);
