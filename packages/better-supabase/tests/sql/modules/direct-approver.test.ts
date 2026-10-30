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

// Everyone may do everything except approve, which only Carol holds, so a
// decision by Bob comes from managing Alice.
const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$
  select permission not like '%.approve' or auth.uid() = '${CAROL}'::uuid
$$;
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select permission not like '%.approve' or member = '${CAROL}'::uuid $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into auth.users (id) values ('${ALICE}'), ('${BOB}'), ('${CAROL}') on conflict do nothing;
insert into better_supabase.memberships (organization_id, user_id, role)
  select '${TENANT}', u, 'member' from unnest(array['${ALICE}', '${BOB}', '${CAROL}']::uuid[]) u
  on conflict do nothing;
insert into better_supabase.employees (id, tenant_id, user_id, name, manager_id) values
  ('${BOB_EMPLOYEE}', '${TENANT}', '${BOB}', 'Bob', null),
  ('${ALICE_EMPLOYEE}', '${TENANT}', '${ALICE}', 'Alice', '${BOB_EMPLOYEE}');
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '', true);`;

const as = (user: string): string =>
  `perform set_config('request.jwt.claims', '{"sub":"${user}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const BLOCKS: AnyBlocksConfig = {
  leave: {
    options: { owner: "employee", approvals: false, approver: "manager" },
  },
  "time-tracking": {
    options: { owner: "employee", approvals: false, overlap: "allow" },
  },
  expenses: {
    tables: { reports: null, lines: null },
    options: { owner: "employee", approver: "manager" },
  },
};

const NAMES = ["employees", "leave", "time-tracking", "expenses"] as const;

const BOOT = { timeout: 180_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(NAMES, { modules: BLOCKS }).map((file) => ({
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

describe("direct decisions by the requester's manager", BOOT, () => {
  it("lets the manager decide leave and an expense, keeps others out and records the decider of a week", async () => {
    await expect(
      run(`do $$
declare
  v_type uuid;
  v_leave uuid;
  v_other uuid;
  v_expense uuid;
  v_sheet jsonb;
begin
  ${as(BOB)}
  v_type := (better_supabase.save_leave_type('${TENANT}', 'holiday', 'Holiday', 'days', true, false) ->> 'id')::uuid;
  ${as(ALICE)}
  v_leave := (better_supabase.request_leave('${TENANT}', v_type, '2099-03-02', '2099-03-03') ->> 'id')::uuid;
  begin
    perform better_supabase.decide_leave_request(v_leave, true);
    raise exception 'Alice decided her own leave';
  exception when others then
    if sqlerrm not like '%not allowed to decide%' then
      raise;
    end if;
  end;
  ${as(CAROL)}
  perform better_supabase.decide_leave_request(v_leave, false);
  ${as(ALICE)}
  v_leave := (better_supabase.request_leave('${TENANT}', v_type, '2099-04-06', '2099-04-07') ->> 'id')::uuid;
  ${as(BOB)}
  perform better_supabase.decide_leave_request(v_leave, true);
  v_other := (better_supabase.request_leave('${TENANT}', v_type, '2099-05-04', '2099-05-05') ->> 'id')::uuid;
  ${as(ALICE)}
  begin
    perform better_supabase.decide_leave_request(v_other, true);
    raise exception 'Alice decided leave of someone she does not manage';
  exception when others then
    if sqlerrm not like '%not allowed to decide%' then
      raise;
    end if;
  end;
  if (select approved_at from better_supabase.leave_requests where id = v_leave) is null then
    raise exception 'the manager could not approve the leave';
  end if;

  ${as(ALICE)}
  v_expense := (better_supabase.create_expense('${TENANT}', '2099-03-02', 1250, 'EUR') ->> 'id')::uuid;
  perform better_supabase.submit_expense(v_expense);
  ${as(BOB)}
  if better_supabase.decide_expense(v_expense, true) ->> 'status' <> 'approved' then
    raise exception 'the manager could not approve the expense';
  end if;

  ${as(ALICE)}
  perform better_supabase.log_time('${TENANT}', '2099-03-02T09:00:00Z', '2099-03-02T10:00:00Z');
  v_sheet := better_supabase.submit_timesheet('${TENANT}', '2099-03-02');
  ${SERVICE}
  begin
    perform better_supabase.approve_timesheet((v_sheet ->> 'id')::uuid, '${ALICE}');
    raise exception 'decided as the week''s owner';
  exception when others then
    if sqlerrm not like '%never for the owner%' then
      raise;
    end if;
  end;
  ${as(CAROL)}
  begin
    perform better_supabase.approve_timesheet((v_sheet ->> 'id')::uuid, '${BOB}');
    raise exception 'a member decided for another user';
  exception when others then
    if sqlerrm not like '%only the service role%' then
      raise;
    end if;
  end;
  ${SERVICE}
  v_sheet := better_supabase.approve_timesheet((v_sheet ->> 'id')::uuid, '${BOB}');
  if v_sheet ->> 'status' <> 'approved' or v_sheet ->> 'decidedBy' <> '${BOB}' then
    raise exception 'decided for Bob %', v_sheet;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});

describe("options.approver", () => {
  it("defaults to the approve permission", () => {
    const sql = renderBlocks(["employees", "leave"], {
      modules: { leave: { options: { owner: "employee", approvals: false } } },
    })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain("options.approver");
  });

  it("needs the employees block for manager", () => {
    expect(() =>
      renderBlocks(["leave"], {
        modules: {
          leave: { options: { approvals: false, approver: "manager" } },
        },
      }),
    ).toThrow(/needs the employees block's tables/);
  });

  it("refuses another value", () => {
    expect(() =>
      renderBlocks(["employees", "expenses"], {
        modules: {
          expenses: {
            tables: { reports: null, lines: null },
            // SAFETY: the test passes a value the option type rules out.
            options: { approver: "team" },
          },
        },
      }),
    ).toThrow(/approver/);
  });
});
