import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";
const CAROL = "66666666-6666-4666-8666-666666666666";
const DAVE = "77777777-7777-4777-8777-777777777777";
const ALICE_EMPLOYEE = "44444444-4444-4444-8444-444444444444";
const BOB_EMPLOYEE = "55555555-5555-4555-8555-555555555555";
const DAVE_EMPLOYEE = "88888888-8888-4888-8888-888888888888";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// Approvers hold expenses.approve; public.denied takes any other key away.
const ACCESS = `
create table public.approvers (user_id uuid primary key);
create table public.denied (user_id uuid, permission text);
insert into public.approvers values ('${CAROL}');
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$
  select case when permission like '%.approve' then exists (select 1 from public.approvers a where a.user_id = auth.uid())
    else not exists (select 1 from public.denied d where d.user_id = auth.uid() and d.permission = can.permission) end
$$;
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$
  select case when permission like '%.approve' then exists (select 1 from public.approvers a where a.user_id = member)
    else not exists (select 1 from public.denied d where d.user_id = member and d.permission = can_user.permission) end
$$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into auth.users (id) values ('${ALICE}'), ('${BOB}'), ('${CAROL}') on conflict do nothing;
insert into better_supabase.memberships (organization_id, user_id, role)
  select '${TENANT}', u, 'member' from unnest(array['${ALICE}', '${BOB}', '${CAROL}']::uuid[]) u
  on conflict do nothing;
grant usage on schema auth to authenticated;
grant select on public.approvers, public.denied to authenticated;
`;

// Bob manages Alice; Carol is an approver without an employee record.
const ALLOW = `${ACCESS}
insert into better_supabase.employees (id, tenant_id, user_id, name, manager_id) values
  ('${BOB_EMPLOYEE}', '${TENANT}', '${BOB}', 'Bob', null),
  ('${ALICE_EMPLOYEE}', '${TENANT}', '${ALICE}', 'Alice', '${BOB_EMPLOYEE}');
alter table better_supabase.expenses add column invoice_id uuid;
grant insert, update on better_supabase.expenses to authenticated;
create policy expenses_client_write on better_supabase.expenses for update to authenticated using (true);
create policy expenses_client_insert on better_supabase.expenses for insert to authenticated with check (true);
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '', true);`;

const as = (user: string): string =>
  `perform set_config('request.jwt.claims', '{"sub":"${user}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

// Runs `call` and expects it to fail with `state` and a message like `reason`.
const refused = (call: string, state: string, reason: string): string => `
  begin
    ${call};
    raise exception 'allowed: %', ${sqlText(call)};
  exception when others then
    if sqlerrm like 'allowed: %' or sqlstate <> '${state}' or sqlerrm not like '%${reason}%' then
      raise;
    end if;
  end;`;

const sqlText = (text: string): string => `'${text.replaceAll("'", "''")}'`;

const status = (id: string): string =>
  `(select x.status from better_supabase.expenses x where x.id = ${id})`;

const BLOCKS: AnyBlocksConfig = {
  expenses: {
    tables: { reports: null, lines: null },
    options: {
      owner: "employee",
      approver: "manager",
      invoicedColumn: "invoice_id",
    },
  },
};

const BOOT = { timeout: 180_000 };

