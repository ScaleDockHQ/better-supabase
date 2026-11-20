import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const CAROL = "66666666-6666-4666-8666-666666666666";
const ALICE_EMPLOYEE = "44444444-4444-4444-8444-444444444444";
const CAROL_EMPLOYEE = "55555555-5555-4555-8555-555555555555";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
create function public.week_needs_approval(tenant uuid, timesheet_id uuid) returns boolean
language sql stable as $$ select false $$;
`;

// Only Carol holds the approve keys.
const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$
  select permission not like '%.approve' or auth.uid() = '${CAROL}'::uuid
$$;
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$
  select permission not like '%.approve' or member = '${CAROL}'::uuid
$$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into auth.users (id) values ('${ALICE}'), ('${CAROL}') on conflict do nothing;
insert into better_supabase.memberships (organization_id, user_id, role)
  select '${TENANT}', u, 'member' from unnest(array['${ALICE}', '${CAROL}']::uuid[]) u
  on conflict do nothing;
`;

const EMPLOYEES = `
insert into better_supabase.employees (id, tenant_id, user_id, name, manager_id) values
  ('${CAROL_EMPLOYEE}', '${TENANT}', '${CAROL}', 'Carol', null),
  ('${ALICE_EMPLOYEE}', '${TENANT}', '${ALICE}', 'Alice', '${CAROL_EMPLOYEE}');
`;

const as = (user: string): string =>
  `perform set_config('request.jwt.claims', '{"sub":"${user}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const BOOT = { timeout: 120_000 };

async function run(
  names: readonly string[],
  modules: AnyBlocksConfig,
  check: string,
  seed = "",
): Promise<void> {
  const files = renderBlocks(names, { modules }).map((file) => ({
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
      ALLOW,
      seed,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("self-decide in the approvals flow", BOOT, () => {
  it("lets an expense owner nobody else can decide for approve their own claim", async () => {
    await expect(
      run(
        ["expenses"],
        {
          expenses: {
            tables: { reports: null, lines: null },
            options: {
              standaloneApprovals: true,
              selfDecideWhenTopOfChain: true,
            },
          },
        },
        `do $$
declare
  v_expense uuid;
  v_approval uuid;
