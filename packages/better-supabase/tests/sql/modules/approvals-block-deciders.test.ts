import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const CAROL = "66666666-6666-4666-8666-666666666666";
const DAVE = "77777777-7777-4777-8777-777777777777";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;

-- The app's decider exists before the blocks that call it.
create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
create function public.app_decides(id uuid) returns boolean language sql stable as $$
  select auth.uid() = '${DAVE}'::uuid
$$;
create table public.decider_calls (n integer not null);
create function public.app_decides_many(ids uuid[]) returns uuid[] language plpgsql volatile as $$
begin
  insert into public.decider_calls values (cardinality(ids));
  return case when auth.uid() = '${DAVE}'::uuid then ids else '{}'::uuid[] end;
end;
$$;
grant insert on public.decider_calls to public;
create function public.app_decides_all(id uuid) returns boolean language sql stable as $$
  select true
$$;
create function public.app_decides_all_many(ids uuid[]) returns uuid[] language sql stable as $$
  select ids || gen_random_uuid()
$$;
`;

// Only Carol holds the approve keys; the app's decider accepts Dave.
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
insert into auth.users (id) values ('${ALICE}'), ('${CAROL}'), ('${DAVE}') on conflict do nothing;
insert into better_supabase.memberships (organization_id, user_id, role)
  select '${TENANT}', u, 'member' from unnest(array['${ALICE}', '${CAROL}', '${DAVE}']::uuid[]) u
  on conflict do nothing;
`;

const as = (user: string): string =>
  `perform set_config('request.jwt.claims', '{"sub":"${user}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const BLOCKS: AnyBlocksConfig = {
  "time-entries": {
    options: { decider: "public.app_decides", overlap: "allow" },
  },
  expenses: {
    tables: { reports: null, lines: null },
    options: { standaloneApprovals: true, decider: "public.app_decides" },
  },
};

const BOOT = { timeout: 90_000 };

async function run(
  check: string,
  names: readonly string[] = ["time-entries", "expenses"],
  modules: AnyBlocksConfig = BLOCKS,
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
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("an app decider in the approvals flow", BOOT, () => {
  it("decides timesheets and expenses through their approval requests", async () => {
    await expect(
      run(`do $$
declare
  v_sheet uuid;
  v_expense uuid;
  v_approval uuid;