async function run(
  check: string,
  names: readonly string[] = ["employees", "expenses"],
  modules: AnyBlocksConfig = BLOCKS,
  setup: { readonly before?: string; readonly allow?: string } = {},
): Promise<void> {
  const files = renderBlocks(names, { modules });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      setup.before ?? "",
      ...files
        .filter((file) => file.kind === "schema")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      setup.allow ?? ALLOW,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("expense decisions", BOOT, () => {
  it("walks every allowed transition, stamps the decider and refuses the rest", async () => {
    await expect(
      run(`do $$
declare
  v_id uuid;
  v_row jsonb;
begin
  ${as(ALICE)}
  v_id := (better_supabase.create_expense('${TENANT}', '2099-03-02', 1250, 'EUR', null, 'Taxi') ->> 'id')::uuid;
  ${refused("perform better_supabase.withdraw_expense(v_id)", "PT409", "only a submitted expense is withdrawn")}
  ${as(CAROL)}
  ${refused("perform better_supabase.decide_expense(v_id, true)", "PT409", "only a submitted expense is decided")}
  ${as(ALICE)}
  perform better_supabase.submit_expense(v_id);
  ${refused("perform better_supabase.submit_expense(v_id)", "PT409", "already submitted")}
  if better_supabase.withdraw_expense(v_id) ->> 'status' <> 'draft' then
    raise exception 'submitted to draft';
  end if;
  perform better_supabase.submit_expense(v_id);
  ${refused("perform better_supabase.decide_expense(v_id, true)", "42501", "not allowed to decide")}

  ${as(CAROL)}
  v_row := better_supabase.decide_expense(v_id, false, 'needs a receipt');
  if v_row ->> 'status' <> 'rejected' or v_row ->> 'decidedBy' <> '${CAROL}' or v_row ->> 'decidedAt' is null then
    raise exception 'rejected %', v_row;
  end if;
  ${refused("perform better_supabase.decide_expense(v_id, true)", "PT409", "already decided")}
  ${refused("perform better_supabase.reimburse_expense(v_id)", "PT409", "only an approved expense")}
  ${as(BOB)}
  ${refused("perform better_supabase.submit_expense(v_id)", "42501", "only the owner resubmits")}
  ${as(ALICE)}
  ${refused("perform better_supabase.withdraw_expense(v_id)", "PT409", "already decided")}
  v_row := better_supabase.submit_expense(v_id);
  if v_row ->> 'status' <> 'submitted' or v_row ->> 'decidedBy' is not null or v_row ->> 'decidedAt' is not null or v_row ->> 'decisionNote' is not null then
    raise exception 'rejected to submitted %', v_row;
  end if;

  ${as(BOB)}
  v_row := better_supabase.decide_expense(v_id, true);
  if v_row ->> 'status' <> 'approved' or v_row ->> 'decidedBy' <> '${BOB}' then
    raise exception 'approved by the manager %', v_row;
  end if;
  ${as(ALICE)}
  ${refused("perform better_supabase.withdraw_expense(v_id)", "PT409", "already decided")}
  ${refused("perform better_supabase.reopen_expense(v_id, 'typo')", "42501", "not allowed to reopen")}
  ${as(CAROL)}
  ${refused("perform better_supabase.reopen_expense(v_id, null)", "22023", "needs a reason")}
  v_row := better_supabase.reopen_expense(v_id, 'wrong amount');
  if v_row ->> 'status' <> 'submitted' or v_row ->> 'decidedBy' is not null or v_row ->> 'decidedAt' is not null then
    raise exception 'reopened %', v_row;
  end if;
  ${refused("perform better_supabase.reopen_expense(v_id, 'again')", "PT409", "already open")}
  perform better_supabase.decide_expense(v_id, true);
  perform better_supabase.reimburse_expense(v_id, 'SEPA-1');
  if ${status("v_id")} <> 'reimbursed' or (select reimbursed_by from better_supabase.expenses where id = v_id) <> '${CAROL}' then
    raise exception 'reimbursed';
  end if;
  ${refused("perform better_supabase.reimburse_expense(v_id)", "PT409", "already reimbursed")}
  ${refused("perform better_supabase.reopen_expense(v_id, 'late')", "PT409", "reimbursed expense")}
  ${refused("perform better_supabase.reverse_expense_reimbursement(v_id, ' ')", "22023", "needs a reason")}
  v_row := better_supabase.reverse_expense_reimbursement(v_id, 'the transfer bounced');
  if v_row ->> 'status' <> 'approved' or v_row ->> 'reimbursedAt' is not null or v_row ->> 'reimbursement' is not null
    or (select reimbursed_by from better_supabase.expenses where id = v_id) is not null or v_row ->> 'decidedBy' <> '${CAROL}' then
    raise exception 'reversed %', v_row;
  end if;
  ${refused("perform better_supabase.reverse_expense_reimbursement(v_id, 'twice')", "PT409", "not reimbursed")}

  update better_supabase.expenses set invoice_id = gen_random_uuid() where id = v_id;
  ${refused("perform better_supabase.reopen_expense(v_id, 'billed')", "PT409", "invoiced expense")}
  update better_supabase.expenses set invoice_id = null where id = v_id;

  ${SERVICE}
  ${refused("update better_supabase.expenses set status = 'draft' where id = v_id", "PT409", "status change is not allowed")}
  ${refused("update better_supabase.expenses set status = 'rejected' where id = v_id", "PT409", "status change is not allowed")}
  ${refused("update better_supabase.expenses set amount = 99 where id = v_id", "PT409", "keeps its amount")}
  ${refused(`update better_supabase.expenses set employee_id = '${BOB_EMPLOYEE}' where id = v_id`, "PT409", "changes owner only in draft")}
  update better_supabase.expenses set status = 'reimbursed' where id = v_id;
  ${refused("update better_supabase.expenses set status = 'draft' where id = v_id", "PT409", "status change is not allowed")}
  if (select reimbursed_at from better_supabase.expenses where id = v_id) is null then
    raise exception 'the trigger did not stamp the reimbursement';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses client writes to the status, decision and reimbursement columns", async () => {
    await expect(
      run(`do $$
declare
  v_id uuid;
begin
  ${as(ALICE)}
  v_id := (better_supabase.create_expense('${TENANT}', '2099-03-02', 1250, 'EUR', null, 'Taxi') ->> 'id')::uuid;
  set local role authenticated;
  update better_supabase.expenses set description = 'Taxi to the airport' where id = v_id;
  update better_supabase.expenses set employee_id = '${BOB_EMPLOYEE}' where id = v_id;
  update better_supabase.expenses set employee_id = '${ALICE_EMPLOYEE}' where id = v_id;
  ${refused("update better_supabase.expenses set status = 'submitted' where id = v_id", "42501", "only through the expense functions")}
  ${refused(`update better_supabase.expenses set decided_by = '${ALICE}' where id = v_id`, "42501", "only through the expense functions")}
  ${refused("update better_supabase.expenses set decided_at = now() where id = v_id", "42501", "only through the expense functions")}
  ${refused("update better_supabase.expenses set reimbursed_at = now() where id = v_id", "42501", "only through the expense functions")}
  ${refused(`insert into better_supabase.expenses (tenant_id, employee_id, spent_on, amount, currency, status) values ('${TENANT}', '${ALICE_EMPLOYEE}', '2099-03-02', 1, 'EUR', 'approved')`, "42501", "starts as a draft")}
  ${refused(`insert into better_supabase.expenses (tenant_id, employee_id, spent_on, amount, currency, decided_by) values ('${TENANT}', '${ALICE_EMPLOYEE}', '2099-03-02', 1, 'EUR', '${ALICE}')`, "42501", "starts as a draft")}
  insert into better_supabase.expenses (tenant_id, employee_id, spent_on, amount, currency) values ('${TENANT}', '${ALICE_EMPLOYEE}', '2099-03-02', 1, 'EUR');
  reset role;
  insert into public.denied values ('${ALICE}', 'expenses.manage');
  set local role authenticated;
  ${refused(`update better_supabase.expenses set employee_id = '${BOB_EMPLOYEE}' where id = v_id`, "42501", "not allowed to change the owner")}
  reset role;
  perform better_supabase.submit_expense(v_id);
  set local role authenticated;
  ${refused(`update better_supabase.expenses set employee_id = '${BOB_EMPLOYEE}' where id = v_id`, "PT409", "changes owner only in draft")}
  ${refused("update better_supabase.expenses set amount = 1 where id = v_id", "PT409", "withdraw it to draft first")}
  update better_supabase.expenses set description = 'Taxi home' where id = v_id;
  reset role;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("lets the owner or creator decide only when nobody else can", async () => {
    await expect(
      run(`do $$
declare
  v_mine uuid;
  v_hers uuid;
begin
  ${as(BOB)}
  v_hers := (better_supabase.create_expense('${TENANT}', '2099-03-02', 1250, 'EUR', null, 'Taxi', employee_id => '${ALICE_EMPLOYEE}') ->> 'id')::uuid;
  perform better_supabase.submit_expense(v_hers);
  v_mine := (better_supabase.create_expense('${TENANT}', '2099-03-03', 800, 'EUR', null, 'Lunch') ->> 'id')::uuid;
  perform better_supabase.submit_expense(v_mine);
  insert into public.approvers values ('${BOB}');

  if better_supabase.expense_self_decides(v_hers) or better_supabase.expense_self_decides(v_mine) then
    raise exception 'Bob self-decides while Carol can approve';
  end if;
  ${refused("perform better_supabase.decide_expense(v_hers, true)", "42501", "owner or creator decides only when nobody else can")}
  ${refused("perform better_supabase.decide_expense(v_mine, true)", "42501", "owner or creator decides only when nobody else can")}
  ${SERVICE}
  ${refused(`perform better_supabase.decide_expense(v_mine, true, null, '${BOB}')`, "42501", "owner or creator decides only when nobody else can")}

  if cardinality(better_supabase.expense_self_decides_many(array[v_hers, v_mine])) > 0 then
    raise exception 'the batch helper lets Bob self-decide while Carol can approve';
  end if;

  delete from public.approvers where user_id = '${CAROL}';
  ${as(BOB)}
  if not better_supabase.expense_self_decides(v_hers) or not better_supabase.expense_self_decides(v_mine) then
    raise exception 'Bob does not self-decide as the only approver';
  end if;
  if cardinality(better_supabase.expense_self_decides_many(array[v_hers, v_mine, gen_random_uuid()])) <> 2 then
    raise exception 'the batch helper does not answer like expense_self_decides';
  end if;
  ${as(ALICE)}
  if better_supabase.expense_self_decides(v_hers) then
    raise exception 'Alice self-decides without the approve key';
  end if;
  ${as(BOB)}
  if better_supabase.decide_expense(v_hers, true) ->> 'decidedBy' <> '${BOB}' then
    raise exception 'the creator could not decide as the only approver';
  end if;
  if better_supabase.reopen_expense(v_hers, 'typo') ->> 'status' <> 'submitted' then
    raise exception 'the creator could not reopen as the only decider';
  end if;
  if better_supabase.decide_expense(v_mine, false, 'personal') ->> 'status' <> 'rejected' then
    raise exception 'the owner could not decide as the only approver';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("lets the owner decide when their only manager has no login, whoever sits above", async () => {
    await expect(
      run(`do $$
declare
  v_id uuid;
begin
  insert into auth.users (id) values ('${DAVE}');
  insert into better_supabase.memberships (organization_id, user_id, role) values ('${TENANT}', '${DAVE}', 'member');
  insert into better_supabase.employees (id, tenant_id, user_id, name, manager_id) values ('${DAVE_EMPLOYEE}', '${TENANT}', '${DAVE}', 'Dave', null);
  update better_supabase.employees set user_id = null, manager_id = '${DAVE_EMPLOYEE}' where id = '${BOB_EMPLOYEE}';
  delete from public.approvers;
  insert into public.approvers values ('${ALICE}');
  ${as(ALICE)}
  v_id := (better_supabase.create_expense('${TENANT}', '2099-03-02', 1250, 'EUR', null, 'Taxi') ->> 'id')::uuid;
  perform better_supabase.submit_expense(v_id);
  if not better_supabase.expense_self_decides(v_id) then
    raise exception 'a manager two levels up, who can''t decide, blocks Alice';
  end if;
  if better_supabase.decide_expense(v_id, true) ->> 'status' <> 'approved' then
    raise exception 'Alice could not decide with nobody able to';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("keeps the creator out of an approval request's decision", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
  v_request uuid;
begin
  insert into public.approvers values ('${BOB}');
  ${as(BOB)}
  v_id := (better_supabase.create_expense('${TENANT}', '2099-03-02', 1250, 'EUR', null, 'Taxi', employee_id => '${ALICE_EMPLOYEE}') ->> 'id')::uuid;
  perform better_supabase.submit_expense(v_id);
  v_request := (select r.id from better_supabase.approval_requests r where r.subject_id = v_id::text);
  ${refused("perform better_supabase.decide_approval(v_request, 'approved')", "42501", "not an approver for this step")}
  if exists (select 1 from better_supabase.approval_eligible_ids() i where i = v_request) then
    raise exception 'the creator sees the request in the queue';
  end if;
  ${SERVICE}
  ${refused(`perform better_supabase.decide_approval(v_request, 'approved', null, '${BOB}')`, "42501", "left out of deciding")}
  ${as(CAROL)}
  if not exists (select 1 from better_supabase.approval_eligible_ids() i where i = v_request) then
    raise exception 'Carol does not see the request in the queue';
  end if;
  perform better_supabase.decide_approval(v_request, 'approved');
  if ${status("v_id")} <> 'approved' or (select decided_by from better_supabase.expenses where id = v_id) <> '${CAROL}' then
    raise exception 'Carol could not approve through the request';
  end if;
end;
$$;`,
        ["employees", "approvals", "expenses"],
        {
          expenses: {
            tables: { reports: null, lines: null },
            options: { owner: "employee", standaloneApprovals: true },
          },
        },
      ),
    ).resolves.toBeUndefined();
  });

  it("stamps the creator, keeps it from clients and fails closed without one", async () => {
    await expect(
      run(`do $$
declare
  v_id uuid;
  v_other uuid;
begin
  ${as(ALICE)}
  set local role authenticated;
  insert into better_supabase.expenses (tenant_id, employee_id, spent_on, amount, currency, created_by)
    values ('${TENANT}', '${ALICE_EMPLOYEE}', '2099-03-02', 1250, 'EUR', '${CAROL}') returning id into v_id;
  reset role;
  if (select created_by from better_supabase.expenses where id = v_id) <> '${ALICE}' then
    raise exception 'a client insert keeps the creator it names';
  end if;
  set local role authenticated;
  ${refused("update better_supabase.expenses set created_by = null where id = v_id", "42501", "creator never changes")}
  reset role;
  ${refused(`perform better_supabase.create_expense('${TENANT}', '2099-03-02', 1, 'EUR', employee_id => '${ALICE_EMPLOYEE}', created_by => '${BOB}')`, "42501", "only the service role records")}

  ${SERVICE}
  insert into better_supabase.expenses (tenant_id, employee_id, spent_on, amount, currency)
    values ('${TENANT}', '${ALICE_EMPLOYEE}', '2099-03-02', 1, 'EUR') returning id into v_other;
  if (select created_by from better_supabase.expenses where id = v_other) <> '${ALICE}' then
    raise exception 'a service insert without a creator does not fall back to the owner';
  end if;
  v_other := (better_supabase.create_expense('${TENANT}', '2099-03-02', 1, 'EUR', employee_id => '${ALICE_EMPLOYEE}', created_by => '${BOB}') ->> 'id')::uuid;
  if (select created_by from better_supabase.expenses where id = v_other) <> '${BOB}' then
    raise exception 'the service role could not name the creator';
  end if;

  ${as(ALICE)}
  perform better_supabase.submit_expense(v_id);
  ${SERVICE}
  update better_supabase.expenses set created_by = null where id = v_id;
  ${as(CAROL)}
  ${refused("perform better_supabase.decide_expense(v_id, true)", "42501", "owner or creator decides only when nobody else can")}
  ${SERVICE}
  update better_supabase.expenses set created_by = '${ALICE}' where id = v_id;
  ${as(CAROL)}
  if better_supabase.decide_expense(v_id, true) ->> 'status' <> 'approved' then
    raise exception 'Carol could not decide once the creator is known';
  end if;
  ${SERVICE}
  update better_supabase.expenses set created_by = null where id = v_id;
  ${as(CAROL)}
  ${refused("perform better_supabase.reopen_expense(v_id, 'typo')", "42501", "not allowed to reopen")}
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("counts the managers up the chain with a decider, and reads invoicedCheck", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  insert into auth.users (id) values ('${DAVE}');
  insert into better_supabase.memberships (organization_id, user_id, role) values ('${TENANT}', '${DAVE}', 'member');
  insert into better_supabase.employees (id, tenant_id, user_id, name, manager_id) values ('${DAVE_EMPLOYEE}', '${TENANT}', '${DAVE}', 'Dave', null);
  update better_supabase.employees set manager_id = '${DAVE_EMPLOYEE}' where id = '${BOB_EMPLOYEE}';
  delete from public.approvers;
  insert into public.approvers values ('${ALICE}');
  ${as(ALICE)}
  v_id := (better_supabase.create_expense('${TENANT}', '2099-03-02', 1250, 'EUR', null, 'Taxi') ->> 'id')::uuid;
  perform better_supabase.submit_expense(v_id);
  if better_supabase.expense_self_decides(v_id) then
    raise exception 'Alice self-decides while her chain can decide';
  end if;
  ${refused("perform better_supabase.decide_expense(v_id, true)", "42501", "owner or creator decides only when nobody else can")}
  ${as(DAVE)}
  if better_supabase.decide_expense(v_id, true) ->> 'status' <> 'approved' then
    raise exception 'the decider did not let Dave decide';
  end if;

  insert into public.invoice_links values (v_id, false);
  ${refused("perform better_supabase.reopen_expense(v_id, 'billed')", "PT409", "invoiced expense")}
  update public.invoice_links set cancelled = true;
  if better_supabase.reopen_expense(v_id, 'the invoice was cancelled') ->> 'status' <> 'submitted' then
    raise exception 'an expense on a cancelled invoice could not be reopened';
  end if;

  update better_supabase.employees set user_id = null where id in ('${BOB_EMPLOYEE}', '${DAVE_EMPLOYEE}');
  ${as(ALICE)}
  if not better_supabase.expense_self_decides(v_id) then
    raise exception 'Alice does not self-decide once nobody up the chain has a login';
  end if;
end;
$$;`,
        ["employees", "expenses"],
        {
          expenses: {
            tables: { reports: null, lines: null },
            options: {
              owner: "employee",
              decider: "public.chain_decider",
              invoicedCheck: "public.invoiced",
            },
          },
        },
        {
          before: `
create table public.invoice_links (expense_id uuid, cancelled boolean);
create function public.invoiced(expense_id uuid) returns boolean language sql stable as $$
  select exists (select 1 from public.invoice_links l where l.expense_id = invoiced.expense_id and not l.cancelled)
$$;
create function public.chain_decider(id uuid) returns boolean language sql stable as $$
  select auth.uid() = '${DAVE}'::uuid
$$;`,
        },
      ),
    ).resolves.toBeUndefined();
  });

  it("guards expense reports and their lines like standalone expenses", async () => {
    await expect(
      run(
        `do $$
declare
  v_category uuid;
  v_report uuid;
begin
  ${as(ALICE)}
  v_category := (better_supabase.save_expense_category('${TENANT}', 'travel', 'Travel') ->> 'id')::uuid;
  v_report := (better_supabase.create_expense_report('${TENANT}', 'Trip', 'EUR') ->> 'id')::uuid;
  perform better_supabase.add_expense_line(v_report, v_category, '2099-03-02', 1250, 'Taxi');
  set local role authenticated;
  update better_supabase.expense_reports set title = 'Trip to Berlin' where id = v_report;
  update better_supabase.expense_lines set amount = 1300 where report_id = v_report;
  ${refused("update better_supabase.expense_reports set submitted_at = now() where id = v_report", "42501", "change only through the expense functions")}
  ${refused(`update better_supabase.expense_reports set user_id = '${BOB}' where id = v_report`, "42501", "change only through the expense functions")}
  ${refused(`insert into better_supabase.expense_reports (tenant_id, user_id, title, currency) values ('${TENANT}', '${BOB}', 'Theirs', 'EUR')`, "42501", "draft of the caller")}
  ${refused(`insert into better_supabase.expense_reports (tenant_id, user_id, title, currency, approved_at) values ('${TENANT}', '${ALICE}', 'Approved', 'EUR', now())`, "42501", "draft of the caller")}
  insert into better_supabase.expense_reports (tenant_id, user_id, title, currency) values ('${TENANT}', '${ALICE}', 'Mine', 'EUR');
  reset role;
  perform better_supabase.submit_expense_report(v_report);
  set local role authenticated;
  ${refused("update better_supabase.expense_reports set currency = 'USD' where id = v_report", "PT409", "keeps its owner and currency")}
  ${refused("update better_supabase.expense_lines set amount = 1 where report_id = v_report", "PT409", "lines change")}
  reset role;

  ${as(CAROL)}
  perform better_supabase.decide_expense_report(v_report, false, 'needs a receipt');
  if (select decided_by from better_supabase.expense_reports where id = v_report) <> '${CAROL}' then
    raise exception 'the decider was not stamped';
  end if;
  ${as(ALICE)}
  set local role authenticated;
  update better_supabase.expense_lines set amount = 1200 where report_id = v_report;
  reset role;
  perform better_supabase.submit_expense_report(v_report);
  if (select row(decided_by, decision_note, rejected_at) is not distinct from row(null::uuid, null::text, null::timestamptz) from better_supabase.expense_reports where id = v_report) is not true then
    raise exception 'a resubmission kept the old decision';
  end if;

  ${SERVICE}
  ${refused("update better_supabase.expense_reports set submitted_at = null where id = v_report", "PT409", "not allowed for an expense report")}
  ${refused("update better_supabase.expense_reports set reimbursed_at = now() where id = v_report", "PT409", "not allowed for an expense report")}
  update better_supabase.expense_reports set approved_at = now() where id = v_report;
  if (select decided_by from better_supabase.expense_reports where id = v_report) is not null then
    raise exception 'the service role was stamped as a user';
  end if;
  ${refused("update better_supabase.expense_reports set currency = 'USD' where id = v_report", "PT409", "keeps its owner and currency")}
  ${refused("update better_supabase.expense_lines set amount = 1 where report_id = v_report", "PT409", "keeps its lines")}
  ${refused("delete from better_supabase.expense_lines where report_id = v_report", "PT409", "keeps its lines")}
end;
$$;`,
        ["ledger", "expenses"],
        {
          expenses: {
            columns: { reports: { approval: null } },
            options: { approvals: false },
          },
        },
        {
          allow: `${ACCESS}
grant insert, update, delete on better_supabase.expense_reports, better_supabase.expense_lines to authenticated;
create policy reports_client_write on better_supabase.expense_reports for update to authenticated using (true);
create policy reports_client_insert on better_supabase.expense_reports for insert to authenticated with check (true);
create policy lines_client_write on better_supabase.expense_lines for all to authenticated using (true);
`,
        },
      ),
    ).resolves.toBeUndefined();
  });

  it("backfills the owner as the creator on upgrade, and leaves an owner without a user", async () => {
    const [plan] = upgradePlan(
      [
        { module: "employees", version: 999 },
        { module: "expenses", version: 1 },
      ],
      { modules: BLOCKS },
    );

    const backfill = plan?.steps.map((step) => step.sql).join("\n") ?? "";

    expect(backfill).toContain("created_by");

    await expect(
      run(`do $$
declare
  v_known uuid;
  v_orphan uuid;
begin
  ${SERVICE}
  insert into better_supabase.employees (id, tenant_id, user_id, name) values ('${DAVE_EMPLOYEE}', '${TENANT}', null, 'Dave');
  insert into better_supabase.expenses (tenant_id, employee_id, spent_on, amount, currency)
    values ('${TENANT}', '${ALICE_EMPLOYEE}', '2099-03-02', 1, 'EUR') returning id into v_known;
  insert into better_supabase.expenses (tenant_id, employee_id, spent_on, amount, currency)
    values ('${TENANT}', '${DAVE_EMPLOYEE}', '2099-03-02', 1, 'EUR') returning id into v_orphan;
  update better_supabase.expenses set created_by = null;
  ${backfill.replaceAll("$$", "$bsb$")}
  if (select created_by from better_supabase.expenses where id = v_known) is distinct from '${ALICE}' then
    raise exception 'the backfill did not record the owner';
  end if;
  if (select created_by from better_supabase.expenses where id = v_orphan) is not null then
    raise exception 'the backfill named a creator for an owner without a user';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
