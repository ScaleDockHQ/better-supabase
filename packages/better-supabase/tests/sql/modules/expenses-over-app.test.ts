import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { withBlockSubjects } from "../../../src/config/block-subjects.ts";
import { adoptedColumnProblems } from "../../../src/sql/adopted-columns.ts";
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

// The app's own expense tables: renamed columns, and no limit, receipt
// threshold, note, ledger transaction or merchant columns.
const APP = `
create table public.spend_categories (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  code text not null,
  title text not null,
  currency text,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.claims (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  owner_id uuid not null,
  title text not null,
  currency text not null,
  approval_id uuid,
  submitted_at timestamptz,
  approved_at timestamptz,
  reimbursed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.claim_items (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  claim_id uuid not null references public.claims (id) on delete cascade,
  category_id uuid not null references public.spend_categories (id),
  spent_on date not null,
  description text not null,
  amount bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
`;

const OWN_TABLES = {
  "public.spend_categories": "app.sql",
  "public.claims": "app.sql",
  "public.claim_items": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  expenses: {
    tables: {
      categories: "public.spend_categories",
      reports: "public.claims",
      lines: "public.claim_items",
    },
    columns: {
      categories: {
        tenant: "org_id",
        key: "code",
        name: "title",
        limitAmount: null,
        receiptOver: null,
      },
      reports: {
        tenant: "org_id",
        user: "owner_id",
        note: null,
        approvalTransaction: null,
        reimbursement: null,
      },
      lines: { tenant: "org_id", report: "claim_id", merchant: null },
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

async function run(
  check: string,
  modules: AnyBlocksConfig = BLOCKS,
  app: string = APP,
): Promise<void> {
  const files = renderBlocks(["expenses"], { modules, ownTables: OWN_TABLES });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      app,
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

describe("expenses over the app's tables", BOOT, () => {
  it("files, submits, approves and reimburses a report", async () => {
    await expect(
      run(`do $$
declare
  v_category uuid;
  v_report jsonb;
  v_id uuid;
begin
  ${SERVICE}
  v_category := (better_supabase.save_expense_category('${TENANT}', 'travel', 'Travel', 'EUR') ->> 'id')::uuid;
  perform better_supabase.save_expense_category('${TENANT}', 'travel', 'Trips', 'EUR');
  if (select count(*) from public.spend_categories) <> 1 or (select title from public.spend_categories where id = v_category) <> 'Trips' then
    raise exception 'category upsert';
  end if;
  ${AS_ALICE}
  v_report := better_supabase.create_expense_report('${TENANT}', 'Conference', 'EUR');
  v_id := (v_report ->> 'id')::uuid;
  perform better_supabase.add_expense_line(v_id, v_category, '2099-01-10', 12500, 'Train');
  if jsonb_array_length(better_supabase.check_expense_report(v_id)) <> 0 then
    raise exception 'violations %', better_supabase.check_expense_report(v_id);
  end if;
  perform better_supabase.submit_expense_report(v_id);
  if (select submitted_at from public.claims where id = v_id) is null then
    raise exception 'not submitted';
  end if;
  perform better_supabase.approve_expense_report(v_id);
  ${SERVICE}
  v_report := better_supabase.reimburse_expense_report(v_id);
  if (select reimbursed_at from public.claims where id = v_id) is null then
    raise exception 'not reimbursed %', v_report;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("files and approves a report over categories without key and currency columns", async () => {
    const expenses = BLOCKS["expenses"];

    await expect(
      run(
        `do $$
declare
  v_category uuid;
  v_id uuid;
begin
  ${SERVICE}
  v_category := (better_supabase.save_expense_category('${TENANT}', null, 'Travel') ->> 'id')::uuid;
  ${AS_ALICE}
  v_id := (better_supabase.create_expense_report('${TENANT}', 'Conference', 'EUR') ->> 'id')::uuid;
  perform better_supabase.add_expense_line(v_id, v_category, '2099-01-10', 12500, 'Train');
  perform better_supabase.submit_expense_report(v_id);
  perform better_supabase.approve_expense_report(v_id);
  if (select approved_at from public.claims where id = v_id) is null then
    raise exception 'not approved';
  end if;
end;
$$;`,
        {
          expenses: {
            ...expenses,
            columns: {
              ...expenses?.columns,
              categories: {
                ...expenses?.columns?.["categories"],
                key: null,
                currency: null,
              },
            },
          },
        },
        APP.replace("  code text not null,\n", "").replace(
          "  currency text,\n  archived_at",
          "  archived_at",
        ),
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses a spend limit the app's table has no column for", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.save_expense_category('${TENANT}', 'travel', 'Travel', 'EUR', 50000);
end;
$$;`),
    ).rejects.toThrow(/no limit column/);
  });

  it("decides reports without the approvals block", async () => {
    const expenses = BLOCKS["expenses"];

    await expect(
      run(
        `do $$
declare
  v_category uuid;
  v_report jsonb;
  v_id uuid;
begin
  ${SERVICE}
  v_category := (better_supabase.save_expense_category('${TENANT}', 'travel', 'Travel', 'EUR') ->> 'id')::uuid;
  ${AS_ALICE}
  v_id := (better_supabase.create_expense_report('${TENANT}', 'Conference', 'EUR') ->> 'id')::uuid;
  perform better_supabase.add_expense_line(v_id, v_category, '2099-01-10', 12500, 'Train');
  v_report := better_supabase.submit_expense_report(v_id);
  if v_report ->> 'status' <> 'submitted' or v_report ->> 'approvalId' is not null then
    raise exception 'submitted %', v_report;
  end if;
  begin
    perform better_supabase.decide_expense_report(v_id, true, null);
    raise exception 'decided own report';
  exception when others then
    if sqlerrm = 'decided own report' then
      raise;
    end if;
  end;
  ${SERVICE}
  v_report := better_supabase.decide_expense_report(v_id, false, 'receipt missing', '${BOB}');
  if v_report ->> 'status' <> 'rejected' or (select decision_note from public.claims where id = v_id) <> 'receipt missing'
    or (select decided_by from public.claims where id = v_id) <> '${BOB}' then
    raise exception 'rejected %', v_report;
  end if;
  ${AS_ALICE}
  perform better_supabase.update_expense_line((select id from public.claim_items where claim_id = v_id), null, null, 12000, null, null);
  v_report := better_supabase.submit_expense_report(v_id);
  if v_report ->> 'status' <> 'submitted' or (select rejected_at from public.claims where id = v_id) is not null then
    raise exception 'resubmitted %', v_report;
  end if;
  ${SERVICE}
  v_report := better_supabase.decide_expense_report(v_id, true, null);
  if v_report ->> 'status' <> 'approved' or (select approved_at from public.claims where id = v_id) is null then
    raise exception 'approved %', v_report;
  end if;
  v_report := better_supabase.reimburse_expense_report(v_id);
  if v_report ->> 'status' <> 'reimbursed' then
    raise exception 'reimbursed %', v_report;
  end if;
end;
$$;`,
        {
          expenses: {
            ...expenses,
            columns: {
              ...expenses?.columns,
              reports: { ...expenses?.columns?.["reports"], approval: null },
            },
            options: { approvals: false },
          },
        },
        APP.replace(
          "  approval_id uuid,",
          "  rejected_at timestamptz,\n  decided_by uuid,\n  decision_note text,",
        ),
      ),
    ).resolves.toBeUndefined();
  });
});

const BOB = "33333333-3333-4333-8333-333333333333";
const ALICE_EMPLOYEE = "55555555-5555-4555-8555-555555555555";
const BOB_EMPLOYEE = "66666666-6666-4666-8666-666666666666";
const NO_ACCOUNT = "77777777-7777-4777-8777-777777777777";

const STAFF = `
insert into auth.users (id) values ('${BOB}');
insert into better_supabase.memberships (organization_id, user_id, role) values ('${TENANT}', '${BOB}', 'member');
insert into better_supabase.employees (id, tenant_id, user_id, name, manager_id) values
  ('${BOB_EMPLOYEE}', '${TENANT}', '${BOB}', 'Bob', null),
  ('${ALICE_EMPLOYEE}', '${TENANT}', '${ALICE}', 'Alice', '${BOB_EMPLOYEE}'),
  ('${NO_ACCOUNT}', '${TENANT}', null, 'Dana', '${BOB_EMPLOYEE}');
`;

const AS = (
  user: string,
): string => `perform set_config('request.jwt.claims', '{"sub":"${user}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const STANDALONE_APP = `
create type public.expense_status as enum ('draft', 'submitted', 'approved', 'rejected', 'reimbursed');

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  employee_id uuid,
  merchant text,
  description text,
  spent_on date not null,
  amount_cents bigint not null check (amount_cents >= 0),
  currency text not null default 'EUR',
  status public.expense_status not null default 'draft',
  submitted_at timestamptz,
  decided_by uuid,
  decided_at timestamptz,
  decision_note text,
  reimbursed_at timestamptz,
  reimbursed_by uuid,
  reimbursement_reference text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
`;

const STANDALONE_OWN = { "public.expenses": "app.sql" };

const STANDALONE: AnyBlocksConfig = {
  expenses: {
    tables: { reports: null, lines: null, expenses: "public.expenses" },
    columns: {
      expenses: {
        tenant: "organization_id",
        user: null,
        category: null,
        amount: "amount_cents",
        approvedAt: null,
        rejectedAt: null,
      },
    },
    options: { owner: "employee" },
  },
};

async function runStandalone(
  check: string,
  modules: AnyBlocksConfig,
  ownTables: Readonly<Record<string, string>>,
  app: string,
): Promise<void> {
  const files = renderBlocks(["employees", "expenses"], { modules, ownTables });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      app,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      ALLOW,
      STAFF,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("expenses without reports", BOOT, () => {
  it("adopts the app's expenses table without problems", () => {
    expect(
      adoptedColumnProblems(
        STANDALONE,
        [{ text: STANDALONE_APP }],
        ["public"],
        STANDALONE_OWN,
      ),
    ).toEqual([]);
  });

  it("creates, submits, decides and reimburses employees' expenses in an enum status", async () => {
    await expect(
      runStandalone(
        `do $$
declare
  v_expense jsonb;
  v_id uuid;
  v_dana uuid;
begin
  ${AS(ALICE)}
  v_expense := better_supabase.create_expense('${TENANT}', '2099-03-02', 4250, 'EUR', null, 'Train', 'NS');
  v_id := (v_expense ->> 'id')::uuid;
  if v_expense ->> 'employeeId' <> '${ALICE_EMPLOYEE}' or v_expense ->> 'status' <> 'draft'
    or (select status from public.expenses where id = v_id) <> 'draft' then
    raise exception 'created %', v_expense;
  end if;
  v_expense := better_supabase.update_expense(v_id, amount => 4500);
  v_expense := better_supabase.submit_expense(v_id);
  if v_expense ->> 'status' <> 'submitted' or (select submitted_at from public.expenses where id = v_id) is null then
    raise exception 'submitted %', v_expense;
  end if;
  begin
    perform better_supabase.update_expense(v_id, amount => 1);
    raise exception 'changed a submitted expense';
  exception when others then
    if sqlerrm not like '%draft or rejected%' then
      raise;
    end if;
  end;
  begin
    perform better_supabase.decide_expense(v_id, true);
    raise exception 'decided own expense';
  exception when others then
    if sqlerrm not like '%not allowed%' then
      raise;
    end if;
  end;
  ${AS(BOB)}
  begin
    perform better_supabase.decide_expense(v_id, false, null, '${ALICE}');
    raise exception 'decided as someone else';
  exception when others then
    if sqlerrm not like '%only the service role decides for another user%' then
      raise;
    end if;
  end;
  v_expense := better_supabase.decide_expense(v_id, false, 'needs a receipt');
  if (select status from public.expenses where id = v_id) <> 'rejected' or (select decision_note from public.expenses where id = v_id) <> 'needs a receipt' then
    raise exception 'rejected %', v_expense;
  end if;
  v_dana := (better_supabase.create_expense('${TENANT}', '2099-03-03', 1200, 'EUR', null, 'Lunch', employee_id => '${NO_ACCOUNT}') ->> 'id')::uuid;
  perform better_supabase.submit_expense(v_dana);
  ${AS(ALICE)}
  perform better_supabase.submit_expense(v_id);
  ${SERVICE}
  perform better_supabase.decide_expense(v_id, true, null, '${BOB}');
  if (select decided_by from public.expenses where id = v_id) <> '${BOB}' then
    raise exception 'decided for Bob %', (select decided_by from public.expenses where id = v_id);
  end if;
  v_expense := better_supabase.reimburse_expense(v_id, 'SEPA-1');
  if v_expense ->> 'status' <> 'reimbursed' or (select reimbursement_reference from public.expenses where id = v_id) <> 'SEPA-1'
    or (v_expense ->> 'amount')::bigint <> 4500 then
    raise exception 'reimbursed %', v_expense;
  end if;
  ${AS(BOB)}
  if jsonb_array_length(better_supabase.list_expenses('${TENANT}', employee_id => '${NO_ACCOUNT}')) <> 1
    or jsonb_array_length(better_supabase.list_expenses('${TENANT}', status => 'reimbursed', everyone => true)) <> 1 then
    raise exception 'lists';
  end if;
  if better_supabase.get_expense(v_dana) ->> 'status' <> 'submitted' then
    raise exception 'get %', better_supabase.get_expense(v_dana);
  end if;
end;
$$;`,
        STANDALONE,
        STANDALONE_OWN,
        STANDALONE_APP,
      ),
    ).resolves.toBeUndefined();
  });

  it("inserts extra columns with the row, clears columns, records company expenses, withdraws and deletes", async () => {
    const standalone = STANDALONE["expenses"];

    await expect(
      runStandalone(
        `do $$
declare
  v_expense jsonb;
  v_id uuid;
  v_company uuid;
begin
  ${AS(ALICE)}
  v_expense := better_supabase.create_expense('${TENANT}', '2099-03-02', 4250, 'EUR', null, 'Train', 'NS', fields => '{"base_currency": "EUR", "project_code": "P1"}');
  v_id := (v_expense ->> 'id')::uuid;
  if (select base_currency from public.expenses where id = v_id) <> 'EUR' or v_expense -> 'fields' ->> 'project_code' <> 'P1' then
    raise exception 'created %', v_expense;
  end if;
  v_expense := better_supabase.update_expense(v_id, clear => array['merchant', 'description'], fields => '{"project_code": null}');
  if (select row(merchant, description, project_code, base_currency)::text from public.expenses where id = v_id) <> '(,,,EUR)' then
    raise exception 'cleared %', v_expense;
  end if;
  perform better_supabase.submit_expense(v_id);
  v_expense := better_supabase.withdraw_expense(v_id);
  if v_expense ->> 'status' <> 'draft' or (select submitted_at from public.expenses where id = v_id) is not null then
    raise exception 'withdrawn %', v_expense;
  end if;
  begin
    perform better_supabase.create_expense('${TENANT}', '2099-03-02', 100, 'EUR', employee_id => '${ALICE_EMPLOYEE}', company => true, fields => '{"base_currency": "EUR"}');
    raise exception 'a company expense took an employee';
  exception when others then
    if sqlerrm not like '%no member or employee%' then
      raise;
    end if;
  end;
  if not better_supabase.delete_expense(v_id) then
    raise exception 'delete returned false';
  end if;
  if exists (select 1 from public.expenses where id = v_id) then
    raise exception 'not deleted';
  end if;
  ${SERVICE}
  v_expense := better_supabase.create_expense('${TENANT}', '2099-03-04', 9900, 'EUR', null, 'Office rent', company => true, fields => '{"base_currency": "EUR"}');
  v_company := (v_expense ->> 'id')::uuid;
  if v_expense ->> 'employeeId' is not null or (select employee_id from public.expenses where id = v_company) is not null then
    raise exception 'company %', v_expense;
  end if;
  perform better_supabase.submit_expense(v_company);
  begin
    perform better_supabase.delete_expense(v_company);
    raise exception 'deleted a submitted expense';
  exception when others then
    if sqlerrm not like '%only a draft%' then
      raise;
    end if;
  end;
end;
$$;`,
        {
          expenses: {
            ...standalone,
            options: {
              ...standalone?.options,
              companyExpenses: true,
              extraColumns: { base_currency: "text", project_code: "text" },
            },
          },
        },
        STANDALONE_OWN,
        STANDALONE_APP.replace(
          "  created_by uuid,",
          "  created_by uuid,\n  base_currency text not null,\n  project_code text,",
        ),
      ),
    ).resolves.toBeUndefined();
  });

  it("checks finer keys for others' expenses, reimbursing and categories", async () => {
    const payroll = "88888888-8888-4888-8888-888888888888";

    const refused = (call: string): string => `begin
    perform ${call};
    raise exception 'allowed: ${call.replaceAll("'", "''")}';
  exception when others then
    if sqlerrm like 'allowed: %' then
      raise;
    end if;
  end;`;

    await expect(
      runStandalone(
        `create table public.denied (user_id uuid, permission text);
insert into public.denied values ('${payroll}', 'expense.create'), ('${payroll}', 'expense.update'),
  ('${payroll}', 'expense.delete'), ('${payroll}', 'expense.policies'), ('${payroll}', 'expense.manage');
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select not exists (select 1 from public.denied d where d.user_id = auth.uid() and d.permission = can.permission) $$;
insert into auth.users (id) values ('${payroll}');
insert into better_supabase.memberships (organization_id, user_id, role) values ('${TENANT}', '${payroll}', 'member');
do $$
declare
  v_category uuid;
  v_id uuid;
  v_draft uuid;
begin
  ${SERVICE}
  v_category := (better_supabase.save_expense_category('${TENANT}', 'travel', 'Travel') ->> 'id')::uuid;
  ${AS(ALICE)}
  v_id := (better_supabase.create_expense('${TENANT}', '2099-03-02', 900, 'EUR', v_category, 'Taxi') ->> 'id')::uuid;
  v_draft := (better_supabase.create_expense('${TENANT}', '2099-03-03', 400, 'EUR', v_category, 'Lunch') ->> 'id')::uuid;
  perform better_supabase.submit_expense(v_id);
  ${AS(BOB)}
  perform better_supabase.decide_expense(v_id, true);
  ${AS(payroll)}
  ${refused(`better_supabase.create_expense('${TENANT}', '2099-03-04', 100, 'EUR', user_id => '${ALICE}')`)}
  ${refused("better_supabase.update_expense(v_draft, amount => 500)")}
  ${refused("better_supabase.submit_expense(v_draft)")}
  ${refused("better_supabase.delete_expense(v_draft)")}
  ${refused(`better_supabase.save_expense_category('${TENANT}', 'meals', 'Meals')`)}
  perform better_supabase.reimburse_expense(v_id, 'batch-1');
  if better_supabase.get_expense(v_id) ->> 'status' <> 'reimbursed' then
    raise exception 'reimbursed %', better_supabase.get_expense(v_id);
  end if;
end;
$$;`,
        {
          expenses: {
            tables: { reports: null, lines: null },
            permissions: {
              manage: "expense.manage",
              create: "expense.create",
              update: "expense.update",
              delete: "expense.delete",
              reimburse: "expense.reimburse",
              categories: "expense.policies",
            },
          },
        },
        {},
        "",
      ),
    ).resolves.toBeUndefined();

    const sql = renderBlocks(["employees", "expenses"], {
      modules: { expenses: { tables: { reports: null, lines: null } } },
    })
      .map((file) => file.contents)
      .join("\n");

    const body = (name: string): string => {
      const start = sql.indexOf(`function "better_supabase"."${name}"(`);

      return sql.slice(start, sql.indexOf("$$;", start));
    };

    for (const name of [
      "create_expense",
      "update_expense",
      "delete_expense",
      "reimburse_expense",
      "save_expense_category",
    ]) {
      expect(body(name)).toContain("'expenses.manage'");
    }
  });

  it("withdraws approved expenses and deletes submitted ones when the config allows it", async () => {
    const payroll = "88888888-8888-4888-8888-888888888888";

    const refused = (call: string, reason: string): string => `begin
    perform ${call};
    raise exception 'allowed: ${call.replaceAll("'", "''")}';
  exception when others then
    if sqlerrm like 'allowed: %' or sqlerrm not like '%${reason}%' then
      raise;
    end if;
  end;`;

    await expect(
      runStandalone(
        `create table public.denied (user_id uuid, permission text);
insert into public.denied values ('${payroll}', 'expense.withdraw'), ('${payroll}', 'expense.purge'),
  ('${payroll}', 'expense.update'), ('${payroll}', 'expense.manage'), ('${ALICE}', 'expense.purge');
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select not exists (select 1 from public.denied d where d.user_id = auth.uid() and d.permission = can.permission) $$;
insert into auth.users (id) values ('${payroll}');
insert into better_supabase.memberships (organization_id, user_id, role) values ('${TENANT}', '${payroll}', 'member');
do $$
declare
  v_id uuid;
  v_other uuid;
  v_paid uuid;
  v_expense jsonb;
begin
  ${AS(ALICE)}
  v_id := (better_supabase.create_expense('${TENANT}', '2099-03-02', 900, 'EUR', null, 'Taxi') ->> 'id')::uuid;
  v_other := (better_supabase.create_expense('${TENANT}', '2099-03-03', 400, 'EUR', null, 'Lunch') ->> 'id')::uuid;
  v_paid := (better_supabase.create_expense('${TENANT}', '2099-03-04', 300, 'EUR', null, 'Bus') ->> 'id')::uuid;
  perform better_supabase.submit_expense(v_id);
  perform better_supabase.submit_expense(v_other);
  perform better_supabase.submit_expense(v_paid);
  ${AS(BOB)}
  perform better_supabase.decide_expense(v_id, true);
  perform better_supabase.decide_expense(v_other, true);
  perform better_supabase.decide_expense(v_paid, true);
  perform better_supabase.reimburse_expense(v_paid, 'batch-1');
  ${AS(ALICE)}
  v_expense := better_supabase.withdraw_expense(v_id);
  if v_expense ->> 'status' <> 'draft' or v_expense ->> 'decidedBy' is not null or v_expense ->> 'submittedAt' is not null then
    raise exception 'withdrawn %', v_expense;
  end if;
  ${refused("better_supabase.delete_expense(v_other)", "not allowed")}
  ${refused("better_supabase.withdraw_expense(v_paid)", "submitted or approved")}
  perform better_supabase.submit_expense(v_id);
  ${AS(BOB)}
  perform better_supabase.decide_expense(v_id, true);
  ${AS(payroll)}
  ${refused("better_supabase.withdraw_expense(v_id)", "not allowed")}
  ${refused("better_supabase.delete_expense(v_other)", "not allowed")}
  ${AS(BOB)}
  if better_supabase.withdraw_expense(v_id) ->> 'status' <> 'draft' then
    raise exception 'withdrawn by a key holder';
  end if;
  if not better_supabase.delete_expense(v_other) then
    raise exception 'approved expense not deleted';
  end if;
  ${refused("better_supabase.get_expense(v_other)", "no such expense")}
  ${refused("better_supabase.delete_expense(v_paid)", "only a draft")}
end;
$$;`,
        {
          expenses: {
            tables: { reports: null, lines: null },
            permissions: {
              manage: "expense.manage",
              update: "expense.update",
              withdraw: "expense.withdraw",
              deleteSubmitted: "expense.purge",
            },
            options: { withdrawApproved: true },
          },
        },
        {},
        "",
      ),
    ).resolves.toBeUndefined();

    const sql = renderBlocks(["employees", "expenses"], {
      modules: { expenses: { tables: { reports: null, lines: null } } },
    })
      .map((file) => file.contents)
      .join("\n");

    const body = (name: string): string => {
      const start = sql.indexOf(`function "better_supabase"."${name}"(`);

      return sql.slice(start, sql.indexOf("$$;", start));
    };

    expect(body("withdraw_expense")).toContain(
      "only a submitted expense is withdrawn",
    );
    expect(body("withdraw_expense")).toContain("not in ('submitted')");
    expect(body("delete_expense")).toContain("only a draft expense is deleted");
    expect(body("delete_expense")).not.toContain("'approved'");
  });

  it("runs over categories without key and currency columns, with extra columns", async () => {
    const modules: AnyBlocksConfig = {
      expenses: {
        tables: {
          reports: null,
          lines: null,
          categories: "public.expense_kinds",
        },
        columns: {
          categories: {
            tenant: "organization_id",
            key: null,
            currency: null,
            limitAmount: null,
            receiptOver: null,
          },
        },
        options: { categoryExtraColumns: { gl_code: "text" } },
      },
    };

    const refused = (call: string): string => `begin
    perform ${call};
    raise exception 'allowed: ${call.replaceAll("'", "''")}';
  exception when others then
    if sqlerrm like 'allowed: %' then
      raise;
    end if;
  end;`;

    await expect(
      runStandalone(
        `do $$
declare
  v_category jsonb;
  v_id uuid;
begin
  ${SERVICE}
  v_category := better_supabase.save_expense_category('${TENANT}', null, 'Travel', fields => '{"gl_code": "4100"}');
  v_id := (v_category ->> 'id')::uuid;
  if v_category ->> 'key' <> v_id::text or v_category -> 'fields' ->> 'gl_code' <> '4100' then
    raise exception 'created %', v_category;
  end if;
  v_category := better_supabase.save_expense_category('${TENANT}', v_id::text, 'Trips');
  if (select row(name, gl_code)::text from public.expense_kinds where id = v_id) <> '(Trips,4100)'
    or (select count(*) from public.expense_kinds) <> 1 then
    raise exception 'updated %', v_category;
  end if;
  ${refused(`better_supabase.save_expense_category('${TENANT}', null, 'Meals', 'EUR')`)}
  ${AS(ALICE)}
  perform better_supabase.create_expense('${TENANT}', '2099-03-02', 900, 'EUR', v_id, 'Taxi');
end;
$$;`,
        modules,
        { "public.expense_kinds": "app.sql" },
        `create table public.expense_kinds (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  name text not null,
  gl_code text,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);`,
      ),
    ).resolves.toBeUndefined();

    expect(
      renderBlocks(["expenses"], {
        modules: {
          expenses: {
            columns: {
              categories: {
                key: null,
                currency: null,
                limitAmount: null,
                receiptOver: null,
              },
            },
          },
        },
      })
        .map((file) => file.contents)
        .join("\n"),
    ).toContain(`'expenses:category:' || c."id"::text`);
    expect(() =>
      renderBlocks(["expenses"], {
        modules: { expenses: { columns: { categories: { currency: null } } } },
      }),
    ).toThrow(/needs the currency column/);
  });

  it("registers no ledger subjects without reports", () => {
    const standalone: AnyBlocksConfig = {
      expenses: { tables: { reports: null, lines: null } },
    };

    const sql = (modules: AnyBlocksConfig): string =>
      renderBlocks(["expenses", "comments"], {
        modules,
        subjects: withBlockSubjects({}, ["expenses", "comments"], modules),
      })
        .map((file) => file.contents)
        .join("\n");

    expect(sql(standalone)).not.toContain("ledger_accounts");
    expect(sql({ expenses: {} })).toContain("'ledger_account'");
  });

  it("keeps a member's expenses in the block's own table with categories", async () => {
    await expect(
      runStandalone(
        `do $$
declare
  v_category uuid;
  v_id uuid;
begin
  ${SERVICE}
  v_category := (better_supabase.save_expense_category('${TENANT}', 'travel', 'Travel') ->> 'id')::uuid;
  ${AS(ALICE)}
  v_id := (better_supabase.create_expense('${TENANT}', '2099-03-02', 900, 'EUR', v_category, 'Taxi') ->> 'id')::uuid;
  perform better_supabase.submit_expense(v_id);
  ${AS(BOB)}
  perform better_supabase.decide_expense(v_id, true);
  if better_supabase.get_expense(v_id) ->> 'status' <> 'approved'
    or (select approved_at from better_supabase.expenses where id = v_id) is null then
    raise exception 'approved';
  end if;
end;
$$;`,
        { expenses: { tables: { reports: null, lines: null } } },
        {},
        "",
      ),
    ).resolves.toBeUndefined();
  });
});