begin
  ${as(ALICE)}
  perform better_supabase.log_time('${TENANT}', '2099-03-02T09:00:00Z', '2099-03-02T10:00:00Z');
  v_sheet := (better_supabase.submit_timesheet('${TENANT}', '2099-03-02') ->> 'id')::uuid;
  v_expense := (better_supabase.create_expense('${TENANT}', '2099-03-02', 1250, 'EUR') ->> 'id')::uuid;
  perform better_supabase.submit_expense(v_expense);
  ${as(DAVE)}
  foreach v_approval in array array[
    (select id from better_supabase.approval_requests where subject_type = 'timesheet' and subject_id = v_sheet::text and status = 'pending'),
    (select id from better_supabase.approval_requests where subject_type = 'expense' and subject_id = v_expense::text and status = 'pending')
  ] loop
    if v_approval is null or not better_supabase.approval_eligible(v_approval)
      or v_approval <> all (select better_supabase.approval_eligible_ids('${TENANT}')) then
      raise exception 'the decider can''t decide %', v_approval;
    end if;
    perform better_supabase.decide_approval(v_approval, 'approved');
  end loop;
  if better_supabase.get_expense(v_expense) ->> 'status' <> 'approved' then
    raise exception 'the expense is %', better_supabase.get_expense(v_expense) ->> 'status';
  end if;
  if (select status from better_supabase.approval_requests where subject_type = 'timesheet' and subject_id = v_sheet::text) <> 'approved' then
    raise exception 'the timesheet approval is still open';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("asks the set form once per subject type in approval_eligible_ids_in, with the same answer", async () => {
    const many: AnyBlocksConfig = {
      "time-entries": {
        options: {
          decider: "public.app_decides",
          deciderMany: "public.app_decides_many",
          overlap: "allow",
        },
      },
      expenses: {
        tables: { reports: null, lines: null },
        options: {
          standaloneApprovals: true,
          decider: "public.app_decides",
          deciderMany: "public.app_decides_many",
        },
      },
    };

    const sql = renderBlocks(["time-entries", "expenses"], { modules: many })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain('"public"."app_decides_many"(own.bsb_ids)');
    expect(sql).toContain(
      "from block_decided bd where bd.bsb_type = 'timesheet'",
    );

    await expect(
      run(
        `create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $f$
  select '${TENANT}'::uuid where permission not like '%.approve' or auth.uid() = '${CAROL}'::uuid
$f$;
do $$
declare
  v_sheet uuid;
  v_expense uuid;
  v_ids uuid[];
  v_calls integer;
  v_user uuid;
begin
  ${as(ALICE)}
  perform better_supabase.log_time('${TENANT}', '2099-03-02T09:00:00Z', '2099-03-02T10:00:00Z');
  v_sheet := (better_supabase.submit_timesheet('${TENANT}', '2099-03-02') ->> 'id')::uuid;
  v_expense := (better_supabase.create_expense('${TENANT}', '2099-03-02', 1250, 'EUR') ->> 'id')::uuid;
  perform better_supabase.submit_expense(v_expense);
  foreach v_user in array array['${DAVE}', '${CAROL}']::uuid[] loop
    perform set_config('request.jwt.claims', jsonb_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_user::text, true);
    delete from public.decider_calls;
    v_ids := array(select x from better_supabase.approval_eligible_ids_in() x order by x);
    v_calls := (select count(*) from public.decider_calls);
    if v_calls > 2 or (v_user = '${DAVE}' and v_calls <> 2) then
      raise exception 'the set form ran % times, not once per subject type', v_calls;
    end if;
    if v_ids is distinct from array(select r.id from better_supabase.approval_requests r where r.status = 'pending' and better_supabase.approval_eligible(r.id) order by r.id) then
      raise exception 'the set form answers % for %, approval_eligible differs', v_ids, v_user;
    end if;
    if v_user = '${DAVE}' and cardinality(v_ids) <> 2 then
      raise exception 'the decider decides % requests, not 2', cardinality(v_ids);
    end if;
  end loop;
end;
$$;`,
        ["time-entries", "expenses"],
        many,
      ),
    ).resolves.toBeUndefined();
  });

  it("keeps the requester's own and excluded requests out when the set form returns them and more", async () => {
    const wide: AnyBlocksConfig = {
      "time-entries": {
        options: {
          decider: "public.app_decides_all",
          deciderMany: "public.app_decides_all_many",
          overlap: "allow",
        },
      },
      expenses: {
        tables: { reports: null, lines: null },
        options: {
          standaloneApprovals: true,
          decider: "public.app_decides_all",
          deciderMany: "public.app_decides_all_many",
        },
      },
    };

    await expect(
      run(
        `do $$
declare
  v_expense uuid;
  v_sheet uuid;
  v_user uuid;
  v_ids uuid[];
begin
  ${as(ALICE)}
  perform better_supabase.log_time('${TENANT}', '2099-03-02T09:00:00Z', '2099-03-02T10:00:00Z');
  v_sheet := (better_supabase.submit_timesheet('${TENANT}', '2099-03-02') ->> 'id')::uuid;
  v_expense := (better_supabase.create_expense('${TENANT}', '2099-03-02', 1250, 'EUR') ->> 'id')::uuid;
  perform better_supabase.submit_expense(v_expense);
  update better_supabase.approval_requests
  set policy = policy || jsonb_build_object('excludedUserIds', jsonb_build_array('${DAVE}'))
  where subject_type = 'expense' and subject_id = v_expense::text;
  if cardinality(array(select x from better_supabase.approval_eligible_ids_in() x)) <> 0 then
    raise exception 'the requester decides their own request through the set form';
  end if;
  foreach v_user in array array['${ALICE}', '${DAVE}', '${CAROL}']::uuid[] loop
    perform set_config('request.jwt.claims', jsonb_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_user::text, true);
    v_ids := array(select x from better_supabase.approval_eligible_ids_in() x order by x);
    if v_ids is distinct from array(select r.id from better_supabase.approval_requests r where r.status = 'pending' and better_supabase.approval_eligible(r.id) order by r.id) then
      raise exception 'the set form answers % for %, approval_eligible differs', v_ids, v_user;
    end if;
    if v_user = '${DAVE}' and v_ids is distinct from array(select r.id from better_supabase.approval_requests r where r.subject_type = 'timesheet' and r.subject_id = v_sheet::text) then
      raise exception 'the excluded user decides %', v_ids;
    end if;
  end loop;
end;
$$;`,
        ["time-entries", "expenses"],
        wide,
      ),
    ).resolves.toBeUndefined();
  });

  it("asks the set form for an escalated step whose escalateTo sets decider", async () => {
    const many: AnyBlocksConfig = {
      "time-entries": {
        options: {
          decider: "public.app_decides",
          deciderMany: "public.app_decides_many",
          overlap: "allow",
        },
      },
    };

    await expect(
      run(
        `do $$
declare
  v_sheet uuid;
  v_request uuid;
  v_user uuid;
  v_ids uuid[];
begin
  ${as(ALICE)}
  perform better_supabase.log_time('${TENANT}', '2099-03-02T09:00:00Z', '2099-03-02T10:00:00Z');
  v_sheet := (better_supabase.submit_timesheet('${TENANT}', '2099-03-02') ->> 'id')::uuid;
  update better_supabase.approval_requests
  set policy = jsonb_set(policy, '{steps,0}', '{"approvers": {"users": []}, "escalateTo": {"decider": true}, "escalated": true, "required": 1}'::jsonb)
  where subject_type = 'timesheet' and subject_id = v_sheet::text
  returning id into v_request;
  foreach v_user in array array['${DAVE}', '${CAROL}']::uuid[] loop
    perform set_config('request.jwt.claims', jsonb_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_user::text, true);
    delete from public.decider_calls;
    v_ids := array(select x from better_supabase.approval_eligible_ids_in() x);
    if v_ids is distinct from array(select r.id from better_supabase.approval_requests r where r.status = 'pending' and better_supabase.approval_eligible(r.id)) then
      raise exception 'the set form answers % for %, approval_eligible differs', v_ids, v_user;
    end if;
    if (select count(*) from public.decider_calls) <> 1 then
      raise exception 'the escalated decider step asked the set form % times', (select count(*) from public.decider_calls);
    end if;
    if (v_user = '${DAVE}') is distinct from (v_ids = array[v_request]) then
      raise exception 'the escalated decider step answers % for %', v_ids, v_user;
    end if;
  end loop;
end;
$$;`,
        ["time-entries"],
        many,
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses deciderMany without decider", () => {
    expect(() =>
      renderBlocks(["time-entries"], {
        modules: {
          "time-entries": {
            options: { deciderMany: "public.app_decides_many" },
          },
        },
      }),
    ).toThrow(/deciderMany is the set form/u);
  });

  it("lets the decider withdraw a submitted week, and nobody else but the owner", async () => {
    await expect(
      run(`create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $f$
  select permission not like '%.approve' and permission not like '%.manage' or (permission like '%.approve' and auth.uid() = '${CAROL}'::uuid)
$f$;
do $$
declare
  v_sheet uuid;
  v_hint text;
  v_status text;
begin
  ${as(ALICE)}
  perform better_supabase.log_time('${TENANT}', '2099-03-02T09:00:00Z', '2099-03-02T10:00:00Z');
  v_sheet := (better_supabase.submit_timesheet('${TENANT}', '2099-03-02') ->> 'id')::uuid;
  ${as(CAROL)}
  begin
    perform better_supabase.withdraw_timesheet(v_sheet);
    raise exception 'an approver who isn''t the decider withdrew the week';
  exception when insufficient_privilege then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  ${as(DAVE)}
  v_status := better_supabase.withdraw_timesheet(v_sheet) ->> 'status';
  if v_status <> 'open'
    or exists (select 1 from better_supabase.approval_requests where subject_id = v_sheet::text and status = 'pending') then
    raise exception 'the decider could not withdraw the week: %', v_status;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a timesheet decider without the approvals block", () => {
    expect(() =>
      renderBlocks(["time-entries"], {
        modules: {
          "time-entries": {
            options: { approvals: false, decider: "public.app_decides" },
          },
        },
      }),
    ).toThrow(/decider decides approvals policy steps/u);
  });

  it("refuses a decider step no block decides, and with required all", () => {
    const policies = (step: Record<string, unknown>) => ({
      approvals: {
        options: { policies: { contract: { approve: { steps: [step] } } } },
      },
    });

    expect(() =>
      renderBlocks(["approvals"], {
        modules: policies({ approvers: { decider: true } }),
      }),
    ).toThrow(/approvers.decider needs a block that decides/u);
    expect(() =>
      renderBlocks(["approvals"], {
        modules: policies({
          approvers: { permission: "contracts.approve", decider: true },
          required: "all",
        }),
      }),
    ).toThrow(/required "all"/u);
  });

  it("keeps tenant policies from naming a decider no block has", () => {
    const sql = renderBlocks(["time-entries"], {
      modules: {
        approvals: { options: { tenantPolicies: true } },
        "time-entries": { options: { decider: "public.app_decides" } },
      },
    })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("-> 'approvers' -> 'decider' = 'true'::jsonb");
    expect(sql).toContain("hint = 'APPROVAL_POLICY_DECIDER_UNAVAILABLE'");
    expect(sql).toContain("and v_type not in ('timesheet')");
  });

  it("refuses a tenant decider step on a type no block decides", async () => {
    await expect(
      run(
        `do $$
declare
  v_hint text;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform better_supabase.upsert_approval_policy('${TENANT}', '{"subjectType": "timesheet", "action": "approve", "name": "Chain", "steps": [{"approvers": {"decider": true}}]}');
  begin
    perform better_supabase.upsert_approval_policy('${TENANT}', '{"subjectType": "contract", "action": "approve", "name": "Chain", "steps": [{"approvers": {"decider": true}}]}');
    raise exception 'allowed';
  exception when sqlstate '22023' then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint <> 'APPROVAL_POLICY_DECIDER_UNAVAILABLE' then
      raise exception 'hint %', v_hint;
    end if;
  end;
end;
$$;`,
        ["time-entries"],
        {
          approvals: {
            options: {
              tenantPolicies: true,
              policies: {
                timesheet: { approve: { steps: [] } },
                contract: { approve: { steps: [] } },
              },
            },
          },
          "time-entries": {
            options: { decider: "public.app_decides", overlap: "allow" },
          },
        },
      ),
    ).resolves.toBeUndefined();
  });
});