begin
  ${as(CAROL)}
  v_expense := (better_supabase.create_expense('${TENANT}', '2099-03-02', 1250, 'EUR') ->> 'id')::uuid;
  perform better_supabase.submit_expense(v_expense);
  select id into v_approval from better_supabase.approval_requests where subject_type = 'expense' and subject_id = v_expense::text;
  if not better_supabase.approval_eligible(v_approval)
    or v_approval <> all (select better_supabase.approval_eligible_ids('${TENANT}')) then
    raise exception 'the only approver can''t decide their own claim';
  end if;
  perform better_supabase.decide_approval(v_approval, 'approved');
  if better_supabase.get_expense(v_expense) ->> 'status' <> 'approved' then
    raise exception 'the expense is %', better_supabase.get_expense(v_expense) ->> 'status';
  end if;
  ${as(ALICE)}
  v_expense := (better_supabase.create_expense('${TENANT}', '2099-03-02', 900, 'EUR') ->> 'id')::uuid;
  perform better_supabase.submit_expense(v_expense);
  select id into v_approval from better_supabase.approval_requests where subject_type = 'expense' and subject_id = v_expense::text;
  if better_supabase.approval_eligible(v_approval) then
    raise exception 'an owner without the approve key decides their own claim';
  end if;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses an expense self-decide rule without standalone approvals or with approvers it can't count", () => {
    expect(() =>
      renderBlocks(["expenses"], {
        modules: {
          expenses: {
            tables: { reports: null, lines: null },
            options: { selfDecideWhenTopOfChain: true },
          },
        },
      }),
    ).toThrow(/needs standaloneApprovals/u);
    expect(() =>
      renderBlocks(["expenses"], {
        modules: {
          expenses: {
            tables: { reports: null, lines: null },
            options: {
              standaloneApprovals: true,
              selfDecideWhenTopOfChain: true,
              policy: { steps: [{ approvers: { role: "admin" } }] },
            },
          },
        },
      }),
    ).toThrow(/counts only/u);
  });

  it("approves a week at once when its owner is the only approver", async () => {
    await expect(
      run(
        ["time-entries"],
        {
          "time-entries": {
            options: { selfApproveWhenTopOfChain: true, overlap: "allow" },
          },
        },
        `do $$
declare
  v_sheet jsonb;
begin
  ${as(CAROL)}
  perform better_supabase.log_time('${TENANT}', '2099-03-02T09:00:00Z', '2099-03-02T10:00:00Z');
  v_sheet := better_supabase.submit_timesheet('${TENANT}', '2099-03-02');
  if v_sheet ->> 'status' <> 'approved' or exists (select 1 from better_supabase.approval_requests where subject_id = v_sheet ->> 'id') then
    raise exception 'the only approver''s week is %', v_sheet;
  end if;
  ${as(ALICE)}
  perform better_supabase.log_time('${TENANT}', '2099-03-02T09:00:00Z', '2099-03-02T10:00:00Z');
  v_sheet := better_supabase.submit_timesheet('${TENANT}', '2099-03-02');
  if v_sheet ->> 'status' <> 'submitted' then
    raise exception 'a week of a member without the approve key is %', v_sheet;
  end if;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });

  it("approves an employee's week at once when the app says it needs no approval", async () => {
    await expect(
      run(
        ["employees", "time-entries"],
        {
          "time-entries": {
            options: {
              owner: "employee",
              approvalRequired: "public.week_needs_approval",
              overlap: "allow",
            },
          },
        },
        `do $$
declare
  v_sheet jsonb;
begin
  ${as(ALICE)}
  perform better_supabase.log_time('${TENANT}', '2099-03-02T09:00:00Z', '2099-03-02T10:00:00Z');
  v_sheet := better_supabase.submit_timesheet('${TENANT}', '2099-03-02');
  if v_sheet ->> 'status' <> 'approved' or exists (select 1 from better_supabase.approval_requests where subject_id = v_sheet ->> 'id') then
    raise exception 'the week is %', v_sheet;
  end if;
end;
$$;`,
        EMPLOYEES,
      ),
    ).resolves.toBeUndefined();
  });

  it("approves the top of the chain's week at once and files the others", async () => {
    await expect(
      run(
        ["employees", "time-entries"],
        {
          "time-entries": {
            options: {
              owner: "employee",
              selfApproveWhenTopOfChain: true,
              overlap: "allow",
            },
          },
        },
        `do $$
declare
  v_sheet jsonb;
begin
  ${as(CAROL)}
  perform better_supabase.log_time('${TENANT}', '2099-03-02T09:00:00Z', '2099-03-02T10:00:00Z');
  v_sheet := better_supabase.submit_timesheet('${TENANT}', '2099-03-02');
  if v_sheet ->> 'status' <> 'approved' or v_sheet ->> 'decidedBy' is distinct from '${CAROL}' then
    raise exception 'the top of the chain''s week is %', v_sheet;
  end if;
  ${as(ALICE)}
  perform better_supabase.log_time('${TENANT}', '2099-03-02T09:00:00Z', '2099-03-02T10:00:00Z');
  v_sheet := better_supabase.submit_timesheet('${TENANT}', '2099-03-02');
  if v_sheet ->> 'status' <> 'submitted' then
    raise exception 'Alice''s week is %', v_sheet;
  end if;
end;
$$;`,
        EMPLOYEES,
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses self approval when a policy step doesn't name the approve key", () => {
    expect(() =>
      renderBlocks(["employees", "time-entries"], {
        modules: {
          "time-entries": {
            options: {
              selfApproveWhenTopOfChain: true,
              policy: { steps: [{ approvers: { manager: true } }] },
            },
          },
        },
      }),
    ).toThrow(/every policy step names/u);
  });

  it("refuses the week options without approvals", () => {
    expect(() =>
      renderBlocks(["time-entries"], {
        modules: {
          "time-entries": {
            options: { approvals: false, selfApproveWhenTopOfChain: true },
          },
        },
      }),
    ).toThrow(/need approvals/u);
  });
});
