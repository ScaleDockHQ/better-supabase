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

async function run(check: string): Promise<void> {
  const files = renderBlocks(["time-entries", "expenses"], {
    modules: BLOCKS,
  }).map((file) => ({
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
    expect(sql).toContain("and v_type not in ('timesheet')");
  });
});
