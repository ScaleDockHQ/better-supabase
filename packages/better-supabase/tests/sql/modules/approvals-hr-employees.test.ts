import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";
const ALICE_EMPLOYEE = "44444444-4444-4444-8444-444444444444";
const BOB_EMPLOYEE = "55555555-5555-4555-8555-555555555555";
const DANA_EMPLOYEE = "66666666-6666-4666-8666-666666666666";

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
  ('${ALICE_EMPLOYEE}', '${TENANT}', '${ALICE}', 'Alice', '${BOB_EMPLOYEE}'),
  ('${DANA_EMPLOYEE}', '${TENANT}', null, 'Dana', '${BOB_EMPLOYEE}');
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
  "time-entries": {
    options: { owner: "employee", policy: MANAGER, overlap: "allow" },
  },
  expenses: {
    tables: { reports: null, lines: null },
    options: { owner: "employee", standaloneApprovals: true, policy: MANAGER },
  },
};

const NAMES = ["employees", "leave", "time-entries", "expenses"] as const;

const BOOT = { timeout: 90_000 };

const render = (modules: AnyBlocksConfig, names: readonly string[] = NAMES) =>
  renderBlocks(names, { modules });

async function run(
  check: string,
  blocks: AnyBlocksConfig = BLOCKS,
  allow: string = ALLOW,
): Promise<void> {
  const files = render(blocks).map((file) => ({
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
        .filter((file) => file.kind === "schema")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      allow,
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
  if v_approval = any (select better_supabase.approval_eligible_ids('${TENANT}')) then
    raise exception 'the set lists the employee own leave';
  end if;
  ${as(BOB)}
  if v_approval <> all (select better_supabase.approval_eligible_ids('${TENANT}')) then
    raise exception 'the set misses the manager step';
  end if;
  perform better_supabase.decide_approval(v_approval, 'approved');
  if (select approved_at from better_supabase.leave_requests where id = (v_request ->> 'id')::uuid) is null then
    raise exception 'the manager could not approve';
  end if;
end;
$$;`),
      ).resolves.toBeUndefined();
    });

    it("drops a manager whose employment ended from the manager step of leave, weeks and expenses", async () => {
      await expect(
        run(`do $$
declare
  v_type uuid;
  v_leave uuid;
  v_sheet uuid;
  v_expense uuid;
  v_approval uuid;
begin
  ${as(BOB)}
  v_type := (better_supabase.save_leave_type('${TENANT}', 'holiday', 'Holiday', 'days', true, false) ->> 'id')::uuid;
  update better_supabase.employees set start_date = '2020-01-01', end_date = current_date - 1 where id = '${BOB_EMPLOYEE}';
  ${as(ALICE)}
  v_leave := (better_supabase.request_leave('${TENANT}', v_type, '2099-03-02', '2099-03-03') ->> 'approvalId')::uuid;
  perform better_supabase.log_time('${TENANT}', '2099-03-02T09:00:00Z', '2099-03-02T10:00:00Z');
  v_sheet := (better_supabase.submit_timesheet('${TENANT}', '2099-03-02') ->> 'id')::uuid;
  v_expense := (better_supabase.create_expense('${TENANT}', '2099-03-02', 1250, 'EUR') ->> 'id')::uuid;
  perform better_supabase.submit_expense(v_expense);
  ${as(BOB)}
  foreach v_approval in array array[
    v_leave,
    (select id from better_supabase.approval_requests where subject_type = 'timesheet' and subject_id = v_sheet::text and status = 'pending'),
    (select id from better_supabase.approval_requests where subject_type = 'expense' and subject_id = v_expense::text and status = 'pending')
  ] loop
    if v_approval is null or better_supabase.approval_eligible(v_approval)
      or v_approval = any (select better_supabase.approval_eligible_ids('${TENANT}')) then
      raise exception 'Bob still decides % after his employment ended', v_approval;
    end if;
  end loop;
end;
$$;`),
      ).resolves.toBeUndefined();
    });

    it("keeps approval_eligible_ids in step with approval_eligible for role approvers", async () => {
      await expect(
        run(`do $$
declare
  v_type uuid;
  v_approval uuid;
  u uuid;
begin
  ${as(ALICE)}
  v_type := (better_supabase.save_leave_type('${TENANT}', 'holiday', 'Holiday', 'days', true, false) ->> 'id')::uuid;
  v_approval := (better_supabase.request_leave('${TENANT}', v_type, '2099-03-02', '2099-03-03') ->> 'approvalId')::uuid;
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  update better_supabase.memberships set role = 'admin' where user_id = '${BOB}';
  update better_supabase.approval_requests
    set policy = jsonb_build_object('steps', jsonb_build_array(jsonb_build_object('approvers', jsonb_build_object('role', 'admin'), 'required', 1)), 'selfApproval', false)
    where id = v_approval;
  foreach u in array array['${ALICE}', '${BOB}']::uuid[] loop
    perform set_config('request.jwt.claims', jsonb_build_object('sub', u, 'role', 'authenticated')::text, true);
    if better_supabase.approval_eligible(v_approval) is distinct from (v_approval = any (select better_supabase.approval_eligible_ids())) then
      raise exception 'the role step differs for %', u;
    end if;
  end loop;
  ${as(BOB)}
  if not better_supabase.approval_eligible(v_approval) then
    raise exception 'an admin member decides the role step';
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

    it("files for an employee without a login with no requester, so the member who filed decides", async () => {
      await expect(
        run(`do $$
declare
  v_type uuid;
  v_expense uuid;
  v_sheet uuid;
  v_approvals uuid[];
  v_approval uuid;
begin
  ${as(BOB)}
  v_type := (better_supabase.save_leave_type('${TENANT}', 'holiday', 'Holiday', 'days', true, false) ->> 'id')::uuid;
  v_approvals := array[(better_supabase.request_leave('${TENANT}', v_type, '2099-03-02', '2099-03-03', employee_id => '${DANA_EMPLOYEE}') ->> 'approvalId')::uuid];
  perform better_supabase.log_time('${TENANT}', '2099-03-02T09:00:00Z', '2099-03-02T10:00:00Z', employee_id => '${DANA_EMPLOYEE}');
  v_sheet := (better_supabase.submit_timesheet('${TENANT}', '2099-03-02', employee_id => '${DANA_EMPLOYEE}') ->> 'id')::uuid;
  v_approvals := v_approvals || (select id from better_supabase.approval_requests where subject_type = 'timesheet' and subject_id = v_sheet::text and status = 'pending');
  v_expense := (better_supabase.create_expense('${TENANT}', '2099-03-02', 1250, 'EUR', employee_id => '${DANA_EMPLOYEE}') ->> 'id')::uuid;
  perform better_supabase.submit_expense(v_expense);
  v_approvals := v_approvals || (select id from better_supabase.approval_requests where subject_type = 'expense' and subject_id = v_expense::text and status = 'pending');
  foreach v_approval in array v_approvals loop
    if v_approval is null or (select requested_by from better_supabase.approval_requests where id = v_approval) is not null then
      raise exception 'the filer became the requester of %', v_approval;
    end if;
  end loop;
  foreach v_approval in array v_approvals[1:2] loop
    if not better_supabase.approval_eligible(v_approval) then
      raise exception 'the manager who filed can''t decide %', v_approval;
    end if;
    perform better_supabase.decide_approval(v_approval, 'approved');
  end loop;
  if better_supabase.get_timesheet('${TENANT}', '2099-03-02', null, '${DANA_EMPLOYEE}') ->> 'status' <> 'approved'
    or (select approved_at from better_supabase.leave_requests where approval_id = v_approvals[1]) is null then
    raise exception 'not approved';
  end if;
end;
$$;`),
      ).resolves.toBeUndefined();
    });

    it("keeps a request rejected before the approvals mode closed, unless it was approved after", async () => {
      await expect(
        run(`do $$
declare
  v_type uuid;
  v_id uuid;
begin
  ${as(BOB)}
  v_type := (better_supabase.save_leave_type('${TENANT}', 'holiday', 'Holiday', 'days', true, false) ->> 'id')::uuid;
  v_id := (better_supabase.request_leave('${TENANT}', v_type, '2099-03-02', '2099-03-03', employee_id => '${ALICE_EMPLOYEE}') ->> 'id')::uuid;
  update better_supabase.approval_requests set status = 'cancelled' where subject_id = v_id::text;
  update better_supabase.leave_requests set approval_id = null, rejected_at = now() where id = v_id;
  if better_supabase.get_leave_request(v_id) ->> 'status' <> 'rejected' then
    raise exception 'a legacy rejection reads %', better_supabase.get_leave_request(v_id) ->> 'status';
  end if;
  if jsonb_array_length(better_supabase.list_leave_requests('${TENANT}', status => 'pending', employee_id => '${ALICE_EMPLOYEE}')) <> 0 then
    raise exception 'a legacy rejection lists as pending';
  end if;
  begin
    perform better_supabase.update_leave_request(v_id, '2099-03-02', '2099-03-04');
    raise exception 'changed a rejected request';
  exception when sqlstate 'PT409' then
    if sqlerrm not like '%only a pending or approved%' then
      raise;
    end if;
  end;
  begin
    perform better_supabase.cancel_leave_request(v_id);
    raise exception 'cancelled a rejected request';
  exception when sqlstate 'PT409' then
    if sqlerrm not like '%was rejected%' then
      raise;
    end if;
  end;
  update better_supabase.leave_requests set approved_at = now() where id = v_id;
  if better_supabase.get_leave_request(v_id) ->> 'status' <> 'approved' then
    raise exception 'approved_at does not win over rejected_at';
  end if;
  if better_supabase.cancel_leave_request(v_id) ->> 'status' <> 'cancelled' then
    raise exception 'an approved request with a stale rejected_at was not cancelled';
  end if;
end;
$$;`),
      ).resolves.toBeUndefined();
    });

    it("lets options.writer submit and change another employee's time without the manage permission", async () => {
      const blocks: AnyBlocksConfig = {
        ...BLOCKS,
        "time-entries": {
          options: {
            owner: "employee",
            policy: MANAGER,
            overlap: "allow",
            writer: "public.writes_time_for",
          },
        },
      };

      const allow = `${ALLOW}
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select permission <> 'time_entries.manage' $$;
create or replace function public.writes_time_for(tenant uuid, owner uuid)
returns boolean language sql stable as $$
  select case when owner = '${DANA_EMPLOYEE}' then auth.uid() = '${BOB}' end
$$;`;

      await expect(
        run(
          `do $$
declare
  v_entry uuid;
  v_sheet uuid;
begin
  ${as(BOB)}
  v_entry := (better_supabase.log_time('${TENANT}', '2099-03-02T09:00:00Z', '2099-03-02T10:00:00Z', employee_id => '${DANA_EMPLOYEE}') ->> 'id')::uuid;
  perform better_supabase.update_time_entry(v_entry, '{"note": "fixed"}');
  v_sheet := (better_supabase.submit_timesheet('${TENANT}', '2099-03-02', employee_id => '${DANA_EMPLOYEE}') ->> 'id')::uuid;
  perform better_supabase.withdraw_timesheet(v_sheet);
  begin
    perform better_supabase.submit_timesheet('${TENANT}', '2099-03-02', employee_id => '${ALICE_EMPLOYEE}');
    raise exception 'a null answer let Bob submit for Alice';
  exception when insufficient_privilege then
    null;
  end;
  ${as(ALICE)}
  begin
    perform better_supabase.log_time('${TENANT}', '2099-03-02T11:00:00Z', '2099-03-02T12:00:00Z', employee_id => '${DANA_EMPLOYEE}');
    raise exception 'a false answer let Alice log for Dana';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;`,
          blocks,
          allow,
        ),
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
