import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";
const CAROL = "66666666-6666-4666-8666-666666666666";
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

// Approvers hold expenses.approve; public.denied takes any other key away.
// Bob manages Alice; Carol is an approver without an employee record.
const ALLOW = `
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
insert into better_supabase.employees (id, tenant_id, user_id, name, manager_id) values
  ('${BOB_EMPLOYEE}', '${TENANT}', '${BOB}', 'Bob', null),
  ('${ALICE_EMPLOYEE}', '${TENANT}', '${ALICE}', 'Alice', '${BOB_EMPLOYEE}');
alter table better_supabase.expenses add column invoice_id uuid;
grant usage on schema auth to authenticated;
grant select on public.approvers, public.denied to authenticated;
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

async function run(check: string): Promise<void> {
  const files = renderBlocks(["employees", "expenses"], { modules: BLOCKS });

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
  ${refused("perform better_supabase.withdraw_expense(v_id)", "55000", "only a submitted expense is withdrawn")}
  ${as(CAROL)}
  ${refused("perform better_supabase.decide_expense(v_id, true)", "55000", "only a submitted expense is decided")}
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
  ${refused("perform better_supabase.reimburse_expense(v_id)", "55000", "only an approved expense")}
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
  ${refused("update better_supabase.expenses set status = 'draft' where id = v_id", "55000", "status change is not allowed")}
  ${refused("update better_supabase.expenses set status = 'rejected' where id = v_id", "55000", "status change is not allowed")}
  ${refused("update better_supabase.expenses set amount = 99 where id = v_id", "55000", "keeps its amount")}
  ${refused(`update better_supabase.expenses set employee_id = '${BOB_EMPLOYEE}' where id = v_id`, "55000", "changes owner only in draft")}
  update better_supabase.expenses set status = 'reimbursed' where id = v_id;
  ${refused("update better_supabase.expenses set status = 'draft' where id = v_id", "55000", "status change is not allowed")}
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
  ${refused(`update better_supabase.expenses set employee_id = '${BOB_EMPLOYEE}' where id = v_id`, "55000", "changes owner only in draft")}
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

  delete from public.approvers where user_id = '${CAROL}';
  ${as(BOB)}
  if not better_supabase.expense_self_decides(v_hers) or not better_supabase.expense_self_decides(v_mine) then
    raise exception 'Bob does not self-decide as the only approver';
  end if;
  ${as(ALICE)}
  if better_supabase.expense_self_decides(v_hers) then
    raise exception 'Alice self-decides without the approve key';
  end if;
  ${as(BOB)}
  if better_supabase.decide_expense(v_hers, true) ->> 'decidedBy' <> '${BOB}' then
    raise exception 'the creator could not decide as the only approver';
  end if;
  if better_supabase.decide_expense(v_mine, false, 'personal') ->> 'status' <> 'rejected' then
    raise exception 'the owner could not decide as the only approver';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
