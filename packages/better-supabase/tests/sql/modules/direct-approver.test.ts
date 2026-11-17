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
  "time-entries": {
    options: { owner: "employee", approvals: false, overlap: "allow" },
  },
  expenses: {
    tables: { reports: null, lines: null },
    options: { owner: "employee", approver: "manager" },
  },
};

const NAMES = ["employees", "leave", "time-entries", "expenses"] as const;

const BOOT = { timeout: 180_000 };

async function run(
  check: string,
  names: readonly string[] = NAMES,
  blocks: AnyBlocksConfig = BLOCKS,
  extra = "",
): Promise<void> {
  const files = renderBlocks(names, { modules: blocks }).map((file) => ({
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
      extra,
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

const DAVE = "77777777-7777-4777-8777-777777777777";
const DAVE_EMPLOYEE = "88888888-8888-4888-8888-888888888888";

// Dave manages Bob, who manages Alice; the app's decider walks the chain.
const CHAIN = `
insert into auth.users (id) values ('${DAVE}') on conflict do nothing;
insert into better_supabase.memberships (organization_id, user_id, role)
  values ('${TENANT}', '${DAVE}', 'member') on conflict do nothing;
insert into better_supabase.employees (id, tenant_id, user_id, name, manager_id)
  values ('${DAVE_EMPLOYEE}', '${TENANT}', '${DAVE}', 'Dave', null);
update better_supabase.employees set manager_id = '${DAVE_EMPLOYEE}' where id = '${BOB_EMPLOYEE}';
create function public.chain_decides(request_id uuid)
returns boolean language sql stable as $$
  with recursive chain as (
    select e.manager_id from better_supabase.leave_requests r
    join better_supabase.employees e on e.id = r.employee_id
    where r.id = request_id
    union
    select e.manager_id from chain c join better_supabase.employees e on e.id = c.manager_id
  )
  select exists (
    select 1 from chain c join better_supabase.employees m on m.id = c.manager_id
    where m.user_id = auth.uid()
  )
$$;
`;

describe("options.decider", BOOT, () => {
  it("lets the app's function admit a manager up the chain and keeps a report out", async () => {
    await expect(
      run(
        `do $$
declare
  v_type uuid;
  v_leave uuid;
begin
  ${as(CAROL)}
  v_type := (better_supabase.save_leave_type('${TENANT}', 'holiday', 'Holiday', 'days', true, false) ->> 'id')::uuid;
  ${as(ALICE)}
  v_leave := (better_supabase.request_leave('${TENANT}', v_type, '2099-03-02', '2099-03-03') ->> 'id')::uuid;
  ${as(DAVE)}
  perform better_supabase.decide_leave_request(v_leave, true);
  if (select approved_at from better_supabase.leave_requests where id = v_leave) is null then
    raise exception 'the chain manager could not approve the leave';
  end if;
  ${as(DAVE)}
  v_leave := (better_supabase.request_leave('${TENANT}', v_type, '2099-04-06', '2099-04-07') ->> 'id')::uuid;
  ${as(ALICE)}
  begin
    perform better_supabase.decide_leave_request(v_leave, true);
    raise exception 'a report decided her manager''s leave';
  exception when others then
    if sqlerrm not like '%not allowed to decide%' then
      raise;
    end if;
  end;
end;
$$;`,
        ["employees", "leave"],
        {
          leave: {
            options: {
              owner: "employee",
              approvals: false,
              decider: "public.chain_decides",
            },
          },
        },
        CHAIN,
      ),
    ).resolves.toBeUndefined();
  });

  it("needs approvals: false and a schema-qualified name", () => {
    expect(() =>
      renderBlocks(["employees", "approvals", "leave"], {
        modules: { leave: { options: { decider: "public.chain_decides" } } },
      }),
    ).toThrow(/needs approvals: false/);
    expect(() =>
      renderBlocks(["employees", "leave"], {
        modules: {
          leave: { options: { approvals: false, decider: "chain_decides" } },
        },
      }),
    ).toThrow(/decider is "schema.function"/);
  });
});

const CAROL_EMPLOYEE = "99999999-9999-4999-8999-999999999999";

const CAROL_ON_TOP = `
insert into better_supabase.employees (id, tenant_id, user_id, name, manager_id)
  values ('${CAROL_EMPLOYEE}', '${TENANT}', '${CAROL}', 'Carol', null);
`;

const decideOwn = (who: string, request: string, expected: string): string => `
  ${as(who)}
  begin
    perform better_supabase.decide_leave_request(${request}, true);
    raise exception '${expected}';
  exception when others then
    if sqlerrm not like '%not allowed to decide%' then
      raise;
    end if;
  end;`;

const topBlocks = (on: boolean): AnyBlocksConfig => ({
  leave: {
    options: {
      owner: "employee",
      approvals: false,
      selfDecideWhenTopOfChain: on,
    },
  },
});

describe("options.selfDecideWhenTopOfChain", BOOT, () => {
  it("keeps refusing the requester when it is off", async () => {
    await expect(
      run(
        `do $$
declare
  v_type uuid;
  v_leave uuid;
begin
  ${as(CAROL)}
  v_type := (better_supabase.save_leave_type('${TENANT}', 'holiday', 'Holiday', 'days', true, false) ->> 'id')::uuid;
  v_leave := (better_supabase.request_leave('${TENANT}', v_type, '2099-03-02', '2099-03-03') ->> 'id')::uuid;
  ${decideOwn(CAROL, "v_leave", "Carol decided her own leave with the option off")}
end;
$$;`,
        ["employees", "leave"],
        topBlocks(false),
        CAROL_ON_TOP,
      ),
    ).resolves.toBeUndefined();
  });

  it("lets a key holder at the top decide their own leave and refuses one with a manager or without the key", async () => {
    await expect(
      run(
        `do $$
declare
  v_type uuid;
  v_leave uuid;
  v_bob uuid;
begin
  ${as(CAROL)}
  v_type := (better_supabase.save_leave_type('${TENANT}', 'holiday', 'Holiday', 'days', true, false) ->> 'id')::uuid;
  v_leave := (better_supabase.request_leave('${TENANT}', v_type, '2099-03-02', '2099-03-03') ->> 'id')::uuid;
  perform better_supabase.decide_leave_request(v_leave, true);
  if (select approved_at is null or decided_by is distinct from '${CAROL}'::uuid from better_supabase.leave_requests where id = v_leave) then
    raise exception 'Carol could not decide her own leave at the top';
  end if;

  ${as(BOB)}
  v_bob := (better_supabase.request_leave('${TENANT}', v_type, '2099-03-09', '2099-03-10') ->> 'id')::uuid;
  ${decideOwn(BOB, "v_bob", "Bob decided his own leave without the approve permission")}

  update better_supabase.employees set manager_id = '${BOB_EMPLOYEE}' where id = '${CAROL_EMPLOYEE}';
  ${as(CAROL)}
  v_leave := (better_supabase.request_leave('${TENANT}', v_type, '2099-04-06', '2099-04-07') ->> 'id')::uuid;
  ${decideOwn(CAROL, "v_leave", "Carol decided her own leave with a manager above her")}

  update better_supabase.employees set status = 'offboarded' where id = '${BOB_EMPLOYEE}';
  ${as(CAROL)}
  v_leave := (better_supabase.request_leave('${TENANT}', v_type, '2099-05-04', '2099-05-05') ->> 'id')::uuid;
  ${decideOwn(CAROL, "v_leave", "Carol decided her own leave under an offboarded manager")}

  update better_supabase.employees set status = 'active', user_id = null where id = '${BOB_EMPLOYEE}';
  ${as(CAROL)}
  v_leave := (better_supabase.request_leave('${TENANT}', v_type, '2099-06-01', '2099-06-02') ->> 'id')::uuid;
  ${decideOwn(CAROL, "v_leave", "Carol decided her own leave under a manager without a login")}
end;
$$;`,
        ["employees", "leave"],
        topBlocks(true),
        CAROL_ON_TOP,
      ),
    ).resolves.toBeUndefined();
  });

  it("needs approvals: false and the employees block", () => {
    expect(() =>
      renderBlocks(["employees", "approvals", "leave"], {
        modules: { leave: { options: { selfDecideWhenTopOfChain: true } } },
      }),
    ).toThrow(/needs approvals: false/);
    expect(() =>
      renderBlocks(["leave"], {
        modules: {
          leave: {
            options: { approvals: false, selfDecideWhenTopOfChain: true },
          },
        },
      }),
    ).toThrow(/needs the employees block's tables/);
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
